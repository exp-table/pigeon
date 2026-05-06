// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// @notice Vendored from `smartcontractkit/chainlink-ccip` at tag `contracts-ccip-v1.6.0`
/// (`chains/evm/contracts/libraries/Client.sol`). Trimmed to the EVM-only subset that pigeon's
/// CcipHelper and tests consume; SVM/Solana extras were dropped.
library Client {
    struct EVMTokenAmount {
        address token;
        uint256 amount;
    }

    struct Any2EVMMessage {
        bytes32 messageId;
        uint64 sourceChainSelector;
        bytes sender; // abi.decode(sender, (address)) for EVM source chains
        bytes data;
        EVMTokenAmount[] destTokenAmounts;
    }

    struct EVM2AnyMessage {
        bytes receiver; // abi.encode(address)
        bytes data;
        EVMTokenAmount[] tokenAmounts;
        address feeToken; // address(0) ⇒ msg.value (native)
        bytes extraArgs;
    }

    /// @dev Tag for legacy gas-limit-only extra args.
    bytes4 public constant EVM_EXTRA_ARGS_V1_TAG = 0x97a657c9;

    struct EVMExtraArgsV1 {
        uint256 gasLimit;
    }

    function _argsToBytes(EVMExtraArgsV1 memory extraArgs) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(EVM_EXTRA_ARGS_V1_TAG, extraArgs);
    }

    /// @dev Tag for current gas-limit + out-of-order extra args.
    bytes4 public constant GENERIC_EXTRA_ARGS_V2_TAG = 0x181dcf10;

    struct GenericExtraArgsV2 {
        uint256 gasLimit;
        bool allowOutOfOrderExecution;
    }

    function _argsToBytes(GenericExtraArgsV2 memory extraArgs) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(GENERIC_EXTRA_ARGS_V2_TAG, extraArgs);
    }
}
