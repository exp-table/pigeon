// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "./lib/PayloadDecoder.sol";
import "./lib/InternalStructs.sol";

interface IWormholeReceiver {
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable;
}

contract WormholeHelper is Test {
    /// @dev LogMessagePublished (index_topic_1 address sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)
    bytes32 constant MESSAGE_EVENT_SELECTOR =
        0x6eb224fb001ed210e379b335e35efe88672a8ce935d981a6896b27ffdf52a3b2;

    /// @dev to process cross-chain message delivery
    function help(
        uint16 srcChainId,
        uint256 forkId,
        address dstAddress,
        address dstRelayer,
        Vm.Log[] calldata logs
    ) external {
        _help(
            srcChainId,
            forkId,
            dstAddress,
            dstRelayer,
            MESSAGE_EVENT_SELECTOR,
            logs
        );
    }

    struct LocalVars {
        uint64 sequence;
        uint32 nonce;
        bytes payload;
    }

    /// @dev helper to process cross-chain messages
    function _help(
        uint16 srcChainId,
        uint256 forkId,
        address dstAddress,
        address dstRelayer,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) internal {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(forkId);
        vm.startBroadcast(dstRelayer);

        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];

            if (log.topics[0] == eventSelector) {
                LocalVars memory vars;

                (vars.sequence, vars.nonce, vars.payload, ) = abi.decode(
                    log.data,
                    (uint64, uint32, bytes, uint8)
                );

                console.logBytes(vars.payload);

                DeliveryInstruction memory instruction = PayloadDecoder
                    .decodeDeliveryInstruction(vars.payload);

                IWormholeReceiver(dstAddress).receiveWormholeMessages(
                    instruction.payload,
                    new bytes[](0),
                    log.topics[1],
                    srcChainId,
                    keccak256(abi.encodePacked(vars.sequence, vars.nonce)) /// @dev generating some random hash
                );
            }
        }

        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }
}
