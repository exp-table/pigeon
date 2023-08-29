// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// bridge specific imports
import "./lib/PayloadDecoder.sol";
import "./lib/InternalStructs.sol";

import {TypeCasts} from "../../libraries/TypeCasts.sol";

/// @dev interface that every wormhole receiver should implement
/// @notice the helper will try to deliver the message to this interface
interface IWormholeReceiver {
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable;
}

/// @title WormholeHelper
/// @author Sujith Somraaj
/// @dev wormhole bridge helper
/// @notice supports only automatic relayer (not specialized relayers)
/// MORE INFO: https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/automatic-relayer
contract WormholeHelper is Test {
    /*///////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @dev LogMessagePublished (index_topic_1 address sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)
    bytes32 constant MESSAGE_EVENT_SELECTOR = 0x6eb224fb001ed210e379b335e35efe88672a8ce935d981a6896b27ffdf52a3b2;

    /*///////////////////////////////////////////////////////////////
                             EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev single dst x default event selector
    /// @param srcChainId is the wormhole identifier of the source chain
    /// @param dstForkId is the dst fork id to deliver the message
    /// @param dstRelayer is wormhole's dst chain relayer
    /// @param logs is the logs after message dispatch on src chain
    function help(uint16 srcChainId, uint256 dstForkId, address dstRelayer, Vm.Log[] calldata logs) external {
        _help(srcChainId, dstForkId, address(0), dstRelayer, MESSAGE_EVENT_SELECTOR, logs);
    }

    /// @dev single dst x user-specific event selector
    /// @param srcChainId is the wormhole identifier of the source chain
    /// @param dstForkId is the dst fork id to deliver the message
    /// @param dstRelayer is wormhole's dst chain relayer
    /// @param logs is the logs after message dispatch on src chain
    function help(
        uint16 srcChainId,
        uint256 dstForkId,
        address dstRelayer,
        bytes32 msgEventSelector,
        Vm.Log[] calldata logs
    ) external {
        _help(srcChainId, dstForkId, address(0), dstRelayer, msgEventSelector, logs);
    }

    /// @dev multi dst x default event selector
    /// @param srcChainId is the wormhole identifier of the source chain
    /// @param dstForkId is the dst fork id to deliver the message
    /// @param dstRelayer is wormhole's dst chain relayer
    /// @param logs is the logs after message dispatch on src chain
    function help(
        uint16 srcChainId,
        uint256[] calldata dstForkId,
        address[] calldata expDstAddress,
        address[] calldata dstRelayer,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i; i < dstForkId.length;) {
            _help(srcChainId, dstForkId[i], expDstAddress[i], dstRelayer[i], MESSAGE_EVENT_SELECTOR, logs);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev multi dst x user-specific event selector
    /// @param srcChainId is the wormhole identifier of the source chain
    /// @param dstForkId is the dst fork id to deliver the message
    /// @param dstRelayer is wormhole's dst chain relayer
    /// @param logs is the logs after message dispatch on src chain
    function help(
        uint16 srcChainId,
        uint256[] calldata dstForkId,
        address[] calldata expDstAddress,
        address[] calldata dstRelayer,
        bytes32 msgEventSelector,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i; i < dstForkId.length;) {
            _help(srcChainId, dstForkId[i], expDstAddress[i], dstRelayer[i], msgEventSelector, logs);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev helps find logs of `length` for default event selector
    function findLogs(Vm.Log[] calldata logs, uint256 length) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, MESSAGE_EVENT_SELECTOR, length);
    }

    /*///////////////////////////////////////////////////////////////
                        INTERNAL/HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    struct LocalVars {
        uint256 prevForkId;
        uint64 sequence;
        uint32 nonce;
        bytes payload;
        address dstAddress;
    }

    /// @dev helper to process cross-chain messages
    function _help(
        uint16 srcChainId,
        uint256 dstForkId,
        address expDstAddress,
        address dstRelayer,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) internal {
        LocalVars memory v;
        v.prevForkId = vm.activeFork();

        vm.selectFork(dstForkId);
        vm.startBroadcast(dstRelayer);

        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];

            if (log.topics[0] == eventSelector) {
                (v.sequence, v.nonce, v.payload,) = abi.decode(log.data, (uint64, uint32, bytes, uint8));

                DeliveryInstruction memory instruction = PayloadDecoder.decodeDeliveryInstruction(v.payload);

                v.dstAddress = TypeCasts.bytes32ToAddress(instruction.targetAddress);

                if (expDstAddress == address(0) || expDstAddress == v.dstAddress) {
                    IWormholeReceiver(v.dstAddress).receiveWormholeMessages(
                        instruction.payload,
                        new bytes[](0),
                        instruction.senderAddress,
                        srcChainId,
                        keccak256(abi.encodePacked(v.sequence, v.nonce))
                    );
                    /// @dev generating some random hash
                }
            }
        }

        vm.stopBroadcast();
        vm.selectFork(v.prevForkId);
    }

    /// @dev helper to get logs
    function _findLogs(Vm.Log[] memory logs, bytes32 dispatchSelector, uint256 length)
        internal
        pure
        returns (Vm.Log[] memory WormholeLogs)
    {
        WormholeLogs = new Vm.Log[](length);

        uint256 currentIndex = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == dispatchSelector) {
                WormholeLogs[currentIndex] = logs[i];
                currentIndex++;

                if (currentIndex == length) {
                    break;
                }
            }
        }
    }
}
