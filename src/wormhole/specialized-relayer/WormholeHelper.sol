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
    function help(
        uint16 srcChainId,
        uint16 dstChainId,
        uint256 dstForkId,
        address dstWormhole,
        address dstTarget,
        Vm.Log[] calldata srcLogs
    ) external {
        vm.selectFork(dstForkId);

        IWormhole wormhole = IWormhole(dstWormhole);

        bytes32 lastSlot = 0x2fc7941cecc943bf2000c5d7068f2b8c8e9a29be62acd583fe9e6e90489a8c82;
        uint256 lastKey = 420;

        /// @dev updates the storage slot to update the guardian set
        for (uint256 i; i < 19; i++) {
            vm.store(address(wormhole), bytes32(lastSlot), TypeCasts.addressToBytes32(vm.addr(lastKey)));
            lastSlot = bytes32(uint256(lastSlot) + 1);
            ++lastKey;
        }

        /// @dev generates vaa hash
        IWormhole.VM memory vaa = IWormhole.VM(
            uint8(1),
            uint32(block.timestamp),
            uint32(0),
            srcChainId,
            TypeCasts.addressToBytes32(vm.addr(419)),
            uint64(0),
            uint8(0),
            abi.encode(type(uint256).max),
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

        console.logBytes(vaa.payload);

        vaa.hash = keccak256(abi.encodePacked(keccak256(body)));
        lastKey = 420;

        for (uint256 i; i < 19; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(lastKey, vaa.hash);
            vaa.signatures[i] = IWormhole.Signature(r, s, v, uint8(i));
            console.log(vm.addr(lastKey));
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

        encodedVaa = abi.encodePacked(encodedVaa, body);

        /// call the target with the vaa
        IWormholeReceiver(dstTarget).receiveMessage(encodedVaa);
    }
}
