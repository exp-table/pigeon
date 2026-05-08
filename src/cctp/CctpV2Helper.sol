// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import {IMessageTransmitterV2} from "./interfaces/IMessageTransmitterV2.sol";

/// @title CCTP V2 Helper
/// @notice helps simulate CCTP V2 cross-chain USDC transfers by relaying MessageSent events
contract CctpV2Helper is Test {
    /// @dev event selector for MessageSent(bytes) emitted by MessageTransmitterV2
    bytes32 constant MESSAGE_SENT_TOPIC = keccak256("MessageSent(bytes)");

    /// @dev MessageTransmitterV2 address (same on all mainnet EVM chains via CREATE2)
    address constant MESSAGE_TRANSMITTER_V2 = 0x81D40F21F12A8F0E3252Bccb954D722d4c464B64;

    /// @dev storage slot of the usedNonces mapping in MessageTransmitterV2
    uint256 constant USED_NONCES_SLOT = 29;

    /// @dev private key used to sign attestations in tests
    uint256 public immutable TEST_ATTESTER_PK;

    /// @dev address derived from TEST_ATTESTER_PK
    address public immutable testAttesterAddress;

    /// @dev tracks (sourceDomain, nonce) pairs already relayed to prevent double-mint on replay
    mapping(bytes32 => bool) private _processedMessages;

    //////////////////////////////////////////////////////////////
    //                      CONSTRUCTOR                         //
    //////////////////////////////////////////////////////////////

    /// @notice creates a helper with a test attester private key
    /// @param attesterPK the private key used to sign attestations (use 0 for default key 0x1)
    constructor(uint256 attesterPK) {
        uint256 pk = attesterPK == 0 ? 1 : attesterPK;
        TEST_ATTESTER_PK = pk;
        testAttesterAddress = vm.addr(pk);
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice relays CCTP messages to a single destination domain
    /// @param expectedDestDomain the CCTP domain ID to filter for
    /// @param forkId the fork ID of the destination chain
    /// @param logs the recorded logs from source chain execution
    function help(uint32 expectedDestDomain, uint256 forkId, Vm.Log[] calldata logs) external {
        _help(expectedDestDomain, forkId, logs, MESSAGE_TRANSMITTER_V2);
    }

    /// @notice relays CCTP messages to a single destination domain, filtering by emitter
    /// @param expectedDestDomain the CCTP domain ID to filter for
    /// @param forkId the fork ID of the destination chain
    /// @param logs the recorded logs from source chain execution
    /// @param emitter only process MessageSent logs from this address
    function help(uint32 expectedDestDomain, uint256 forkId, Vm.Log[] calldata logs, address emitter) external {
        _help(expectedDestDomain, forkId, logs, emitter);
    }

    /// @notice relays CCTP messages to multiple destination domains
    /// @param expectedDestDomains array of CCTP domain IDs to filter for
    /// @param forkIds array of fork IDs corresponding to each destination
    /// @param logs the recorded logs from source chain execution
    function help(uint32[] memory expectedDestDomains, uint256[] memory forkIds, Vm.Log[] calldata logs) external {
        require(expectedDestDomains.length == forkIds.length, "CctpV2Helper: length mismatch");
        for (uint256 i; i < expectedDestDomains.length; ++i) {
            _help(expectedDestDomains[i], forkIds[i], logs, MESSAGE_TRANSMITTER_V2);
        }
    }

    /// @notice relays CCTP messages to multiple destination domains, filtering by emitter
    /// @param expectedDestDomains array of CCTP domain IDs to filter for
    /// @param forkIds array of fork IDs corresponding to each destination
    /// @param logs the recorded logs from source chain execution
    /// @param emitter only process MessageSent logs from this address
    function help(
        uint32[] memory expectedDestDomains,
        uint256[] memory forkIds,
        Vm.Log[] calldata logs,
        address emitter
    ) external {
        require(expectedDestDomains.length == forkIds.length, "CctpV2Helper: length mismatch");
        for (uint256 i; i < expectedDestDomains.length; ++i) {
            _help(expectedDestDomains[i], forkIds[i], logs, emitter);
        }
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice processes logs and relays matching CCTP messages to the destination fork
    function _help(uint32 expectedDestDomain, uint256 forkId, Vm.Log[] memory logs, address emitter) internal {
        uint256 prevForkId = vm.activeFork();

        for (uint256 i; i < logs.length; i++) {
            /// skip anonymous events / log0 (no topics)
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != MESSAGE_SENT_TOPIC) continue;
            /// filter by emitter to avoid collisions with other MessageSent(bytes) events
            if (logs[i].emitter != emitter) continue;

            bytes memory message = abi.decode(logs[i].data, (bytes));
            uint32 destDomain = _getDestinationDomain(message);

            if (destDomain != expectedDestDomain) continue;

            /// dedup: skip if this (sourceDomain, nonce) was already relayed
            uint32 sourceDomain = _getSourceDomain(message);
            bytes32 nonce = _getNonce(message);
            bytes32 msgKey = keccak256(abi.encode(sourceDomain, nonce));
            if (_processedMessages[msgKey]) continue;
            _processedMessages[msgKey] = true;

            /// switch to destination fork
            vm.selectFork(forkId);

            /// replace production attesters with our test key
            _setupTestAttester();

            /// set finalityThresholdExecuted >= minFinalityThreshold (simulates attestation service)
            _setFinalityExecuted(message);

            /// sign the modified message to create a valid attestation
            bytes memory attestation = _signMessage(message);

            /// check if destinationCaller is set (restricts who can relay)
            bytes32 destinationCaller = _getDestinationCaller(message);

            /// clear usedNonces for this message's nonce so relay succeeds on forked state
            _clearUsedNonce(message);

            if (destinationCaller != bytes32(0)) {
                vm.prank(address(uint160(uint256(destinationCaller))));
            }

            /// relay the message on destination
            IMessageTransmitterV2(MESSAGE_TRANSMITTER_V2).receiveMessage(message, attestation);

            /// switch back to source fork
            vm.selectFork(prevForkId);
        }
    }

    /// @notice replaces production attesters with the test attester on the destination chain
    function _setupTestAttester() internal {
        IMessageTransmitterV2 transmitter = IMessageTransmitterV2(MESSAGE_TRANSMITTER_V2);
        address mgr = transmitter.attesterManager();

        vm.startPrank(mgr);
        /// enable our test attester
        if (!transmitter.isEnabledAttester(testAttesterAddress)) {
            transmitter.enableAttester(testAttesterAddress);
        }
        /// set threshold to 1 so only our signature is needed
        transmitter.setSignatureThreshold(1);
        vm.stopPrank();
    }

    /// @notice signs a CCTP message with the test attester key
    /// @param message the raw CCTP message bytes
    /// @return attestation the packed signature (r, s, v)
    function _signMessage(bytes memory message) internal view returns (bytes memory attestation) {
        bytes32 digest = keccak256(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_ATTESTER_PK, digest);
        attestation = abi.encodePacked(r, s, v);
    }

    /// @notice sets finalityThresholdExecuted to match minFinalityThreshold in the message
    /// @dev in production, the attestation service fills in finalityThresholdExecuted.
    ///      in tests, we set it to minFinalityThreshold so receiveMessage doesn't revert.
    ///      offset 140 = minFinalityThreshold (uint32), offset 144 = finalityThresholdExecuted (uint32)
    function _setFinalityExecuted(bytes memory message) internal pure {
        require(message.length >= 148, "CctpV2Helper: message too short for finality");
        assembly {
            let minFinality := shr(224, mload(add(message, 172)))
            // write minFinality into finalityThresholdExecuted (offset 144, 4 bytes)
            let word := mload(add(message, 176))
            // clear top 4 bytes and set to minFinality
            word := or(shl(224, minFinality), and(word, 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff))
            mstore(add(message, 176), word)
        }
    }

    /// @notice clears the usedNonces entry so the message can be relayed on forked state
    /// @param message the raw CCTP message bytes
    function _clearUsedNonce(bytes memory message) internal {
        bytes32 nonce = _getNonce(message);
        bytes32 storageKey = keccak256(abi.encode(nonce, USED_NONCES_SLOT));
        vm.store(MESSAGE_TRANSMITTER_V2, storageKey, bytes32(0));
    }

    /// @notice extracts nonce from CCTP message bytes
    /// @dev offset 12, 32 bytes (after version[4] + sourceDomain[4] + destinationDomain[4])
    function _getNonce(bytes memory message) internal pure returns (bytes32) {
        require(message.length >= 44, "CctpV2Helper: message too short for nonce");
        bytes32 nonce;
        assembly {
            nonce := mload(add(message, 44))
        }
        return nonce;
    }

    /// @notice extracts sourceDomain from CCTP message bytes
    /// @dev offset 4, 4 bytes (after version[4])
    function _getSourceDomain(bytes memory message) internal pure returns (uint32) {
        require(message.length >= 8, "CctpV2Helper: message too short for srcDomain");
        uint32 srcDomain;
        assembly {
            srcDomain := shr(224, mload(add(message, 36)))
        }
        return srcDomain;
    }

    /// @notice extracts destinationDomain from CCTP message bytes
    /// @dev offset 8, 4 bytes (after version[4] + sourceDomain[4])
    function _getDestinationDomain(bytes memory message) internal pure returns (uint32) {
        require(message.length >= 12, "CctpV2Helper: message too short for destDomain");
        uint32 destDomain;
        assembly {
            destDomain := shr(224, mload(add(message, 40)))
        }
        return destDomain;
    }

    /// @notice extracts destinationCaller from CCTP message bytes
    /// @dev offset 108, 32 bytes
    function _getDestinationCaller(bytes memory message) internal pure returns (bytes32) {
        require(message.length >= 140, "CctpV2Helper: message too short for destCaller");
        bytes32 destCaller;
        assembly {
            destCaller := mload(add(message, 140))
        }
        return destCaller;
    }
}
