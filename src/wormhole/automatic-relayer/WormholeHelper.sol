// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// bridge specific imports
import "./lib/PayloadDecoder.sol";
import "./lib/InternalStructs.sol";
import "../specialized-relayer/lib/IWormhole.sol";

import {TypeCasts} from "../../libraries/TypeCasts.sol";
import "forge-std/console.sol";

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
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256[] public indicesCache;

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

    /// @dev multi dst with additionalVAAs (use this for single dst as well)
    /// @param srcChainId is the wormhole identifier for the source chain
    /// @param dstForkId is the dst fork id to deliver the message
    /// @param expDstAddress is the expected dst chain receiver
    /// @param dstRelayer is the wormhole dst relayer address
    /// @param dstWormhole is the wormhole dst core address
    /// @param logs is the logs after message dispatch with additional VAAs
    /// @notice considers the expectedDst to be unique in the logs (i.e., only supports one log for expectedDst per chain)
    function helpWithAdditionalVAA(
        uint16 srcChainId,
        uint256[] calldata dstForkId,
        address[] calldata expDstAddress,
        address[] calldata dstRelayer,
        address[] calldata dstWormhole,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i; i < dstForkId.length;) {
            _helpWithAddtionalVAAs(
                srcChainId, dstForkId[i], expDstAddress[i], dstRelayer[i], dstWormhole[i], MESSAGE_EVENT_SELECTOR, logs
            );
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
        bytes[] additionalVAAs;
        uint256 currIndex;
        uint256 deliveryIndex;
        DeliveryInstruction instruction;
    }

    struct PrepareDeliverVars {
        uint256 prevForkId;
        uint64 sequence;
        uint32 nonce;
        bytes payload;
        uint8 consistencyLevel;
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
                        /// @dev generating some random hash
                        keccak256(abi.encodePacked(v.sequence, v.nonce))
                    );
                }
            }
        }

        vm.stopBroadcast();
        vm.selectFork(v.prevForkId);
    }

    function _helpWithAddtionalVAAs(
        uint16 srcChainId,
        uint256 dstForkId,
        address expDstAddress,
        address dstRelayer,
        address dstWormhole,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) internal {
        LocalVars memory v;
        v.prevForkId = vm.activeFork();

        vm.selectFork(dstForkId);
        vm.startBroadcast(dstRelayer);

        Vm.Log memory log;
        console.log("Total Log Length:", logs.length);

        /// @dev calculates the valid indices
        for (uint256 i; i < logs.length; i++) {
            log = logs[i];
            if (log.topics[0] == eventSelector) indicesCache.push(i);
        }

        /// @dev if valid indices > 1, then it has additional VAAs to be delivered
        /// @dev constructs the additional VAAs in that case
        v.additionalVAAs = new bytes[](indicesCache.length - 1);
        v.currIndex;

        console.log("Total matching VAAs:", indicesCache.length);

        if (indicesCache.length > 1 && expDstAddress != address(0)) {
            for (uint256 j; j < indicesCache.length; j++) {
                log = logs[indicesCache[j]];

                if (TypeCasts.bytes32ToAddress(log.topics[1]) != dstRelayer) {
                    v.additionalVAAs[v.currIndex] = _generateSignedVAA(srcChainId, dstWormhole, log.topics[1], log.data);
                    v.currIndex++;
                } else {
                    v.deliveryIndex = indicesCache[j];
                }
            }
        }

        log = logs[v.currIndex == 0 ? indicesCache[0] : v.deliveryIndex];

        (v.sequence, v.nonce, v.payload,) = abi.decode(log.data, (uint64, uint32, bytes, uint8));

        DeliveryInstruction memory instruction = PayloadDecoder.decodeDeliveryInstruction(v.payload);

        v.dstAddress = TypeCasts.bytes32ToAddress(instruction.targetAddress);

        if (expDstAddress == address(0) || expDstAddress == v.dstAddress) {
            IWormholeReceiver(v.dstAddress).receiveWormholeMessages(
                instruction.payload,
                v.additionalVAAs,
                instruction.senderAddress,
                srcChainId,
                /// @dev generating some random hash
                keccak256(abi.encodePacked(v.sequence, v.nonce))
            );
        }

        /// @dev reset indices cache
        delete indicesCache;

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

    /// @dev prepares a valid VAA in the wormhole core by overriding the guardian set
    /// @param srcChainId is the source chain
    /// @param dstWormhole is the wormhole core on dst chain
    /// @param emitter is the wormhole core on source chain
    /// @param logData is the data emitted in the log
    function _generateSignedVAA(uint16 srcChainId, address dstWormhole, bytes32 emitter, bytes memory logData)
        internal
        returns (bytes memory)
    {
        PrepareDeliverVars memory v;

        (v.sequence, v.nonce, v.payload, v.consistencyLevel) = abi.decode(logData, (uint64, uint32, bytes, uint8));

        /// @dev overrides wormhole guardian set to a preferred set
        _prepareWormhole(dstWormhole);

        bytes memory encodedVAA = _generateVAA(
            srcChainId,
            v.nonce,
            TypeCasts.bytes32ToAddress(emitter),
            v.sequence,
            v.consistencyLevel,
            v.payload,
            dstWormhole
        );

        return encodedVAA;
    }

    /// @dev generates the encoded vaa
    /// @param srcChainId represents the wormhole identifier of the source chain
    /// @param nonce represents the nonce of the message
    /// @param emitterAddress represents the emitter address
    /// @param sequence represents the sequence of the message
    /// @param consistencyLevel represents the consistency level
    /// @param payload represents the message payload
    /// @param dstWormhole represents the wormhole core contract on dst chain
    /// @return encodedVAA the encoded VAA
    function _generateVAA(
        uint16 srcChainId,
        uint32 nonce,
        address emitterAddress,
        uint64 sequence,
        uint8 consistencyLevel,
        bytes memory payload,
        address dstWormhole
    ) internal view returns (bytes memory) {
        IWormhole wormhole = IWormhole(dstWormhole);

        /// @dev generates vaa hash
        IWormhole.VM memory vaa = IWormhole.VM(
            uint8(1),
            /// version = 1
            uint32(block.timestamp),
            nonce,
            srcChainId,
            TypeCasts.addressToBytes32(emitterAddress),
            sequence,
            consistencyLevel,
            payload,
            wormhole.getCurrentGuardianSetIndex(),
            new IWormhole.Signature[](19),
            bytes32(0)
        );

        bytes memory body = abi.encodePacked(
            vaa.timestamp,
            vaa.nonce,
            vaa.emitterChainId,
            vaa.emitterAddress,
            vaa.sequence,
            vaa.consistencyLevel,
            vaa.payload
        );

        vaa.hash = keccak256(abi.encodePacked(keccak256(body)));
        uint256 lastKey = 420;

        for (uint256 i; i < 19; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(lastKey, vaa.hash);
            vaa.signatures[i] = IWormhole.Signature(r, s, v, uint8(i));
            ++lastKey;
        }

        bytes memory encodedVaa = abi.encodePacked(vaa.version, vaa.guardianSetIndex, uint8(19));
        for (uint256 i; i < 19; i++) {
            encodedVaa = abi.encodePacked(
                encodedVaa,
                vaa.signatures[i].guardianIndex,
                vaa.signatures[i].r,
                vaa.signatures[i].s,
                vaa.signatures[i].v - 27
            );
        }

        return abi.encodePacked(encodedVaa, body);
    }

    /// @dev overrides the guardian set by choosing slot
    /// @notice overrides the current guardian set with a set of known guardian set
    /// @param dstWormhole represents the wormhole core contract on dst chain
    function _prepareWormhole(address dstWormhole) internal {
        IWormhole wormhole = IWormhole(dstWormhole);

        uint32 currentGuardianSet = wormhole.getCurrentGuardianSetIndex();
        bytes32 guardianSetSlot = keccak256(abi.encode(currentGuardianSet, 2));
        uint256 numGuardians = uint256(vm.load(address(wormhole), guardianSetSlot));

        bytes32 lastSlot = bytes32(uint256(keccak256(abi.encodePacked(guardianSetSlot))));
        uint256 lastKey = 420;

        /// @dev updates the storage slot to update the guardian set
        for (uint256 i; i < numGuardians; i++) {
            vm.store(address(wormhole), bytes32(lastSlot), TypeCasts.addressToBytes32(vm.addr(lastKey)));
            lastSlot = bytes32(uint256(lastSlot) + 1);
            ++lastKey;
        }
    }
}
