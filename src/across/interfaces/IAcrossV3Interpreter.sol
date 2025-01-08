// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IAcrossV3Interpreter {
    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/
    // TODO: might remove after we test cross chain flow
    struct EntryPointData {
        address account;
        uint256 callGasLimit;
        uint256 verificationGasLimit;
        uint256 preVerificationGas;
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        bytes paymasterAndData;
        bytes signature;
        address payable beneficiary;
    }

    struct Instruction {
        bytes strategyData; // ISuperExecutor.ExecutorEntry[]
        uint256 amount;
        address account;
    }
}
