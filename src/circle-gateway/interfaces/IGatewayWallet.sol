// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice the GatewayWallet surface the helper and its tests use
/// @dev proxy at 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE on every Gateway chain
interface IGatewayWallet {
    function deposit(address token, uint256 value) external;
    function availableBalance(address token, address depositor) external view returns (uint256);
}
