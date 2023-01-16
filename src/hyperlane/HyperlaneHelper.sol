// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "solady/utils/LibString.sol";

import {TypeCasts} from "./lib/TypeCasts.sol";

interface IMessageRecipient {
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external;
}

contract HyperlaneHelper is Test {
    function help(address mailbox, uint256 forkId, Vm.Log[] calldata logs) external {
        return _help(mailbox, 0x769f711d20c679153d382254f59892613b58a97cc876b249134ac25c80f9c814, forkId, logs);
    }

    function help(address mailbox, bytes32 dispatchSelector, uint256 forkId, Vm.Log[] calldata logs) external {
        _help(mailbox, dispatchSelector, forkId, logs);
    }

    function _help(address mailbox, bytes32 dispatchSelector, uint256 forkId, Vm.Log[] memory logs) internal {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(forkId);
        vm.startBroadcast(mailbox);
        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.emitter == mailbox && log.topics[0] == dispatchSelector) {
                bytes32 sender = log.topics[1];
                uint32 destinationDomain = uint32(uint256(log.topics[2]));
                bytes32 recipient = log.topics[3];
                bytes memory message = abi.decode(log.data, (bytes));

                uint256 gasEstimate = _estimateGas(0, destinationDomain, _handle(message));
                emit log_named_uint("gasEstimate", gasEstimate);
            }
        }
        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }

    function _estimateGas(uint32 origin, uint32 destination, uint256 handleGas)
        internal
        returns (uint256 gasEstimate)
    {
        string[] memory cmds = new string[](9);

        // Build ffi command string
        cmds[0] = "npm";
        cmds[1] = "--silent";
        cmds[2] = "--prefix";
        cmds[3] = "utils/scripts/";
        cmds[4] = "run";
        cmds[5] = "estimateHLGas";
        cmds[6] = LibString.toHexString(origin);
        cmds[7] = LibString.toHexString(destination);
        cmds[8] = LibString.toString(handleGas);

        bytes memory result = vm.ffi(cmds);
        gasEstimate = abi.decode(result, (uint256));
    }

    function _handle(bytes memory message) internal returns (uint256 handleGas) {
        bytes32 _recipient;
        uint256 _originDomain;
        bytes32 _sender;
        bytes memory body = bytes(LibString.slice(string(message), 0x4d));
        assembly {
            _sender := mload(add(message, 0x29))
            _recipient := mload(add(message, 0x4d))
            _originDomain := and(mload(add(message, 0x2d)), 0xffffffff)
        }
        address recipient = TypeCasts.bytes32ToAddress(_recipient);
        uint32 originDomain = uint32(_originDomain);
        bytes32 sender = _sender;
        uint256 handleGasStart = gasleft();
        IMessageRecipient(recipient).handle(originDomain, sender, body);
        handleGas = handleGasStart - gasleft();
    }
}
