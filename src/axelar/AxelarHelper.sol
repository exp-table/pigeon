// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import {AddressHelper} from "../axelar/lib/AddressHelper.sol";

interface IAxelarExecutable {
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}

/// @title Axelar Helper
/// @notice helps mock the message transfer using axelar bridge
contract AxelarHelper is Test {
    bytes32 constant MESSAGE_EVENT_SELECTOR =
        0x30ae6cc78c27e651745bf2ad08a11de83910ac1e347a52f7ac898c0fbef94dae;

    function help(
        string memory fromChain,
        address toGateway,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(fromChain, toGateway, forkId, MESSAGE_EVENT_SELECTOR, logs);
    }

    function _help(
        string memory fromChain,
        address toGateway,
        uint256 forkId,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) internal {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(forkId);

        vm.startBroadcast(toGateway);

        for (uint256 i; i < logs.length; i++) {
            Vm.Log memory log = logs[i];

            if (log.topics[0] == eventSelector) {
                address sender = address(uint160(uint256(log.topics[1])));

                string memory destinationChain;
                string memory destinationContract;

                bytes memory payload;

                (destinationChain, destinationContract, payload) = abi.decode(
                    log.data,
                    (string, string, bytes)
                );

                IAxelarExecutable(AddressHelper.fromString(destinationContract))
                    .execute(
                        log.topics[2], /// payloadHash
                        fromChain,
                        AddressHelper.toString(sender),
                        payload
                    );
            }
        }

        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }
}
