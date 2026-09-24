// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice a destination contract that consumes a Gateway attestation itself (e.g. Superform's
///         CircleGatewayAdapter): it calls GatewayMinter.gatewayMint and acts on the TransferSpec's hookData
interface IGatewayAttestationReceiver {
    function receiveAndExecute(bytes calldata attestationPayload, bytes calldata signature) external;
}
