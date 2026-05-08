// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// @title Arbitrum Native Helper
/// @notice Helps simulate L1 → Arbitrum native-bridge retryable-ticket delivery in forked tests.
/// @dev Detects `IBridge.MessageDelivered` + `IDelayedMessageProvider.InboxMessageDelivered` events on L1
/// (paired by `messageNum`), decodes the packed retryable payload to `(to, data)`, switches to the L2 fork,
/// pranks `MessageDelivered.sender` (already aliased by the Inbox), and calls `to.call(data)`. Reusable
/// beyond a.DI for any L1 contract that wraps `Inbox.createRetryableTicket`.
/// @dev Note on aliasing: `AbsInbox._submitRetryable` calls `applyL1ToL2Alias(msg.sender)` BEFORE delivering
/// to the Bridge, so `MessageDelivered.sender` is already the L2 alias. The helper does NOT re-alias.
contract ArbitrumNativeHelper is Test {
    /// @dev keccak256("MessageDelivered(uint256,bytes32,address,uint8,address,bytes32,uint256,uint64)")
    bytes32 public constant MESSAGE_DELIVERED_SELECTOR =
        0x5e3c1311ea442664e8b1611bfabef659120ea7a0a2cfc0667700bebc69cbffe1;

    /// @dev keccak256("InboxMessageDelivered(uint256,bytes)")
    bytes32 public constant INBOX_MESSAGE_DELIVERED_SELECTOR =
        0xff64905f73a67fb594e0f940a8075a860db489ad991e032f48c81123eb52d60b;

    /// @dev L1 → L2 address aliasing offset
    uint160 public constant ALIAS_OFFSET = uint160(0x1111000000000000000000000000000000001111);

    /// @dev `MessageDelivered.kind` value for retryable submissions (`L1MessageType_submitRetryableTx`).
    uint8 public constant L1_MESSAGE_TYPE_RETRYABLE = 9;

    struct HelpArgs {
        uint256 l2ForkId; // destination Arbitrum fork id
        address l1Inbox; // optional emitter filter for InboxMessageDelivered (0 = any)
        address l1Bridge; // optional emitter filter for MessageDelivered (0 = any)
        address expectedL1Sender; // optional raw L1 sender filter (0 = any). Compared via applyL1ToL2Alias.
        Vm.Log[] logs; // logs from vm.recordLogs on L1
    }

    error MessageDeliveredMissing(uint256 messageNum);
    error RetryableCallFailed(bytes returnData);
    error MalformedRetryablePayload();

    mapping(uint256 => bool) internal _processedMessageNums;

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helps relay one or more L1 → Arbitrum retryables from recorded logs
    /// @param args the relay arguments
    function help(HelpArgs memory args) external {
        _help(args);
    }

    /// @notice filter logs to those matching `InboxMessageDelivered`
    /// @param logs the recorded logs
    /// @param length the maximum number of matching logs to return
    /// @return found array of matching logs, sized to the actual number found (≤ length)
    function findLogs(Vm.Log[] calldata logs, uint256 length) external pure returns (Vm.Log[] memory found) {
        found = new Vm.Log[](length);
        uint256 idx;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == INBOX_MESSAGE_DELIVERED_SELECTOR) {
                found[idx++] = logs[i];
                if (idx == length) break;
            }
        }
        // shrink array length to the actual match count so trailing zero entries aren't returned
        assembly {
            mstore(found, idx)
        }
    }

    /// @notice compute the L2 alias of an L1 address
    function applyL1ToL2Alias(address l1) public pure returns (address) {
        unchecked {
            return address(uint160(l1) + ALIAS_OFFSET);
        }
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice scan logs for retryables and relay each to the L2 fork
    function _help(HelpArgs memory args) internal {
        uint256 prevForkId = vm.activeFork();

        for (uint256 i; i < args.logs.length; ++i) {
            Vm.Log memory l = args.logs[i];
            if (l.topics.length < 2) continue;
            if (l.topics[0] != INBOX_MESSAGE_DELIVERED_SELECTOR) continue;
            if (args.l1Inbox != address(0) && l.emitter != args.l1Inbox) continue;

            uint256 messageNum = uint256(l.topics[1]);
            if (_processedMessageNums[messageNum]) continue;

            (bool foundPair, address aliasedSender, uint8 kind) =
                _findPairedMessageDelivered(args.logs, messageNum, args.l1Bridge);
            if (!foundPair) revert MessageDeliveredMissing(messageNum);
            if (kind != L1_MESSAGE_TYPE_RETRYABLE) continue;
            if (
                args.expectedL1Sender != address(0)
                    && aliasedSender != applyL1ToL2Alias(args.expectedL1Sender)
            ) continue;

            bytes memory payload = abi.decode(l.data, (bytes));
            (address to, bytes memory innerData) = _decodeRetryablePayload(payload);

            _processedMessageNums[messageNum] = true;

            vm.selectFork(args.l2ForkId);
            vm.prank(aliasedSender, aliasedSender);
            (bool ok, bytes memory ret) = to.call(innerData);
            if (!ok) revert RetryableCallFailed(ret);
        }

        vm.selectFork(prevForkId);
    }

    /// @notice locate the `MessageDelivered` event paired with a given `messageNum`
    /// @return found whether a paired event was found
    /// @return aliasedSender the already-aliased L1 sender stored by the Inbox
    /// @return kind the message kind (9 for retryables)
    function _findPairedMessageDelivered(Vm.Log[] memory logs, uint256 messageNum, address l1Bridge)
        internal
        pure
        returns (bool found, address aliasedSender, uint8 kind)
    {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.topics.length < 2) continue;
            if (l.topics[0] != MESSAGE_DELIVERED_SELECTOR) continue;
            if (l1Bridge != address(0) && l.emitter != l1Bridge) continue;
            if (uint256(l.topics[1]) != messageNum) continue;

            // MessageDelivered.data = abi.encode(inbox, kind, sender, messageDataHash, baseFeeL1, timestamp)
            (, uint8 _kind, address _sender,,,) =
                abi.decode(l.data, (address, uint8, address, bytes32, uint256, uint64));
            return (true, _sender, _kind);
        }
        return (false, address(0), 0);
    }

    /// @notice decode the abi-packed retryable payload from `Inbox.createRetryableTicket`
    /// @dev Layout (from `nitro-contracts/AbsInbox._submitRetryable`):
    ///   uint256(to) | l2CallValue | msg.value | maxSubmissionCost |
    ///   uint256(excessFeeRefundAddress) | uint256(callValueRefundAddress) |
    ///   gasLimit | maxFeePerGas | uint256(callDataLength) | data
    function _decodeRetryablePayload(bytes memory payload) internal pure returns (address to, bytes memory data) {
        if (payload.length < 9 * 32) revert MalformedRetryablePayload();

        uint256 toWord;
        uint256 callDataLength;
        assembly {
            toWord := mload(add(payload, 32))
            callDataLength := mload(add(payload, mul(32, 9)))
        }

        if (payload.length < 9 * 32 + callDataLength) revert MalformedRetryablePayload();
        to = address(uint160(toWord));

        data = new bytes(callDataLength);
        for (uint256 i; i < callDataLength; ++i) {
            data[i] = payload[9 * 32 + i];
        }
    }
}
