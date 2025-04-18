// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

library DlnExternalCallLib {
    struct ExternalCallEnvelopV1 {
        // Address that will receive takeToken if ext call failed
        address fallbackAddress;
        // *optional. Smart contract that will execute ext call.
        address executorAddress;
        // fee that will pay for executor who will execute ext call
        uint160 executionFee;
        // If false, the taker must execute an external call with fulfill in a single transaction.
        bool allowDelayedExecution;
        // if true transaction that will execute ext call will fail if ext call is not success
        bool requireSuccessfullExecution;
        bytes payload;
    }

    struct ExternalCallPayload {
        // the address of the contract to call
        address to;
        // *optional. Tx gas for execute ext call
        uint32 txGas;
        bytes callData;
    }
}
