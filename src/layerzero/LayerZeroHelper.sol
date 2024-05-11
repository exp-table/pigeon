// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
import "./lib/LZPacket.sol";

interface ILayerZeroEndpoint {
    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        uint256 _gasLimit,
        bytes calldata _payload
    ) external;

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external returns (uint256 nativeFee, uint256 zroFee);
}

/// @title LayerZero Helper
/// @notice helps simulate message transfers using the LayerZero protocol (version 1)
contract LayerZeroHelper is Test {
    /// @dev is the default packet selector if not specified by the user
    bytes32 constant PACKET_SELECTOR = 0xe9bded5f24a4168e4f3bf44e00298c993b22376aad8c58c7dda9718a54cbea82;

    /// @dev is the default library address if not specified by the user
    address constant DEFAULT_LIBRARY = 0x4D73AdB72bC3DD368966edD0f0b2148401A178E2;

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helps with multiple destination transfers
    /// @param endpoints represents the array of endpoint addresses
    /// @param expChainIds represents the array of expected chain ids
    /// @param gasToSend represents the gas to send for message execution
    /// @param forkId represents the array of destination fork IDs (localized to your testing)
    /// @param logs represents the array of logs

    function help(
        address[] memory endpoints,
        uint16[] memory expChainIds,
        /// expected chain ids
        uint256 gasToSend,
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i = 0; i < expChainIds.length; i++) {
            _help(endpoints[i], expChainIds[i], DEFAULT_LIBRARY, gasToSend, PACKET_SELECTOR, forkId[i], logs, false);
        }
    }

    /// @notice helps with a single destination transfer (hardcoded default library and packet selector)
    /// @param endpoint represents the endpoint address
    /// @param gasToSend represents the gas to send for message execution
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    function help(address endpoint, uint256 gasToSend, uint256 forkId, Vm.Log[] calldata logs) external {
        _help(endpoint, 0, DEFAULT_LIBRARY, gasToSend, PACKET_SELECTOR, forkId, logs, false);
    }

    /// @notice helps with a single destination transfer (custom default library and event selector)
    /// @param endpoint represents the endpoint address
    /// @param defaultLibrary represents the default library address
    /// @param gasToSend represents the gas to send for message execution
    /// @param eventSelector represents the event selector
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    function help(
        address endpoint,
        address defaultLibrary,
        uint256 gasToSend,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(endpoint, 0, defaultLibrary, gasToSend, eventSelector, forkId, logs, false);
    }

    /// @notice helps with multiple destination transfers and estimates gas
    /// @param endpoints represents the array of endpoint addresses
    /// @param expChainIds represents the array of expected chain ids
    /// @param gasToSend represents the gas to send for message execution
    /// @param forkId represents the array of destination fork IDs (localized to your testing)
    /// @param logs represents the array of logs
    function helpWithEstimates(
        address[] memory endpoints,
        uint16[] memory expChainIds,
        /// expected chain ids
        uint256 gasToSend,
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_LZ_ESTIMATES", false);
        for (uint256 i = 0; i < expChainIds.length; i++) {
            _help(
                endpoints[i],
                expChainIds[i],
                DEFAULT_LIBRARY,
                gasToSend,
                PACKET_SELECTOR,
                forkId[i],
                logs,
                enableEstimates
            );
        }
    }

    /// @notice helps with a single destination transfer and estimates gas (hardcoded default library and packet selector)
    /// @param endpoint represents the endpoint address
    /// @param gasToSend represents the gas to send for message execution
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    function helpWithEstimates(address endpoint, uint256 gasToSend, uint256 forkId, Vm.Log[] calldata logs) external {
        bool enableEstimates = vm.envOr("ENABLE_LZ_ESTIMATES", false);
        _help(endpoint, 0, DEFAULT_LIBRARY, gasToSend, PACKET_SELECTOR, forkId, logs, enableEstimates);
    }

    /// @notice helps with a single destination transfer and estimates gas (custom default library and event selector)
    /// @param endpoint represents the endpoint address
    /// @param defaultLibrary represents the default library address
    /// @param gasToSend represents the gas to send for message execution
    /// @param eventSelector represents the event selector
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    function helpWithEstimates(
        address endpoint,
        address defaultLibrary,
        uint256 gasToSend,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        bool enableEstimates = vm.envOr("ENABLE_LZ_ESTIMATES", false);
        _help(endpoint, 0, defaultLibrary, gasToSend, eventSelector, forkId, logs, enableEstimates);
    }

    /// @notice finds logs with the default packet selector
    /// @param logs represents the array of logs
    /// @param length represents the expected number of logs
    /// @return lzLogs array of found logs
    function findLogs(Vm.Log[] calldata logs, uint256 length) external pure returns (Vm.Log[] memory lzLogs) {
        return _findLogs(logs, PACKET_SELECTOR, length);
    }

    /// @notice finds logs with a specific event selector
    /// @param logs represents the array of logs
    /// @param eventSelector represents the event selector
    /// @param length represents the expected number of logs
    /// @return lzLogs array of found logs
    function findLogs(Vm.Log[] calldata logs, bytes32 eventSelector, uint256 length)
        external
        pure
        returns (Vm.Log[] memory lzLogs)
    {
        return _findLogs(logs, eventSelector, length);
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice internal function to help with destination transfers
    /// @param endpoint represents the endpoint address
    /// @param expChainId represents the expected chain id
    /// @param defaultLibrary represents the default library address
    /// @param gasToSend represents the gas to send for message execution
    /// @param eventSelector represents the event selector
    /// @param forkId represents the destination fork ID (localized to your testing)
    /// @param logs represents the array of logs
    /// @param enableEstimates flag to enable gas estimates
    function _help(
        address endpoint,
        uint16 expChainId,
        address defaultLibrary,
        uint256 gasToSend,
        bytes32 eventSelector,
        uint256 forkId,
        Vm.Log[] memory logs,
        bool enableEstimates
    ) internal {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(forkId);
        // larps as default library
        vm.startBroadcast(defaultLibrary);
        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            // unsure if the default library always emits the event
            if (
                log
                    /*log.emitter == defaultLibrary &&*/
                    .topics[0] == eventSelector
            ) {
                bytes memory payload = abi.decode(log.data, (bytes));
                LayerZeroPacket.Packet memory packet = LayerZeroPacket.getPacket(payload);
                if (packet.dstChainId == expChainId || expChainId == 0) {
                    _receivePayload(endpoint, packet, gasToSend, enableEstimates);
                }
            }
        }
        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }

    /// @notice estimates gas for message execution
    /// @param endpoint represents the endpoint address
    /// @param destination represents the destination chain id
    /// @param userApplication represents the user application address
    /// @param payload represents the message payload
    /// @param payInZRO flag to indicate if fees should be paid in ZRO tokens
    /// @param adapterParam represents the adapter parameters
    /// @return gasEstimate the estimated gas
    function _estimateGas(
        address endpoint,
        uint16 destination,
        address userApplication,
        bytes memory payload,
        bool payInZRO,
        bytes memory adapterParam
    ) internal returns (uint256 gasEstimate) {
        (uint256 nativeGas,) =
            ILayerZeroEndpoint(endpoint).estimateFees(destination, userApplication, payload, payInZRO, adapterParam);
        return nativeGas;
    }

    /// @notice receives the payload and executes the message
    /// @param endpoint represents the endpoint address
    /// @param packet represents the LayerZero packet
    /// @param gasToSend represents the gas to send for message execution
    /// @param enableEstimates flag to enable gas estimates
    function _receivePayload(
        address endpoint,
        LayerZeroPacket.Packet memory packet,
        uint256 gasToSend,
        bool enableEstimates
    ) internal {
        bytes memory path = abi.encodePacked(packet.srcAddress, packet.dstAddress);
        vm.store(
            address(endpoint),
            keccak256(abi.encodePacked(path, keccak256(abi.encodePacked(uint256(packet.srcChainId), uint256(5))))),
            bytes32(uint256(packet.nonce))
        );

        ILayerZeroEndpoint(endpoint).receivePayload(
            packet.srcChainId, path, packet.dstAddress, packet.nonce + 1, gasToSend, packet.payload
        );

        if (enableEstimates) {
            uint256 gasEstimate =
                _estimateGas(endpoint, packet.dstChainId, packet.dstAddress, packet.payload, false, "");
            emit log_named_uint("gasEstimate", gasEstimate);
        }
    }

    /// @notice internal function to find logs with a specific event selector
    /// @param logs represents the array of logs
    /// @param eventSelector represents the event selector
    /// @param length represents the expected number of logs
    /// @return lzLogs array of found logs
    function _findLogs(Vm.Log[] memory logs, bytes32 eventSelector, uint256 length)
        internal
        pure
        returns (Vm.Log[] memory lzLogs)
    {
        lzLogs = new Vm.Log[](length);

        uint256 currentIndex = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSelector) {
                lzLogs[currentIndex] = logs[i];
                currentIndex++;

                if (currentIndex == length) {
                    break;
                }
            }
        }
    }
}
