// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import "solady/src/utils/LibString.sol";

/// local imports
import {TypeCasts} from "../libraries/TypeCasts.sol";

interface IMessageBus {
    function sendMessage(address _receiver, uint256 _dstChainId, bytes calldata _message) external payable;
    function calcFee(bytes calldata _message) external view returns (uint256);
}

interface IMessageReceiverApp {
    enum ExecutionStatus {
        Fail, // execution failed, finalized
        Success, // execution succeeded, finalized
        Retry // execution rejected, can retry later

    }

    function executeMessage(address _sender, uint64 _srcChainId, bytes calldata _message, address _executor)
        external
        payable
        returns (ExecutionStatus);
}

/// @title Celer Helper
/// @notice helps simulate the message transfer using celer im message bridge
contract CelerHelper is Test {
    /// @dev is the default event selector if not specified by the user
    bytes32 constant MESSAGE_EVENT_SELECTOR = 0xce3972bfffe49d317e1d128047a97a3d86b25c94f6f04409f988ef854d25e0e4;

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helps with multiple destination transfers
    /// @param fromChainId represents the source chain id
    /// @param fromMessageBus represents the source message bus address (cannot be fetched from logs)
    /// @param toMessageBus represents the destination message bus addresses
    /// @param expDstChainId represents the expected destination chain ids
    /// @param forkId array of destination fork ids (localized to your testing)
    /// @param logs array of logs
    function help(
        uint64 fromChainId,
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

    /// @notice helps with a single destination transfer
    /// @param fromChainId represents the source chain id
    /// @param fromMessageBus represents the source message bus address (cannot be fetched from logs)
    /// @param toMessageBus represents the destination message bus address
    /// @param expDstChainId represents the expected destination chain id
    /// @param forkId represents the destination fork id (localized to your testing)
    /// @param logs array of logs
    function help(
        uint64 fromChainId,
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(fromChainId, fromMessageBus, toMessageBus, expDstChainId, MESSAGE_EVENT_SELECTOR, forkId, logs, false);
    }

    /// @notice helps with a single destination transfer with a specific event selector
    /// @param fromChainId represents the source chain id
    /// @param fromMessageBus represents the source message bus address (cannot be fetched from logs)
    /// @param toMessageBus represents the destination message bus address
    /// @param expDstChainId represents the expected destination chain id
    /// @param eventSelector represents the event selector
    /// @param forkId represents the destination fork id (localized to your testing)
    /// @param logs array of logs
    function help(
        uint64 fromChainId,
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(fromChainId, fromMessageBus, toMessageBus, expDstChainId, eventSelector, forkId, logs, false);
    }

    /// @notice helps with a single destination transfer and estimates gas
    /// @param fromChainId represents the source chain id
    /// @param fromMessageBus represents the source message bus address (cannot be fetched from logs)
    /// @param toMessageBus represents the destination message bus address
    /// @param expDstChainId represents the expected destination chain id
    /// @param forkId represents the destination fork id (localized to your testing)
    /// @param logs array of logs
    function helpWithEstimates(
        uint64 fromChainId,
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

    /// @notice helps with a single destination transfer with a specific event selector and estimates gas
    /// @param fromChainId represents the source chain id
    /// @param fromMessageBus represents the source message bus address (cannot be fetched from logs)
    /// @param toMessageBus represents the destination message bus address
    /// @param expDstChainId represents the expected destination chain id
    /// @param forkId represents the destination fork id (localized to your testing)
    /// @param eventSelector represents the event selector
    /// @param logs array of logs
    function helpWithEstimates(
        uint64 fromChainId,
        /// @dev is inevitable, cannot fetch form logs
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        uint256 forkId,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_CELER_ESTIMATES", false);
        _help(fromChainId, fromMessageBus, toMessageBus, expDstChainId, eventSelector, forkId, logs, enableEstimates);
    }

    /// @notice helps with multiple destination transfers and estimates gas
    /// @param fromChainId represents the source chain id
    /// @param fromMessageBus represents the source message bus address (cannot be fetched from logs)
    /// @param toMessageBus represents the destination message bus addresses
    /// @param expDstChainId represents the expected destination chain ids
    /// @param forkId array of destination fork ids (localized to your testing)
    /// @param logs array of logs
    function helpWithEstimates(
        uint64 fromChainId,
        /// @dev is inevitable, cannot fetch form logs
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

    /// @notice finds logs with the default event selector
    /// @param logs array of logs
    /// @param length expected number of logs
    /// @return HLLogs array of found logs
    function findLogs(Vm.Log[] calldata logs, uint256 length) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, MESSAGE_EVENT_SELECTOR, length);
    }

    /// @notice finds logs with a specific event selector
    /// @param logs array of logs
    /// @param eventSelector event selector
    /// @param length expected number of logs
    /// @return HLLogs array of found logs
    function findLogs(Vm.Log[] calldata logs, bytes32 eventSelector, uint256 length)
        external
        pure
        returns (Vm.Log[] memory HLLogs)
    {
        return _findLogs(logs, eventSelector, length);
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice internal function to help with destination transfers
    /// @param fromChainId represents the source chain id
    /// @param fromMessageBus represents the source message bus address
    /// @param toMessageBus represents the destination message bus address
    /// @param expDstChainId represents the expected destination chain id
    /// @param eventSelector represents the event selector
    /// @param forkId represents the destination fork id (localized to your testing)
    /// @param logs array of logs
    /// @param enableEstimates flag to enable gas estimates
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

            if (log.topics[0] == eventSelector && log.emitter == fromMessageBus) {
                bytes memory data = log.data;
                address sender = TypeCasts.bytes32ToAddress(log.topics[1]);

                _handle(fromChainId, sender, data, expDstChainId);

                vm.stopBroadcast();
                vm.selectFork(prevForkId);
                if (enableEstimates) {
                    emit log_named_uint("gasEstimate", _estimateGas(fromMessageBus, data));
                }
                vm.selectFork(forkId);
                vm.startBroadcast(toMessageBus);
            }
        }

        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }

    /// @notice handles the message execution
    /// @param fromChainId represents the source chain id
    /// @param sender represents the sender address
    /// @param data represents the message data
    /// @param expDstChainId represents the expected destination chain id
    function _handle(uint64 fromChainId, address sender, bytes memory data, uint64 expDstChainId) internal {
        bytes32 receiver;
        uint256 dstChainId;

        bytes memory message = bytes(LibString.slice(string(data), 0xA0));

        assembly {
            receiver := mload(add(data, 0x20))
            dstChainId := mload(add(data, 0x40))
        }

        if (uint64(dstChainId) == expDstChainId) {
            IMessageReceiverApp(TypeCasts.bytes32ToAddress(receiver)).executeMessage(
                sender, fromChainId, message, address(this)
            );
        }
    }

    /// @notice estimates gas for message execution
    /// @param fromMessageBus represents the source message bus address
    /// @param message represents the message data
    /// @return gasEstimate the estimated gas
    function _estimateGas(address fromMessageBus, bytes memory message) internal view returns (uint256 gasEstimate) {
        /// NOTE: In celer two fees are involved, but only the 1st one is
        /// estimated here
        /// 1: Sync, Sign and Store Cost [Source Fees]
        /// 2: Execution Cost [Application Specific]
        gasEstimate = IMessageBus(fromMessageBus).calcFee(message);
    }

    /// @notice internal function to find logs with a specific event selector
    /// @param logs array of logs
    /// @param dispatchSelector event selector
    /// @param length expected number of logs
    /// @return CelerLogs array of found logs
    function _findLogs(Vm.Log[] memory logs, bytes32 dispatchSelector, uint256 length)
        internal
        pure
        returns (Vm.Log[] memory CelerLogs)
    {
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
