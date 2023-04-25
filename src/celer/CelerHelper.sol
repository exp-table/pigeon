// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "solady/utils/LibString.sol";
import {TypeCasts} from "../hyperlane/lib/TypeCasts.sol";

interface IMessageBus {
    /**
     * @notice Send a message to a contract on another chain.
     * Sender needs to make sure the uniqueness of the message Id, which is computed as
     * hash(type.MessageOnly, sender, receiver, srcChainId, srcTxHash, dstChainId, message).
     * If messages with the same Id are sent, only one of them will succeed at dst chain..
     * A fee is charged in the native gas token.
     * @param _receiver The address of the destination app contract.
     * @param _dstChainId The destination chain ID.
     * @param _message Arbitrary message bytes to be decoded by the destination app contract.
     */
    function sendMessage(
        address _receiver,
        uint256 _dstChainId,
        bytes calldata _message
    ) external payable;

    function calcFee(bytes calldata _message) external view returns (uint256);
}

interface IMessageReceiverApp {
    enum ExecutionStatus {
        Fail, // execution failed, finalized
        Success, // execution succeeded, finalized
        Retry // execution rejected, can retry later
    }

    /**
     * @notice Called by MessageBus to execute a message
     * @param _sender The address of the source app contract
     * @param _srcChainId The source chain ID where the transfer is originated from
     * @param _message Arbitrary message bytes originated from and encoded by the source app contract
     * @param _executor Address who called the MessageBus execution function
     */
    function executeMessage(
        address _sender,
        uint64 _srcChainId,
        bytes calldata _message,
        address _executor
    ) external payable returns (ExecutionStatus);
}

/// @title Celer IM Cross-Chain Helper
/// @dev use the `help` and `helpWithEstimates` functions to process any message delivery
/// @notice will help developers test celer im using forked mainnets (Near mainnet execution)
/// @notice supports only EVM chains at this moment & single transfers
contract CelerHelper is Test {
    bytes32 constant MESSAGE_EVENT_SELECTOR =
        0xce3972bfffe49d317e1d128047a97a3d86b25c94f6f04409f988ef854d25e0e4;

    /// @dev to process multi destination payloads
    function help(
        uint64 fromChainId, /// @dev is inevitable, cannot fetch form logs
        address fromMessageBus,
        address[] memory toMessageBus,
        uint64[] memory expDstChainId,
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i = 0; i < toMessageBus.length; i++) {
            _help(
                fromChainId,
                fromMessageBus,
                toMessageBus[i],
                expDstChainId[i],
                MESSAGE_EVENT_SELECTOR,
                forkId[i],
                logs,
                false
            );
        }
    }

    function help(
        uint64 fromChainId, /// @dev is inevitable, cannot fetch form logs
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(
            fromChainId,
            fromMessageBus,
            toMessageBus,
            expDstChainId,
            MESSAGE_EVENT_SELECTOR,
            forkId,
            logs,
            false
        );
    }

    function help(
        uint64 fromChainId, /// @dev is inevitable, cannot fetch form logs
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(
            fromChainId,
            fromMessageBus,
            toMessageBus,
            expDstChainId,
            eventSelector,
            forkId,
            logs,
            false
        );
    }

    function helpWithEstimates(
        uint64 fromChainId, /// @dev is inevitable, cannot fetch form logs
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_CELER_ESTIMATES", false);
        _help(
            fromChainId,
            fromMessageBus,
            toMessageBus,
            expDstChainId,
            MESSAGE_EVENT_SELECTOR,
            forkId,
            logs,
            enableEstimates
        );
    }

    function helpWithEstimates(
        uint64 fromChainId, /// @dev is inevitable, cannot fetch form logs
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        uint256 forkId,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_CELER_ESTIMATES", false);
        _help(
            fromChainId,
            fromMessageBus,
            toMessageBus,
            expDstChainId,
            eventSelector,
            forkId,
            logs,
            enableEstimates
        );
    }

    function helpWithEstimates(
        uint64 fromChainId, /// @dev is inevitable, cannot fetch form logs
        address fromMessageBus,
        address[] memory toMessageBus,
        uint64[] memory expDstChainId,
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_CELER_ESTIMATES", false);
        for (uint256 i = 0; i < toMessageBus.length; i++) {
            _help(
                fromChainId,
                fromMessageBus,
                toMessageBus[i],
                expDstChainId[i],
                MESSAGE_EVENT_SELECTOR,
                forkId[i],
                logs,
                enableEstimates
            );
        }
    }

    function findLogs(
        Vm.Log[] calldata logs,
        uint256 length
    ) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, MESSAGE_EVENT_SELECTOR, length);
    }

    function findLogs(
        Vm.Log[] calldata logs,
        bytes32 eventSelector,
        uint256 length
    ) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, eventSelector, length);
    }

    function _help(
        uint64 fromChainId,
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] calldata logs,
        bool enableEstimates
    ) internal {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(forkId);
        vm.startBroadcast(toMessageBus);

        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];

            if (
                log.topics[0] == eventSelector && log.emitter == fromMessageBus
            ) {
                bytes memory data = log.data;
                address sender = TypeCasts.bytes32ToAddress(log.topics[1]);

                _handle(fromChainId, sender, data, expDstChainId);

                vm.stopBroadcast();
                vm.selectFork(prevForkId);
                if (enableEstimates) {
                    emit log_named_uint(
                        "gasEstimate",
                        _estimateGas(fromMessageBus, data)
                    );
                }
                vm.selectFork(forkId);
                vm.startBroadcast(toMessageBus);
            }
        }

        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }

    function _handle(
        uint64 fromChainId,
        address sender,
        bytes memory data,
        uint64 expDstChainId
    ) internal {
        bytes32 receiver;
        uint256 dstChainId;

        bytes memory message = bytes(LibString.slice(string(data), 0xA0));

        assembly {
            receiver := mload(add(data, 0x20))
            dstChainId := mload(add(data, 0x40))
        }

        if (uint64(dstChainId) == expDstChainId) {
            IMessageReceiverApp(TypeCasts.bytes32ToAddress(receiver))
                .executeMessage(sender, fromChainId, message, address(this));
        }
    }

    function _estimateGas(
        address fromMessageBus,
        bytes memory message
    ) internal returns (uint256 gasEstimate) {
        /// NOTE: In celer two fees are involved, but only the 1st one is
        /// estimated here
        /// 1: Sync, Sign and Store Cost [Source Fees]
        /// 2: Execution Cost [Application Specific]
        gasEstimate = IMessageBus(fromMessageBus).calcFee(message);
    }

    function _findLogs(
        Vm.Log[] memory logs,
        bytes32 dispatchSelector,
        uint256 length
    ) internal pure returns (Vm.Log[] memory CelerLogs) {
        CelerLogs = new Vm.Log[](length);

        uint256 currentIndex = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == dispatchSelector) {
                CelerLogs[currentIndex] = logs[i];
                currentIndex++;

                if (currentIndex == length) {
                    break;
                }
            }
        }
    }
}
