// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Client} from "./Client.sol";

/// @notice Vendored from `smartcontractkit/chainlink-ccip` at tag `contracts-ccip-v1.6.0`
/// (`chains/evm/contracts/interfaces/IRouterClient.sol`).
interface IRouterClient {
    error UnsupportedDestinationChain(uint64 destChainSelector);
    error InsufficientFeeTokenAmount();
    error InvalidMsgValue();

    function isChainSupported(uint64 destChainSelector) external view returns (bool);

    function getFee(uint64 destinationChainSelector, Client.EVM2AnyMessage memory message)
        external
        view
        returns (uint256 fee);

    function ccipSend(uint64 destinationChainSelector, Client.EVM2AnyMessage calldata message)
        external
        payable
        returns (bytes32);
}
