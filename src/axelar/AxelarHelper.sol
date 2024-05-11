// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
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
/// @notice helps simulate the message transfer using axelar bridge
contract AxelarHelper is Test {
    /// @dev is the default event selector if not specified by the user
    bytes32 constant MESSAGE_EVENT_SELECTOR = 0x30ae6cc78c27e651745bf2ad08a11de83910ac1e347a52f7ac898c0fbef94dae;

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helps with multiple destination transfers
    /// @param fromChain represents the source chain
    /// @param toGateway represents the destination gateway addresses
    /// @param expDstChain represents the expected destination chains
    /// @param forkId array of destination fork ids (localized to your testing)
    /// @param logs array of logs
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

    /// @notice helps with a single destination transfer with a specific event selector
    /// @param fromChain represents the source chain
    /// @param toGateway represents the destination gateway address
    /// @param expDstChain represents the expected destination chain
    /// @param forkId represents the destination fork id (localized to your testing)
    /// @param eventSelector represents the event selector
    /// @param logs array of logs
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

    /// @notice helps with a single destination transfer
    /// @param fromChain represents the source chain
    /// @param toGateway represents the destination gateway address
    /// @param expDstChain represents the expected destination chain
    /// @param forkId represents the destination fork id (localized to your testing)
    /// @param logs array of logs
    function help(
        string memory fromChain,
        address toGateway,
        string memory expDstChain,
        uint256 forkId,
        Vm.Log[] calldata logs
    ) external {
        _help(fromChain, toGateway, expDstChain, forkId, MESSAGE_EVENT_SELECTOR, logs);
    }

    /// @notice finds logs with a specific event selector
    /// @param logs array of logs
    /// @param length expected number of logs
    /// @return HLLogs array of found logs
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

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice internal function to help with destination transfers
    /// @param fromChain represents the source chain
    /// @param toGateway represents the destination gateway address
    /// @param expDstChain represents the expected destination chain
    /// @param forkId represents the destination fork id (localized to your testing)
    /// @param eventSelector represents the event selector
    /// @param logs array of logs
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

                if (_isStringsEqual(expDstChain, v.destinationChain)) {
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

    /// @notice checks if two strings are equal
    /// @param a first string
    /// @param b second string
    /// @return true if the strings are equal, false otherwise
    function _isStringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }

    /// @notice internal function to find logs with a specific event selector
    /// @param logs array of logs
    /// @param dispatchSelector event selector
    /// @param length expected number of logs
    /// @return AxelarLogs array of found logs
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
