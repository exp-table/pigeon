// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "solady/utils/LibString.sol";

import {TypeCasts} from "./lib/TypeCasts.sol";

interface IMessageRecipient {
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) external;
}

contract HyperlaneHelper is Test {
    bytes32 constant DISPATCH_SELECTOR =
        0x769f711d20c679153d382254f59892613b58a97cc876b249134ac25c80f9c814;

    function help(
        address fromMailbox,
        address[] memory toMailbox,
        uint32[] memory expDstDomains,
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i = 0; i < expDstDomains.length; i++) {
            _help(
                fromMailbox,
                toMailbox[i],
                expDstDomains[i],
                DISPATCH_SELECTOR,
                forkId[i],
                logs,
                false
            );
        }
    }

    function help(
        address fromMailbox,
        address toMailbox,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        return
            _help(
                fromMailbox,
                toMailbox,
                0,
                DISPATCH_SELECTOR,
                forkId,
                logs,
                false
            );
    }

    function help(
        address fromMailbox,
        address toMailbox,
        bytes32 dispatchSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(fromMailbox, toMailbox, 0, dispatchSelector, forkId, logs, false);
    }

    function helpWithEstimates(
        address fromMailbox,
        address[] memory toMailbox,
        uint32[] memory expDstDomains,
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_ESTIMATES", false);
        for (uint256 i = 0; i < expDstDomains.length; i++) {
            _help(
                fromMailbox,
                toMailbox[i],
                expDstDomains[i],
                DISPATCH_SELECTOR,
                forkId[i],
                logs,
                enableEstimates
            );
        }
    }

    function helpWithEstimates(
        address fromMailbox,
        address toMailbox,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_ESTIMATES", false);
        _help(
            fromMailbox,
            toMailbox,
            0,
            DISPATCH_SELECTOR,
            forkId,
            logs,
            enableEstimates
        );
    }

    function helpWithEstimates(
        address fromMailbox,
        address toMailbox,
        bytes32 dispatchSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_ESTIMATES", false);
        _help(
            fromMailbox,
            toMailbox,
            0,
            dispatchSelector,
            forkId,
            logs,
            enableEstimates
        );
    }

    function findLogs(
        Vm.Log[] calldata logs,
        uint256 length
    ) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, DISPATCH_SELECTOR, length);
    }

    function findLogs(
        Vm.Log[] calldata logs,
        bytes32 dispatchSelector,
        uint256 length
    ) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, dispatchSelector, length);
    }

    function _help(
        address fromMailbox,
        address toMailbox,
        uint32 expDstDomain,
        bytes32 dispatchSelector,
        uint256 forkId,
        Vm.Log[] memory logs,
        bool enableEstimates
    ) internal {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(forkId);
        vm.startBroadcast(toMailbox);
        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (
                log.emitter == fromMailbox && log.topics[0] == dispatchSelector
            ) {
                bytes32 sender = log.topics[1];
                uint32 destinationDomain = uint32(uint256(log.topics[2]));
                bytes32 recipient = log.topics[3];
                bytes memory message = abi.decode(log.data, (bytes));
                console.log(expDstDomain, destinationDomain);
                if (expDstDomain == destinationDomain || expDstDomain == 0) {
                    _handle(message, destinationDomain, enableEstimates);
                }
            }
        }
        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }

    function _estimateGas(
        uint32 originDomain,
        uint32 destinationDomain,
        uint256 handleGas
    ) internal returns (uint256 gasEstimate) {
        string[] memory cmds = new string[](9);

        // Build ffi command string
        cmds[0] = "npm";
        cmds[1] = "--silent";
        cmds[2] = "--prefix";
        cmds[3] = "utils/scripts/";
        cmds[4] = "run";
        cmds[5] = "estimateHLGas";
        cmds[6] = LibString.toHexString(originDomain);
        cmds[7] = LibString.toHexString(destinationDomain);
        cmds[8] = LibString.toString(handleGas);

        bytes memory result = vm.ffi(cmds);
        gasEstimate = abi.decode(result, (uint256));
    }

    function _handle(
        bytes memory message,
        uint32 destinationDomain,
        bool enableEstimates
    ) internal {
        bytes32 _recipient;
        uint256 _originDomain;
        bytes32 _sender;
        bytes memory body = bytes(LibString.slice(string(message), 0x4d));
        assembly {
            _sender := mload(add(message, 0x29))
            _recipient := mload(add(message, 0x4d))
            _originDomain := and(mload(add(message, 0x09)), 0xffffffff)
        }
        address recipient = TypeCasts.bytes32ToAddress(_recipient);
        console.log(recipient);
        uint32 originDomain = uint32(_originDomain);
        bytes32 sender = _sender;
        uint256 handleGas = gasleft();
        IMessageRecipient(recipient).handle(originDomain, sender, body);
        handleGas -= gasleft();

        if (enableEstimates) {
            uint256 gasEstimate = _estimateGas(
                originDomain,
                destinationDomain,
                handleGas
            );
            emit log_named_uint("gasEstimate", gasEstimate);
        }
    }

    function _findLogs(
        Vm.Log[] memory logs,
        bytes32 dispatchSelector,
        uint256 length
    ) internal pure returns (Vm.Log[] memory HLLogs) {
        HLLogs = new Vm.Log[](length);

        uint256 currentIndex = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == dispatchSelector) {
                HLLogs[currentIndex] = logs[i];
                currentIndex++;

                if (currentIndex == length) {
                    break;
                }
            }
        }
    }
}
