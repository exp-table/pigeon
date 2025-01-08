// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

struct Packet {
    uint64 nonce;
    uint32 srcEid;
    address sender;
    uint32 dstEid;
    bytes32 receiver;
    bytes32 guid;
    bytes message;
}

struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

interface ILayerzeroV2Receiver {
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;
}

/// @title LayerZero V2 Helper
/// @notice helps simulate message transfers using the LayerZero v2 protocol
contract LayerZeroV2Helper is Test {
    /// @dev is the default packet selector if not specified by the user
    bytes32 constant PACKET_SELECTOR = 0x1ab700d4ced0c005b164c0f789fd09fcbb0156d4c2041b8a3bfbcd961cd1567f;

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helps process multiple destination packets in one atomic transaction
    /// @param endpoints represents the layerzero endpoints on the destination chain
    /// @param expChainIds represents the layerzero destination chain eids
    /// @param forkIds represents the layerzero destina
    /// @param logs represents the recorded message logs
    function help(
        address[] memory endpoints,
        uint32[] memory expChainIds,
        uint256[] memory forkIds,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i; i < endpoints.length; ++i) {
            _help(endpoints[i], expChainIds[i], forkIds[i], PACKET_SELECTOR, logs);
        }
    }

    /// @notice helps process multiple destination packets in one atomic transaction
    /// @param endpoints represents the layerzero endpoints on the destination chain
    /// @param expChainIds represents the layerzero destination chain eids
    /// @param forkIds represents the layerzero destination chain fork ids
    /// @param eventSelector represents a custom event selector
    /// @param logs represents the recorded message logs
    function help(
        address[] memory endpoints,
        uint32[] memory expChainIds,
        uint256[] memory forkIds,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i; i < endpoints.length; ++i) {
            _help(endpoints[i], expChainIds[i], forkIds[i], eventSelector, logs);
        }
    }

    /// @notice helps process LayerZero v2 packets
    /// @param endpoint represents the layerzero endpoint on the destination chain
    /// @param forkId represents the destination chain fork id
    /// @param logs represents the recorded message logs
    function help(address endpoint, uint256 forkId, Vm.Log[] calldata logs) external {
        _help(endpoint, 0, forkId, PACKET_SELECTOR, logs);
    }

    /// @notice helps process LayerZero v2 packets
    /// @param endpoint represents the layerzero endpoint on the destination chain
    /// @param forkId represents the destination chain fork id
    /// @param eventSelector represents a custom bytes32 event selector
    /// @param logs represents the recorded message logs
    function help(address endpoint, uint256 forkId, bytes32 eventSelector, Vm.Log[] calldata logs) external {
        _help(endpoint, 0, forkId, eventSelector, logs);
    }

    /// @notice internal function to process LayerZero v2 packets based on the provided logs and fork ID
    /// @param endpoint represents the layerzero endpoint on the destination chain
    /// @param expDstChainId represents the expected destination chain id
    /// @param forkId represents the destination chain fork id
    /// @param eventSelector represents the event selector
    /// @param logs represents the recorded message logs
    function _help(address endpoint, uint32 expDstChainId, uint256 forkId, bytes32 eventSelector, Vm.Log[] memory logs)
        internal
    {
        uint256 prevForkId = vm.activeFork();

        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];

            if (log.topics[0] == eventSelector) {
                (bytes memory payload,,) = abi.decode(log.data, (bytes, bytes, address));
                Packet memory packet = this.decodePacket(payload);
                address receiver = address(uint160(uint256(packet.receiver)));

                if (packet.dstEid == expDstChainId || expDstChainId == 0) {
                    vm.selectFork(forkId);
                    vm.prank(endpoint);
                    ILayerzeroV2Receiver(receiver).lzReceive(
                        Origin(packet.srcEid, bytes32(uint256(uint160(packet.sender))), packet.nonce),
                        packet.guid,
                        packet.message,
                        address(0),
                        bytes("")
                    );
                    vm.selectFork(prevForkId);
                }
            }
        }
    }

    /// @notice helps decode the layerzero encoded payload / packet
    /// @param encodedPacket represents the encoded packet
    /// @return the decoded packet
    function decodePacket(bytes calldata encodedPacket) public pure returns (Packet memory) {
        /// @dev decode the packet header
        uint64 nonce = toUint64(encodedPacket, 1);
        uint32 srcEid = toUint32(encodedPacket, 9);
        address sender = toAddress(encodedPacket, 13);
        uint32 dstEid = toUint32(encodedPacket, 45);
        bytes32 receiver = toBytes32(encodedPacket, 49);

        /// @dev decode the payload
        bytes32 guid = toBytes32(encodedPacket, 81);
        bytes memory message = encodedPacket[113:];

        return Packet({
            nonce: nonce,
            srcEid: srcEid,
            sender: sender,
            dstEid: dstEid,
            receiver: receiver,
            guid: guid,
            message: message
        });
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helper function to convert bytes to uint64
    /// @param data represents the bytes data
    /// @param offset represents the offset within the data
    /// @return the uint64 value
    function toUint64(bytes calldata data, uint256 offset) internal pure returns (uint64) {
        require(offset + 8 <= data.length, "toUint64: out of bounds");
        return uint64(bytes8(data[offset:offset + 8]));
    }

    /// @notice helper function to convert bytes to uint32
    /// @param data represents the bytes data
    /// @param offset represents the offset within the data
    /// @return the uint32 value
    function toUint32(bytes calldata data, uint256 offset) internal pure returns (uint32) {
        require(offset + 4 <= data.length, "toUint32: out of bounds");
        return uint32(bytes4(data[offset:offset + 4]));
    }

    /// @notice helper function to convert bytes to address
    /// @param data represents the bytes data
    /// @param offset represents the offset within the data
    /// @return the address value
    function toAddress(bytes calldata data, uint256 offset) internal pure returns (address) {
        require(offset + 20 <= data.length, "toAddress: out of bounds");
        return address(uint160(bytes20(data[offset + 12:offset + 32])));
    }

    /// @notice helper function to convert bytes to bytes32
    /// @param data represents the bytes data
    /// @param offset represents the offset within the data
    /// @return the bytes32 value
    function toBytes32(bytes calldata data, uint256 offset) internal pure returns (bytes32) {
        require(offset + 32 <= data.length, "toBytes32: out of bounds");
        return bytes32(data[offset:offset + 32]);
    }
}
