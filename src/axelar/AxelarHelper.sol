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

interface IAxelarGateway {
    function approveContractCall(bytes calldata params, bytes32 commandId) external;

    function callContract(string calldata destinationChain, string calldata contractAddress, bytes calldata payload)
        external;
}

/// @title Axelar Helper
/// @notice helps mock the message transfer using axelar bridge
contract AxelarHelper is Test {
    bytes32 constant MESSAGE_EVENT_SELECTOR = 0x30ae6cc78c27e651745bf2ad08a11de83910ac1e347a52f7ac898c0fbef94dae;

    function help(
        string memory fromChain,
        address[] memory toGateway,
        string[] memory expDstChain,
        uint256[] memory forkId,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i; i < toGateway.length; i++) {
            _help(fromChain, toGateway[i], expDstChain[i], forkId[i], MESSAGE_EVENT_SELECTOR, logs);
        }
    }

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
        _help(fromChain, toGateway, expDstChain, forkId, MESSAGE_EVENT_SELECTOR, logs);
    }

    function findLogs(Vm.Log[] calldata logs, uint256 length) external pure returns (Vm.Log[] memory HLLogs) {
        return _findLogs(logs, MESSAGE_EVENT_SELECTOR, length);
    }

    struct LocalVars {
        uint256 prevForkId;
        Vm.Log log;
        string destinationChain;
        string destinationContract;
        bytes payload;
    }

    function _help(
        string memory fromChain,
        address toGateway,
        string memory expDstChain,
        uint256 forkId,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) internal {
        LocalVars memory v;
        v.prevForkId = vm.activeFork();

        vm.selectFork(forkId);
        vm.startBroadcast(toGateway);

        for (uint256 i; i < logs.length; i++) {
            v.log = logs[i];

            if (v.log.topics[0] == eventSelector) {
                (v.destinationChain, v.destinationContract, v.payload) = abi.decode(v.log.data, (string, string, bytes));

                /// FIXME: length based checks aren't sufficient
                if (isStringsEqual(expDstChain, v.destinationChain)) {
                    string memory srcAddress = AddressHelper.toString(address(uint160(uint256(v.log.topics[1]))));
                    address dstContract = AddressHelper.fromString(v.destinationContract);

                    IAxelarGateway(toGateway).approveContractCall(
                        abi.encode(fromChain, srcAddress, dstContract, keccak256(v.payload), bytes32(0), i),
                        v.log.topics[2]
                    );

                    IAxelarExecutable(dstContract).execute(
                        v.log.topics[2],
                        /// payloadHash
                        fromChain,
                        srcAddress,
                        v.payload
                    );
                }
            }
        }

        vm.stopBroadcast();
        vm.selectFork(v.prevForkId);
    }

    function isStringsEqual(string memory a, string memory b) public pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    function _findLogs(Vm.Log[] memory logs, bytes32 dispatchSelector, uint256 length)
        internal
        pure
        returns (Vm.Log[] memory AxelarLogs)
    {
        AxelarLogs = new Vm.Log[](length);

        uint256 currentIndex = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == dispatchSelector) {
                AxelarLogs[currentIndex] = logs[i];
                currentIndex++;

                if (currentIndex == length) {
                    break;
                }
            }
        }
    }
}
