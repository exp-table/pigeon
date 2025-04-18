// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IExternalCallExecutor {
    /**
     * @notice Handles the receipt of Ether to the contract, then validates and executes a function call.
     * @dev Only callable by the adapter. This function decodes the payload to extract execution data.
     *      If the function specified in the callData is prohibited, or the recipient contract is zero,
     *      all Ether is transferred to the fallback address.
     *      Otherwise, it attempts to execute the function call. Any remaining Ether is then transferred to the fallback address.
     * @param _orderId The ID of the order that triggered this function.
     * @param _fallbackAddress The address to receive any unspent Ether.
     * @param _payload The encoded data containing the execution data.
     * @return callSucceeded A boolean indicating whether the call was successful.
     * @return callResult The data returned from the call.
     */
    function onEtherReceived(bytes32 _orderId, address _fallbackAddress, bytes memory _payload)
        external
        payable
        returns (bool callSucceeded, bytes memory callResult);

    /**
     * @notice Handles the receipt of ERC20 tokens, validates and executes a function call.
     * @dev Only callable by the adapter. This function decodes the payload to extract execution data.
     *      If the function specified in the callData is prohibited, or the recipient contract is zero,
     *      all received tokens are transferred to the fallback address.
     *      Otherwise, it attempts to execute the function call. Any remaining tokens are then transferred to the fallback address.
     * @param _orderId The ID of the order that triggered this function.
     * @param _token The address of the ERC20 token that was transferred.
     * @param _transferredAmount The amount of tokens transferred.
     * @param _fallbackAddress The address to receive any unspent tokens.
     * @param _payload The encoded data containing the execution data.
     * @return callSucceeded A boolean indicating whether the call was successful.
     * @return callResult The data returned from the call.
     */
    function onERC20Received(
        bytes32 _orderId,
        address _token,
        uint256 _transferredAmount,
        address _fallbackAddress,
        bytes memory _payload
    ) external returns (bool callSucceeded, bytes memory callResult);
}
