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

interface IMessageTransmitter {
    function attesterManager() external view returns (address);
    function enableAttester(address newAttester) external;
    function isEnabledAttester(address attester) external view returns (bool);
    function setSignatureThreshold(uint256 newSignatureThreshold) external;
    function receiveMessage(bytes calldata message, bytes calldata attestation) external;
}

/// @title WormholeHelper
/// @notice supports only automatic relayer (not specialized relayers)
/// MORE INFO: https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/automatic-relayer
contract WormholeHelper is Test {
    /// @dev is the default event selector if not specified by the user
    bytes32 constant MESSAGE_EVENT_SELECTOR = 0x6eb224fb001ed210e379b335e35efe88672a8ce935d981a6896b27ffdf52a3b2;
    bytes32 constant CCTP_MESSAGE_EVENT_SELECTOR = 0x8c5261668696ce22758910d05bab8f186d6eb247ceac2af2e82c7dc17669b036;

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @dev single dst x default event selector
    /// @param srcChainId represents the wormhole identifier of the source chain
    /// @param dstForkId represents the dst fork id to deliver the message
    /// @param dstRelayer represents wormhole's dst chain relayer
    /// @param logs represents the logs after message dispatch on src chain
    function help(uint16 srcChainId, uint256 dstForkId, address dstRelayer, Vm.Log[] calldata logs) external {
        _help(srcChainId, dstForkId, address(0), dstRelayer, MESSAGE_EVENT_SELECTOR, logs);
    }

    /// @dev single dst x user-specific event selector
    /// @param srcChainId represents the wormhole identifier of the source chain
    /// @param dstForkId represents the dst fork id to deliver the message
    /// @param dstRelayer represents wormhole's dst chain relayer
    /// @param logs represents the logs after message dispatch on src chain
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
    /// @param srcChainId represents the wormhole identifier of the source chain
    /// @param dstForkId represents the dst fork id to deliver the message
    /// @param dstRelayer represents wormhole's dst chain relayer
    /// @param logs represents the logs after message dispatch on src chain
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
    /// @param srcChainId represents the wormhole identifier of the source chain
    /// @param dstForkId represents the dst fork id to deliver the message
    /// @param dstRelayer represents wormhole's dst chain relayer
    /// @param logs represents the logs after message dispatch on src chain
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
    /// @param srcChainId represents the wormhole identifier for the source chain
    /// @param dstForkId represents the dst fork id to deliver the message
    /// @param expDstAddress represents the expected dst chain receiver
    /// @param dstRelayer represents the wormhole dst relayer address
    /// @param dstWormhole represents the wormhole dst core address
    /// @param logs represents the logs after message dispatch with additional VAAs
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

    struct LocalCCTPVars {
        uint256 prevForkId;
        bytes cctpMessage;
        bytes[] additionalMessage;
        bytes32 digest;
        uint8 v;
        bytes32 r;
        bytes32 s;
        Vm.Log log;
        uint64 sequence;
        uint32 nonce;
        bytes payload;
        address dstAddress;
    }

    /// @dev is a helper for https://docs.wormhole.com/wormhole/quick-start/tutorials/cctp
    /// @param srcChainId represents the wormhole identifier for the source chain
    /// @param dstForkId represents the dst fork id to deliver the message
    /// @param expDstAddress represents the expected dst chain receiver of wormhole message
    /// @param dstRelayer represents the wormhole dst relayer address
    /// @param dstTransmitter represents the cctp dst transmitter address
    /// @param logs represents the logs after message dispatch using sendToEvm
    /// @notice supports only one CCTP transfer and sendToEvm per log
    function helpWithCctpAndWormhole(
        uint16 srcChainId,
        uint256 dstForkId,
        address expDstAddress,
        address dstRelayer,
        address dstTransmitter,
        Vm.Log[] calldata logs
    ) external {
        LocalCCTPVars memory v;
        v.prevForkId = vm.activeFork();
        v.additionalMessage = new bytes[](1);
        vm.selectFork(dstForkId);

        /// @dev identifies the cctp transfer
        for (uint256 i; i < logs.length; ++i) {
            v.log = logs[i];
            if (v.log.topics[0] == CCTP_MESSAGE_EVENT_SELECTOR) {
                v.cctpMessage = abi.decode(logs[i].data, (bytes));
                /// @dev prepare circle transmitter on dst chain
                IMessageTransmitter messageTransmitter = IMessageTransmitter(dstTransmitter);

                if (!messageTransmitter.isEnabledAttester(vm.addr(420))) {
                    vm.startPrank(messageTransmitter.attesterManager());
                    messageTransmitter.enableAttester(vm.addr(420));
                    messageTransmitter.setSignatureThreshold(1);
                    vm.stopPrank();
                }

                v.digest = keccak256(v.cctpMessage);
                (v.v, v.r, v.s) = vm.sign(420, v.digest);
                v.additionalMessage[0] = abi.encode(v.cctpMessage, abi.encodePacked(v.r, v.s, v.v));
            }
        }

        /// @dev identifies and delivers the wormhole message
        vm.startBroadcast(dstRelayer);
        for (uint256 j; j < logs.length; ++j) {
            v.log = logs[j];

            if (v.log.topics[0] == MESSAGE_EVENT_SELECTOR) {
                (v.sequence, v.nonce, v.payload,) = abi.decode(v.log.data, (uint64, uint32, bytes, uint8));

                DeliveryInstruction memory instruction = PayloadDecoder.decodeDeliveryInstruction(v.payload);

                v.dstAddress = TypeCasts.bytes32ToAddress(instruction.targetAddress);

                if (expDstAddress == address(0) || expDstAddress == v.dstAddress) {
                    IWormholeReceiver(v.dstAddress).receiveWormholeMessages(
                        instruction.payload,
                        v.additionalMessage,
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

    /// @dev helps find logs of `length` for default event selector
    /// @param logs represents the logs after message dispatch on src chain
    /// @param length represents the expected number of logs
    /// @return HLLogs array of found logs
    function findLogs(Vm.Log[] calldata logs, uint256 length) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, MESSAGE_EVENT_SELECTOR, length);
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    struct LocalVars {
        uint256 prevForkId;
        uint64 sequence;
        uint32 nonce;
        bytes payload;
        address dstAddress;
        bytes[] additionalVAAs;
        uint256 currIndex;
        uint256 deliveryIndex;
        uint256 currLen;
        uint256 totalLen;
        uint256[] indicesCache;
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
    /// @param srcChainId represents the wormhole identifier of the source chain
    /// @param dstForkId represents the dst fork id to deliver the message
    /// @param expDstAddress represents the expected destination address
    /// @param dstRelayer represents wormhole's dst chain relayer
    /// @param eventSelector represents the event selector
    /// @param logs represents the logs after message dispatch on src chain
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

    /// @dev helper to process cross-chain messages with additional VAAs
    /// @param srcChainId represents the wormhole identifier of the source chain
    /// @param dstForkId represents the dst fork id to deliver the message
    /// @param expDstAddress represents the expected destination address
    /// @param dstRelayer represents wormhole's dst chain relayer
    /// @param dstWormhole represents wormhole core on dst chain
    /// @param eventSelector represents the event selector
    /// @param logs represents the logs after message dispatch on src chain
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

        /// @dev calculates the valid indices length
        for (uint256 i; i < logs.length; i++) {
            log = logs[i];
            if (log.topics[0] == eventSelector) v.totalLen++;
        }

        v.indicesCache = new uint256[](v.totalLen);

        /// @dev calculates the valid indices
        for (uint256 i; i < logs.length; i++) {
            log = logs[i];
            if (log.topics[0] == eventSelector) {
                v.indicesCache[v.currLen] = i;
                v.currLen++;
            }
        }

        /// @dev if valid indices > 1, then it has additional VAAs to be delivered
        /// @dev constructs the additional VAAs in that case
        v.additionalVAAs = new bytes[](v.indicesCache.length - 1);
        v.currIndex;

        console.log("Total matching VAAs:", v.indicesCache.length);

        if (v.indicesCache.length > 1 && expDstAddress != address(0)) {
            for (uint256 j; j < v.indicesCache.length; j++) {
                log = logs[v.indicesCache[j]];

                if (TypeCasts.bytes32ToAddress(log.topics[1]) != dstRelayer) {
                    v.additionalVAAs[v.currIndex] = _generateSignedVAA(srcChainId, dstWormhole, log.topics[1], log.data);
                    v.currIndex++;
                } else {
                    v.deliveryIndex = v.indicesCache[j];
                }
            }
        }

        log = logs[v.currIndex == 0 ? v.indicesCache[0] : v.deliveryIndex];

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

        vm.stopBroadcast();
        vm.selectFork(v.prevForkId);
    }

    /// @dev helper to get logs
    /// @param logs represents the logs after message dispatch on src chain
    /// @param dispatchSelector represents the event selector
    /// @param length represents the expected number of logs
    /// @return WormholeLogs array of found logs
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
    /// @param srcChainId represents the source chain
    /// @param dstWormhole represents the wormhole core on dst chain
    /// @param emitter represents the wormhole core on source chain
    /// @param logData represents the data emitted in the log
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
