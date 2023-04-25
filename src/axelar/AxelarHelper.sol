// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import {TypeCasts} from "../hyperlane/lib/TypeCasts.sol";

/// @title Axelar Helper
/// @notice helps mock the message transfer using axelar bridge
contract AxelarHelper is Test {
    bytes32 constant MESSAGE_EVENT_SELECTOR =
        0x30ae6cc78c27e651745bf2ad08a11de83910ac1e347a52f7ac898c0fbef94dae;

    function help(
        address toGateway,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(toGateway, forkId, MESSAGE_EVENT_SELECTOR, logs);
    }

    function _help(
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
                bytes memory data = abi.decode(log.data, (bytes));
                bytes32 sender = log.topics[1];
                bytes32 payloadHash = log.topics[2];

                string memory destinationChain;

                assembly {
                    destinationChain := mload(add(data, 0x20))
                }

                console.log(destinationChain);
            }
        }

        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }
}
