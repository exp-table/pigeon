// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice minimal surface of Circle Gateway's GatewayWallet used by the helper
/// @dev proxy at 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE on every Gateway chain
interface IGatewayWallet {
    function deposit(address token, uint256 value) external;
    function depositFor(address token, address depositor, uint256 value) external;
    function domain() external view returns (uint32);
    function isTokenSupported(address token) external view returns (bool);
}
