/// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
import "./lib/IWormhole.sol";
import {TypeCasts} from "../../libraries/TypeCasts.sol";

interface IWormholeReceiver {
    function receiveMessage(bytes memory encodedMessage) external;
}

/// @title WormholeHelper
/// @author Sujith Somraaj
/// @dev wormhole helper that uses VAA to deliver messages
/// @notice supports specialized relayers (for automatic relayer use WormholeHelper)
/// @notice in real-world scenario the off-chain infra will just sign the VAAs but this helpers mocks both signing and relaying
/// MORE INFO: https://docs.wormhole.com/wormhole/quick-start/cross-chain-dev/specialized-relayer
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
    /// @param dstWormhole is the wormhole core contract on dst chain
    /// @param dstTarget is the final receiver of the message
    /// @param srcLogs is the logs after message dispatch on src chain
    function help(
        uint16 srcChainId,
        uint256 dstForkId,
        address dstWormhole,
        address dstTarget,
        Vm.Log[] calldata srcLogs
    ) external {
        _help(srcChainId, dstForkId, dstWormhole, dstTarget, MESSAGE_EVENT_SELECTOR, srcLogs);
    }

    /// @dev single dst x user-specified event selector
    function help(
        uint16 srcChainId,
        uint256 dstForkId,
        address dstWormhole,
        address dstTarget,
        bytes32 msgEventSelector,
        Vm.Log[] calldata srcLogs
    ) external {
        _help(srcChainId, dstForkId, dstWormhole, dstTarget, msgEventSelector, srcLogs);
    }

    /// @dev multi dst x default event selector
    function help(
        uint16 srcChainId,
        uint256[] memory dstForkId,
        address[] memory dstWormhole,
        address[] memory dstTarget,
        Vm.Log[] calldata srcLogs
    ) external {
        for (uint256 i; i < dstForkId.length;) {
            _help(srcChainId, dstForkId[i], dstWormhole[i], dstTarget[i], MESSAGE_EVENT_SELECTOR, srcLogs);

            unchecked {
                ++i;
            }
        }
    }

    /// @dev multi dst x user-specified event selector
    function help(
        uint16 srcChainId,
        uint256[] memory dstForkId,
        address[] memory dstWormhole,
        address[] memory dstTarget,
        bytes32 msgEventSelector,
        Vm.Log[] calldata srcLogs
    ) external {
        for (uint256 i; i < dstForkId.length;) {
            _help(srcChainId, dstForkId[i], dstWormhole[i], dstTarget[i], msgEventSelector, srcLogs);

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
                        INTERNAL HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    struct LocalVars {
        uint256 prevForkId;
        uint64 sequence;
        uint32 nonce;
        bytes payload;
        uint8 consistencyLevel;
        address dstAddress;
    }

    function _help(
        uint16 srcChainId,
        uint256 dstForkId,
        address dstWormhole,
        address dstTarget,
        bytes32 eventSelector,
        Vm.Log[] calldata srcLogs
    ) internal {
        LocalVars memory v;

        v.prevForkId = vm.activeFork();
        vm.selectFork(dstForkId);

        for (uint256 i; i < srcLogs.length; i++) {
            Vm.Log memory log = srcLogs[i];

            if (log.topics[0] == eventSelector) {
                (v.sequence, v.nonce, v.payload, v.consistencyLevel) =
                    abi.decode(log.data, (uint64, uint32, bytes, uint8));

                /// @dev overrides wormhole guardian set to a preferred set
                _prepareWormhole(dstWormhole);

                /// @dev generates the VAA using our overriden guardian set
                bytes memory encodedVAA = _generateVAA(
                    srcChainId,
                    v.nonce,
                    TypeCasts.bytes32ToAddress(log.topics[1]),
                    v.sequence,
                    v.consistencyLevel,
                    v.payload,
                    dstWormhole
                );

                /// @dev delivers the message by passing the new guardian set to receiver
                IWormholeReceiver(dstTarget).receiveMessage(encodedVAA);
            }
        }

        vm.selectFork(v.prevForkId);
    }

    /// @dev overrides the guardian set by choosing slot
    /// TODO: slot works till the guardianSetIndex is 3
    function _prepareWormhole(address dstWormhole) internal {
        IWormhole wormhole = IWormhole(dstWormhole);
        bytes32 lastSlot = 0x2fc7941cecc943bf2000c5d7068f2b8c8e9a29be62acd583fe9e6e90489a8c82;
        uint256 lastKey = 420;

        /// @dev updates the storage slot to update the guardian set
        for (uint256 i; i < 19; i++) {
            vm.store(address(wormhole), bytes32(lastSlot), TypeCasts.addressToBytes32(vm.addr(lastKey)));
            lastSlot = bytes32(uint256(lastSlot) + 1);
            ++lastKey;
        }
    }

    /// @dev generates the encoded vaa
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
