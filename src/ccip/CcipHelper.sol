// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
import {Client} from "./interfaces/Client.sol";
import {Internal} from "./interfaces/Internal.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IAny2EVMMessageReceiver} from "./interfaces/IAny2EVMMessageReceiver.sol";

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC20Like {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Mirror of the `Router.OffRamp` struct + `getOffRamps()` view from the concrete `Router.sol`. Defined locally
/// to avoid pulling Router.sol's transitive shared-contracts dependency.
interface IRouterWithOffRamps {
    struct OffRamp {
        uint64 sourceChainSelector;
        address offRamp;
    }

    function getOffRamps() external view returns (OffRamp[] memory);
}


/// @title CcipHelper
/// @notice Helps simulate Chainlink CCIP message + token transfers across forked chains.
/// @dev Detects both CCIP 1.6 `OnRamp.CCIPMessageSent(uint64,uint64,Internal.EVM2AnyRampMessage)` and CCIP 1.5
/// `EVM2EVMOnRamp.CCIPSendRequested(EVM2EVMMessage)` source-side events. For each match it switches to the destination
/// fork, resolves the OffRamp via `Router.getOffRamps()`, deals destination tokens to the receiver (1.6 only), and
/// pranks as the OffRamp to call `IRouter.routeMessage` so the receiver's `ccipReceive` runs under realistic
/// `onlyOffRamp` semantics.
/// @dev This helper exercises the receiver callback only. It does NOT exercise the real `OffRamp.executeSingleMessage`
/// path, so `TokenPool.releaseOrMint`, rate limits, RMN curse checks, and CCTP attestations are NOT simulated. Tokens
/// are credited to the receiver via `StdCheats.deal`.
/// @dev For CCIP 1.5 token transfers the 1.5 message carries only the SOURCE token address. The helper resolves the
/// destination token on the dest fork via `EVM2EVMOffRamp.getPoolBySourceToken(srcToken).getToken()` and `deal`s it.
contract CcipHelper is Test {
    /// @dev keccak256 of the CCIP 1.6 `OnRamp.CCIPMessageSent` event signature.
    bytes32 public constant CCIP_MESSAGE_SENT_SELECTOR =
        0x192442a2b2adb6a7948f097023cb6b57d29d3a7a5dd33e6666d33c39cc456f32;

    /// @dev keccak256 of the CCIP 1.5 `EVM2EVMOnRamp.CCIPSendRequested` event signature.
    /// signature: CCIPSendRequested((uint64,address,address,uint64,uint256,bool,uint64,address,uint256,bytes,(address,uint256)[],bytes[],bytes32))
    bytes32 public constant CCIP_SEND_REQUESTED_SELECTOR =
        0xd0c3c799bf9e2639de44391e7f524d229b2b55f5b1ea94b2bf7da42f7243dddd;

    /// @dev Vendored CCIP 1.5 `Internal.EVM2EVMMessage` struct. Layout matches the legacy
    /// `smartcontractkit/ccip` repo at v1.5.x. Used only for log decoding.
    struct EVM2EVMMessage {
        uint64 sourceChainSelector;
        address sender;
        address receiver;
        uint64 sequenceNumber;
        uint256 gasLimit;
        bool strict;
        uint64 nonce;
        address feeToken;
        uint256 feeTokenAmount;
        bytes data;
        Client.EVMTokenAmount[] tokenAmounts;
        bytes[] sourceTokenData;
        bytes32 messageId;
    }

    /// @dev Vendored CCIP 1.5 `Internal.SourceTokenData` struct. Encoded by the OnRamp into
    /// `EVM2EVMMessage.sourceTokenData[i]` so the destination token address is recoverable on the dest fork without
    /// any registry lookup.
    struct SourceTokenData {
        bytes sourcePoolAddress;
        bytes destTokenAddress;
        bytes extraData;
        uint32 destGasAmount;
    }

    /// @dev Standard `gasForCallExactCheck` value used by mainnet OffRamps.
    uint16 public constant GAS_FOR_CALL_EXACT_CHECK = 5_000;

    /// @dev CCIP's empty-extraArgs default gas limit (matches OffRamp + chainlink-local).
    uint256 public constant DEFAULT_GAS_LIMIT = 200_000;

    struct HelpArgs {
        uint256 dstForkId; // destination fork id created via vm.createSelectFork
        address dstRouter; // destination chain Router (Router 1.2.0)
        uint64 expDstChainSelector; // expected destination chain selector; 0 ⇒ accept any
        address srcOnRamp; // expected emitter of CCIPMessageSent; address(0) ⇒ accept any
        Vm.Log[] logs; // logs captured via vm.recordLogs / vm.getRecordedLogs
    }

    error NoOffRampsRegistered(address router);
    error NoOffRampForSource(uint64 sourceChainSelector);
    error InvalidExtraArgsTag(bytes4 tag);
    error TooManyTokens(uint256 count);
    error ReceiverCallFailed(bytes returnData);
    error V15SourceTokenDataMalformed();

    mapping(bytes32 => bool) internal _processedMessageIds;

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helps relay CCIP messages to a single destination
    /// @param args the relay arguments
    function help(HelpArgs memory args) external {
        _help(args, false);
    }

    /// @notice helps relay CCIP messages to multiple destinations
    /// @param argsArray array of per-destination relay arguments
    function help(HelpArgs[] memory argsArray) external {
        for (uint256 i; i < argsArray.length; ++i) {
            _help(argsArray[i], false);
        }
    }

    /// @notice relays CCIP messages and emits the source-side fee paid for each delivered message
    /// @param args the relay arguments
    /// @dev emits `ccipFeePaid` (uint256), `ccipFeeToken` (address), `ccipFeeValueJuels` (uint256) per message.
    function helpWithEstimates(HelpArgs memory args) external {
        _help(args, true);
    }

    /// @notice filter logs to those matching either `CCIPMessageSent` (1.6) or `CCIPSendRequested` (1.5)
    /// @param logs the recorded logs
    /// @param length the expected number of matching logs
    /// @return found array of matching logs
    function findLogs(Vm.Log[] calldata logs, uint256 length)
        external
        pure
        returns (Vm.Log[] memory found)
    {
        found = new Vm.Log[](length);
        uint256 idx;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            bytes32 sel = logs[i].topics[0];
            if (sel == CCIP_MESSAGE_SENT_SELECTOR || sel == CCIP_SEND_REQUESTED_SELECTOR) {
                found[idx++] = logs[i];
                if (idx == length) break;
            }
        }
    }

    /// @notice filter logs by an explicit selector
    /// @param logs the recorded logs
    /// @param selector the event selector to match on `topics[0]`
    /// @param length the expected number of matching logs
    /// @return found array of matching logs
    function findLogs(Vm.Log[] calldata logs, bytes32 selector, uint256 length)
        external
        pure
        returns (Vm.Log[] memory found)
    {
        return _findLogs(logs, selector, length);
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice scans logs, decodes the matching CCIP message, and routes each match to the destination fork
    function _help(HelpArgs memory args, bool emitEstimates) internal {
        uint256 prevForkId = vm.activeFork();

        for (uint256 i; i < args.logs.length; ++i) {
            Vm.Log memory l = args.logs[i];
            if (l.topics.length == 0) continue;
            if (args.srcOnRamp != address(0) && l.emitter != args.srcOnRamp) continue;

            bytes32 sel = l.topics[0];
            if (sel == CCIP_MESSAGE_SENT_SELECTOR) {
                _processV16Log(l, args, emitEstimates);
            } else if (sel == CCIP_SEND_REQUESTED_SELECTOR) {
                _processV15Log(l, args, emitEstimates);
            }
        }

        vm.selectFork(prevForkId);
    }

    /// @notice handle a CCIP 1.6 `CCIPMessageSent` log
    function _processV16Log(Vm.Log memory l, HelpArgs memory args, bool emitEstimates) internal {
        if (l.topics.length < 3) return;

        uint64 destChainSelector = uint64(uint256(l.topics[1]));
        if (args.expDstChainSelector != 0 && destChainSelector != args.expDstChainSelector) return;

        Internal.EVM2AnyRampMessage memory m = abi.decode(l.data, (Internal.EVM2AnyRampMessage));

        if (_processedMessageIds[m.header.messageId]) return;
        _processedMessageIds[m.header.messageId] = true;

        if (emitEstimates) {
            emit log_named_uint("ccipFeePaid", m.feeTokenAmount);
            emit log_named_address("ccipFeeToken", m.feeToken);
            emit log_named_uint("ccipFeeValueJuels", m.feeValueJuels);
        }

        Client.GenericExtraArgsV2 memory extra = _decodeExtraArgs(m.extraArgs);

        vm.selectFork(args.dstForkId);
        _routeV16(args.dstRouter, m, extra);
    }

    /// @notice handle a CCIP 1.5 `CCIPSendRequested` log
    function _processV15Log(Vm.Log memory l, HelpArgs memory args, bool emitEstimates) internal {
        EVM2EVMMessage memory m = abi.decode(l.data, (EVM2EVMMessage));

        if (m.tokenAmounts.length > 1) revert TooManyTokens(m.tokenAmounts.length);

        if (_processedMessageIds[m.messageId]) return;
        _processedMessageIds[m.messageId] = true;

        if (emitEstimates) {
            emit log_named_uint("ccipFeePaid", m.feeTokenAmount);
            emit log_named_address("ccipFeeToken", m.feeToken);
        }

        vm.selectFork(args.dstForkId);
        _routeV15(args.dstRouter, m);
    }

    /// @notice CCIP 1.6 destination-fork routing
    function _routeV16(
        address dstRouter,
        Internal.EVM2AnyRampMessage memory m,
        Client.GenericExtraArgsV2 memory extra
    ) internal {
        if (m.tokenAmounts.length > 1) revert TooManyTokens(m.tokenAmounts.length);

        address receiver = abi.decode(m.receiver, (address));

        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](m.tokenAmounts.length);
        if (m.tokenAmounts.length == 1) {
            address destToken = address(uint160(bytes20(m.tokenAmounts[0].destTokenAddress)));
            uint256 amount = m.tokenAmounts[0].amount;
            destTokenAmounts[0] = Client.EVMTokenAmount({token: destToken, amount: amount});
            uint256 prior = IERC20Like(destToken).balanceOf(receiver);
            deal(destToken, receiver, prior + amount);
        }

        // Mirror OffRamp's pre-call gate: skip if data+gasLimit empty, or receiver is EOA, or no ERC-165 support.
        bool hasData = m.data.length > 0 || extra.gasLimit > 0;
        bool hasCode = receiver.code.length > 0;
        bool isReceiver = hasCode && _supportsReceiverInterface(receiver);
        if (!hasData || !hasCode || !isReceiver) return;

        Client.Any2EVMMessage memory anyMsg = Client.Any2EVMMessage({
            messageId: m.header.messageId,
            sourceChainSelector: m.header.sourceChainSelector,
            sender: abi.encode(m.sender),
            data: m.data,
            destTokenAmounts: destTokenAmounts
        });

        address offRamp = _resolveOffRamp(dstRouter, m.header.sourceChainSelector);

        vm.prank(offRamp);
        (bool success, bytes memory retData,) =
            IRouter(dstRouter).routeMessage(anyMsg, GAS_FOR_CALL_EXACT_CHECK, extra.gasLimit, receiver);
        if (!success) revert ReceiverCallFailed(retData);
    }

    /// @notice CCIP 1.5 destination-fork routing
    /// @dev Destination token is decoded from `EVM2EVMMessage.sourceTokenData[i]` which the 1.5 OnRamp populates from
    /// the source pool's `lockOrBurn` return (`destTokenAddress`). No OffRamp/registry lookup needed.
    function _routeV15(address dstRouter, EVM2EVMMessage memory m) internal {
        Client.EVMTokenAmount[] memory destTokenAmounts = new Client.EVMTokenAmount[](m.tokenAmounts.length);
        if (m.tokenAmounts.length == 1) {
            address destToken = _decodeV15DestToken(m.sourceTokenData[0]);
            uint256 amount = m.tokenAmounts[0].amount;
            destTokenAmounts[0] = Client.EVMTokenAmount({token: destToken, amount: amount});
            uint256 prior = IERC20Like(destToken).balanceOf(m.receiver);
            deal(destToken, m.receiver, prior + amount);
        }

        Client.Any2EVMMessage memory anyMsg = Client.Any2EVMMessage({
            messageId: m.messageId,
            sourceChainSelector: m.sourceChainSelector,
            sender: abi.encode(m.sender),
            data: m.data,
            destTokenAmounts: destTokenAmounts
        });

        bool hasData = m.data.length > 0 || m.gasLimit > 0;
        bool hasCode = m.receiver.code.length > 0;
        bool isReceiver = hasCode && _supportsReceiverInterface(m.receiver);
        if (!hasData || !hasCode || !isReceiver) return;

        address offRamp = _resolveOffRamp(dstRouter, m.sourceChainSelector);

        vm.prank(offRamp);
        (bool success, bytes memory retData,) =
            IRouter(dstRouter).routeMessage(anyMsg, GAS_FOR_CALL_EXACT_CHECK, m.gasLimit, m.receiver);
        if (!success) revert ReceiverCallFailed(retData);
    }

    /// @notice decode CCIP 1.5 sourceTokenData[i] = abi.encode(SourceTokenData) and extract the dest token address
    function _decodeV15DestToken(bytes memory sourceTokenDataBytes) internal pure returns (address) {
        SourceTokenData memory s = abi.decode(sourceTokenDataBytes, (SourceTokenData));
        bytes memory destAddr = s.destTokenAddress;
        if (destAddr.length != 32 && destAddr.length != 20) revert V15SourceTokenDataMalformed();
        return abi.decode(destAddr, (address));
    }

    /// @notice resolve newest OffRamp registered for sourceChainSelector via backwards iteration
    function _resolveOffRamp(address dstRouter, uint64 sourceChainSelector) internal view returns (address) {
        IRouterWithOffRamps.OffRamp[] memory offRamps = IRouterWithOffRamps(dstRouter).getOffRamps();
        if (offRamps.length == 0) revert NoOffRampsRegistered(dstRouter);
        for (uint256 i = offRamps.length; i > 0; --i) {
            if (offRamps[i - 1].sourceChainSelector == sourceChainSelector) {
                return offRamps[i - 1].offRamp;
            }
        }
        revert NoOffRampForSource(sourceChainSelector);
    }

    /// @notice decode CCIP `extraArgs` handling V2 tag, V1 tag, and empty-default
    function _decodeExtraArgs(bytes memory extraArgs) internal pure returns (Client.GenericExtraArgsV2 memory) {
        if (extraArgs.length == 0) {
            return Client.GenericExtraArgsV2({gasLimit: DEFAULT_GAS_LIMIT, allowOutOfOrderExecution: false});
        }
        bytes4 tag = bytes4(extraArgs);
        bytes memory body = _slice(extraArgs, 4);

        if (tag == Client.GENERIC_EXTRA_ARGS_V2_TAG) {
            return abi.decode(body, (Client.GenericExtraArgsV2));
        }
        if (tag == Client.EVM_EXTRA_ARGS_V1_TAG) {
            uint256 g = abi.decode(body, (uint256));
            return Client.GenericExtraArgsV2({gasLimit: g, allowOutOfOrderExecution: false});
        }
        revert InvalidExtraArgsTag(tag);
    }

    /// @notice ERC-165 check for IAny2EVMMessageReceiver. Wrapped in low-level call to swallow unsupported reverts.
    function _supportsReceiverInterface(address receiver) internal view returns (bool) {
        bytes4 iid = type(IAny2EVMMessageReceiver).interfaceId;
        (bool ok, bytes memory ret) =
            receiver.staticcall(abi.encodeWithSelector(IERC165.supportsInterface.selector, iid));
        return ok && ret.length >= 32 && abi.decode(ret, (bool));
    }

    /// @notice slice a memory bytes array starting at `start` to the end
    function _slice(bytes memory data, uint256 start) internal pure returns (bytes memory out) {
        require(start <= data.length, "CcipHelper: slice oob");
        uint256 len = data.length - start;
        out = new bytes(len);
        for (uint256 i; i < len; ++i) {
            out[i] = data[start + i];
        }
    }

    /// @notice find logs with a specific selector
    function _findLogs(Vm.Log[] memory logs, bytes32 selector, uint256 length)
        internal
        pure
        returns (Vm.Log[] memory found)
    {
        found = new Vm.Log[](length);
        uint256 idx;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == selector) {
                found[idx++] = logs[i];
                if (idx == length) break;
            }
        }
    }
}
