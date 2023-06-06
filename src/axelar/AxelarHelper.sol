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
        address[] memory toGateway,
        string[] memory expDstChain,
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {}

    function help(
        string memory fromChain,
        address toGateway,
        string memory expDstChain,
        uint256 forkId,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        _help(fromChain, toGateway, expDstChain, forkId, eventSelector, logs);
    }

    function help(
        string memory fromChain,
        address toGateway,
        string memory expDstChain,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(
            fromChain,
            toGateway,
            expDstChain,
            forkId,
            MESSAGE_EVENT_SELECTOR,
            logs
        );
    }

    function _help(
        string memory fromChain,
        address toGateway,
        string memory expDstChain,
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
                string memory destinationChain;
                string memory destinationContract;

                bytes memory payload;

                (destinationChain, destinationContract, payload) = abi.decode(
                    log.data,
                    (string, string, bytes)
                );

                /// FIXME: length based checks aren't sufficient
                if (isStringsEqual(expDstChain, destinationChain)) {
                    IAxelarExecutable(
                        AddressHelper.fromString(destinationContract)
                    ).execute(
                            log.topics[2], /// payloadHash
                            fromChain,
                            AddressHelper.toString(
                                address(uint160(uint256(log.topics[1])))
                            ),
                            payload
                        );
                }
            }
        }

        vm.stopBroadcast();
        vm.selectFork(prevForkId);
    }

    function isStringsEqual(
        string memory a,
        string memory b
    ) public view returns (bool) {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }
}
