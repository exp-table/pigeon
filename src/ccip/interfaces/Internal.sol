// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice Vendored from `smartcontractkit/chainlink-ccip` at tag `contracts-ccip-v1.6.0`
/// (`chains/evm/contracts/libraries/Internal.sol`). Only the structs decoded from CCIP 1.6 source-side
/// emissions and reconstructed for destination-side routing are kept; merkle / commit-report / OCR
/// helpers and chain-family selectors were dropped.
library Internal {
    struct RampMessageHeader {
        bytes32 messageId;
        uint64 sourceChainSelector;
        uint64 destChainSelector;
        uint64 sequenceNumber;
        uint64 nonce;
    }

    struct EVM2AnyTokenTransfer {
        address sourcePoolAddress;
        bytes destTokenAddress; // ABI-encoded EVM address of the destination token
        bytes extraData;
        uint256 amount;
        bytes destExecData; // abi.encode(uint32 destGasAmount)
    }

    struct Any2EVMTokenTransfer {
        bytes sourcePoolAddress;
        address destTokenAddress;
        uint32 destGasAmount;
        bytes extraData;
        uint256 amount;
    }

    /// @notice Family-agnostic message routed to an OffRamp.
    struct Any2EVMRampMessage {
        RampMessageHeader header;
        bytes sender;
        bytes data;
        address receiver;
        uint256 gasLimit;
        Any2EVMTokenTransfer[] tokenAmounts;
    }

    /// @notice Family-agnostic message emitted from the OnRamp.
    struct EVM2AnyRampMessage {
        RampMessageHeader header;
        address sender;
        bytes data;
        bytes receiver;
        bytes extraArgs;
        address feeToken;
        uint256 feeTokenAmount;
        uint256 feeValueJuels;
        EVM2AnyTokenTransfer[] tokenAmounts;
    }
}
