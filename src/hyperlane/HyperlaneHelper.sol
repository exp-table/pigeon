// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import "solady/src/utils/LibString.sol";

/// local imports
import {TypeCasts} from "../libraries/TypeCasts.sol";

interface IMessageRecipient {
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external;
}

/// @title Hyperlane Helper
/// @notice Helps simulate message transfers using the Hyperlane interchain messaging protocol
contract HyperlaneHelper is Test {
    /// @dev The default dispatch selector if not specified by the user
    bytes32 constant DISPATCH_SELECTOR = 0x769f711d20c679153d382254f59892613b58a97cc876b249134ac25c80f9c814;

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helps with multiple destination transfers
    /// @param fromMailbox represents the source mailbox address
    /// @param toMailbox represents the array of destination mailbox addresses
    /// @param expDstDomains represents the array of expected destination domains
    /// @param forkId represents the array of destination fork IDs (localized to your testing)
    /// @param logs represents the array of logs
    function help(
        address fromMailbox,
        address[] memory toMailbox,
        uint32[] memory expDstDomains,
        /// expected destination domain
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i = 0; i < expDstDomains.length; i++) {
            _help(fromMailbox, toMailbox[i], expDstDomains[i], DISPATCH_SELECTOR, forkId[i], logs, false);
        }
    }

    /// @notice helps with a single destination transfer
    /// @param fromMailbox represents the source mailbox address
    /// @param toMailbox represents the destination mailbox address
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    function help(address fromMailbox, address toMailbox, uint256 forkId, Vm.Log[] calldata logs) external {
        return _help(fromMailbox, toMailbox, 0, DISPATCH_SELECTOR, forkId, logs, false);
    }

    /// @notice helps with a single destination transfer with a specific dispatch selector
    /// @param fromMailbox represents the source mailbox address
    /// @param toMailbox represents the destination mailbox address
    /// @param dispatchSelector represents the dispatch selector
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    function help(
        address fromMailbox,
        address toMailbox,
        bytes32 dispatchSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(fromMailbox, toMailbox, 0, dispatchSelector, forkId, logs, false);
    }

    /// @notice helps with multiple destination transfers and estimates gas
    /// @param fromMailbox represents the source mailbox address
    /// @param toMailbox represents the array of destination mailbox addresses
    /// @param expDstDomains represents the array of expected destination domains
    /// @param forkId represents the array of destination fork IDs (localized to your testing)
    /// @param logs represents the array of logs
    function helpWithEstimates(
        address fromMailbox,
        address[] memory toMailbox,
        uint32[] memory expDstDomains,
        /// expected destination domains
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_HYPERLANE_ESTIMATES", false);
        for (uint256 i = 0; i < expDstDomains.length; i++) {
            _help(fromMailbox, toMailbox[i], expDstDomains[i], DISPATCH_SELECTOR, forkId[i], logs, enableEstimates);
        }
    }

    /// @notice helps with a single destination transfer and estimates gas
    /// @param fromMailbox represents the source mailbox address
    /// @param toMailbox represents the destination mailbox address
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    function helpWithEstimates(address fromMailbox, address toMailbox, uint256 forkId, Vm.Log[] calldata logs)
        external
    {
        bool enableEstimates = vm.envOr("ENABLE_HYPERLANE_ESTIMATES", false);
        _help(fromMailbox, toMailbox, 0, DISPATCH_SELECTOR, forkId, logs, enableEstimates);
    }

    /// @notice helps with a single destination transfer with a specific dispatch selector and estimates gas
    /// @param fromMailbox represents the source mailbox address
    /// @param toMailbox represents the destination mailbox address
    /// @param dispatchSelector represents the dispatch selector
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    function helpWithEstimates(
        address fromMailbox,
        address toMailbox,
        bytes32 dispatchSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_HYPERLANE_ESTIMATES", false);
        _help(fromMailbox, toMailbox, 0, dispatchSelector, forkId, logs, enableEstimates);
    }

    /// @notice finds logs with the default dispatch selector
    /// @param logs represents the array of logs
    /// @param length represents the expected number of logs
    /// @return HLLogs array of found logs
    function findLogs(Vm.Log[] calldata logs, uint256 length) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, DISPATCH_SELECTOR, length);
    }

    /// @notice finds logs with a specific dispatch selector
    /// @param logs represents the array of logs
    /// @param dispatchSelector represents the dispatch selector
    /// @param length represents the expected number of logs
    /// @return HLLogs array of found logs
    function findLogs(Vm.Log[] calldata logs, bytes32 dispatchSelector, uint256 length)
        external
        pure
        returns (Vm.Log[] memory HLLogs)
    {
        return _findLogs(logs, dispatchSelector, length);
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice internal function to help with destination transfers
    /// @param fromMailbox represents the source mailbox address
    /// @param toMailbox represents the destination mailbox address
    /// @param expDstDomain represents the expected destination domain
    /// @param dispatchSelector represents the dispatch selector
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    /// @param enableEstimates flag to enable gas estimates
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
            if (log.emitter == fromMailbox && log.topics[0] == dispatchSelector) {
                uint32 destinationDomain = uint32(uint256(log.topics[2]));
                bytes memory message = abi.decode(log.data, (bytes));

                if (expDstDomain == destinationDomain || expDstDomain == 0) {
                    _handle(message, destinationDomain, enableEstimates);
                }
            }
        }
        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }

    /// @notice estimates gas for message handling
    /// @param originDomain represents the origin domain
    /// @param destinationDomain represents the destination domain
    /// @param handleGas represents the gas used for message handling
    /// @return gasEstimate the estimated gas
    function _estimateGas(uint32 originDomain, uint32 destinationDomain, uint256 handleGas)
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
        cmds[6] = LibString.toHexString(originDomain);
        cmds[7] = LibString.toHexString(destinationDomain);
        cmds[8] = LibString.toString(handleGas);

        bytes memory result = vm.ffi(cmds);
        gasEstimate = abi.decode(result, (uint256));
    }

    /// @notice handles the message
    /// @param message represents the message data
    /// @param destinationDomain represents the destination domain
    /// @param enableEstimates flag to enable gas estimates
    function _handle(bytes memory message, uint32 destinationDomain, bool enableEstimates) internal {
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

        uint32 originDomain = uint32(_originDomain);
        bytes32 sender = _sender;
        uint256 handleGas = gasleft();
        IMessageRecipient(recipient).handle(originDomain, sender, body);
        handleGas -= gasleft();

        if (enableEstimates) {
            uint256 gasEstimate = _estimateGas(originDomain, destinationDomain, handleGas);
            emit log_named_uint("gasEstimate", gasEstimate);
        }
    }

    /// @notice internal function to find logs with a specific dispatch selector
    /// @param logs represents the array of logs
    /// @param dispatchSelector represents the dispatch selector
    /// @param length represents the expected number of logs
    /// @return HLLogs array of found logs
    function _findLogs(Vm.Log[] memory logs, bytes32 dispatchSelector, uint256 length)
        internal
        pure
        returns (Vm.Log[] memory HLLogs)
    {
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
