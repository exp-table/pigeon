// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @title IMessageTransmitterV2
/// @notice Minimal interface for Circle's CCTP V2 MessageTransmitter on destination chain
interface IMessageTransmitterV2 {
    /// @notice Receives a CCTP message and its attestation, verifying signatures and executing the message
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool);

    /// @notice Returns the address of the attester manager
    function attesterManager() external view returns (address);

    /// @notice Enables a new attester
    function enableAttester(address newAttester) external;

    /// @notice Sets the signature threshold for attestation verification
    function setSignatureThreshold(uint256 newSignatureThreshold) external;

    /// @notice Returns the number of enabled attesters
    function getNumEnabledAttesters() external view returns (uint256);

    /// @notice Returns the enabled attester at the given index
    function getEnabledAttester(uint256 index) external view returns (address);

    /// @notice Checks if an address is an enabled attester
    function isEnabledAttester(address attester) external view returns (bool);
}
