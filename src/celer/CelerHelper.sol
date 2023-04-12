// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "solady/utils/LibString.sol";
import {TypeCasts} from "../hyperlane/lib/TypeCasts.sol";

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
///
/// @notice will help developers test celer im using forked mainnets (Near mainnet execution)
/// @notice supports only EVM chains at this moment & single transfers
contract CelerHelper is Test {
    bytes32 constant MESSAGE_EVENT_SELECTOR =
        0xce3972bfffe49d317e1d128047a97a3d86b25c94f6f04409f988ef854d25e0e4;

    function help(
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(
            fromMessageBus,
            toMessageBus,
            expDstChainId,
            MESSAGE_EVENT_SELECTOR,
            forkId,
            logs
        );
    }

    function helpWithEstimates() external {}

    function _help(
        address fromMessageBus,
        address toMessageBus,
        uint64 expDstChainId,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) internal {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(forkId);
        vm.startBroadcast(toMessageBus);

        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];

            if (
                log.topics[0] == eventSelector && log.emitter == fromMessageBus
            ) {
                address sender = TypeCasts.bytes32ToAddress(log.topics[1]);

                bytes memory data = log.data;

                bytes32 receiver;
                uint256 dstChainId;
                uint256 fees;

                bytes memory message = bytes(
                    LibString.slice(string(data), 0xA0)
                );

                assembly {
                    receiver := mload(add(data, 0x20))
                    dstChainId := mload(add(data, 0x40))
                    fees := mload(add(data, 0x80))
                }

                if (uint64(dstChainId) == expDstChainId) {
                    IMessageReceiverApp(TypeCasts.bytes32ToAddress(receiver))
                        .executeMessage(sender, 1, message, address(this));
                }
            }
        }

        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }
}
