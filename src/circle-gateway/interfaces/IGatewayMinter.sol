// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice minimal surface of Circle Gateway's GatewayMinter used by the helper
/// @dev proxy at 0x2222222d7164433c4C09B0b0D809a9b52C04C205 on every Gateway chain
interface IGatewayMinter {
    function gatewayMint(bytes calldata attestationPayload, bytes calldata signature) external;
    function domain() external view returns (uint32);
    function owner() external view returns (address);
    function isAttestationSigner(address signer) external view returns (bool);
    function addAttestationSigner(address signer) external;
    function isTransferSpecHashUsed(bytes32 transferSpecHash) external view returns (bool);
    function isTokenSupported(address token) external view returns (bool);
}
