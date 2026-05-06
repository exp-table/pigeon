// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Client} from "./Client.sol";

/// @notice Vendored from `smartcontractkit/chainlink-ccip` at tag `contracts-ccip-v1.6.0`
/// (`chains/evm/contracts/interfaces/IAny2EVMMessageReceiver.sol`).
interface IAny2EVMMessageReceiver {
    /// @notice Called by the Router to deliver a CCIP message.
    function ccipReceive(Client.Any2EVMMessage calldata message) external;
}
