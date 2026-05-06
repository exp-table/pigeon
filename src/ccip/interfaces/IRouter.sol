// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Client} from "./Client.sol";

/// @notice Vendored from `smartcontractkit/chainlink-ccip` at tag `contracts-ccip-v1.6.0`
/// (`chains/evm/contracts/interfaces/IRouter.sol`).
interface IRouter {
    error OnlyOffRamp();

    /// @notice Route the message to its intended receiver contract.
    function routeMessage(
        Client.Any2EVMMessage calldata message,
        uint16 gasForCallExactCheck,
        uint256 gasLimit,
        address receiver
    ) external returns (bool success, bytes memory retBytes, uint256 gasUsed);

    /// @notice Returns the configured onRamp for a specific destination chain.
    function getOnRamp(uint64 destChainSelector) external view returns (address onRampAddress);

    /// @notice Return true if the given offRamp is a configured offRamp for the given source chain.
    function isOffRamp(uint64 sourceChainSelector, address offRamp) external view returns (bool);
}
