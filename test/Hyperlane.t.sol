// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import "src/hyperlane/HyperlaneHelper.sol";

interface IMailbox {
    function dispatch(uint32 _destinationDomain, bytes32 _recipientAddress, bytes calldata _messageBody)
        external
        returns (bytes32);
}

interface IInterchainGasPaymaster {
    function payForGas(bytes32 _messageId, uint32 _destinationDomain, uint256 _gasAmount, address _refundAddress)
        external
        payable;
}

contract Target {
    uint256 public value;

    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external {
        value = abi.decode(_message, (uint256));
    }
}

contract AnotherTarget {
    uint256 public value;
    address public kevin;
    bytes32 public bob;

    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external {
        (value, kevin, bob) = abi.decode(_message, (uint256, address, bytes32));
    }
}

contract HyperlaneHelperTest is Test {
    HyperlaneHelper hyperlaneHelper;
    Target target;
    AnotherTarget anotherTarget;

    uint256 L1_FORK_ID;
    uint256 L2_FORK_ID;

    uint32 constant L1_DOMAIN = 1;
    uint32 constant L2_DOMAIN = 137;
    address constant L1_HLMailbox = 0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70;
    address constant L1_HLPaymaster = 0xdE86327fBFD04C4eA11dC0F270DA6083534c2582;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 16400467);
        hyperlaneHelper = new HyperlaneHelper();

        L2_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 38063686);
        target = new Target();
        anotherTarget = new AnotherTarget();
    }

    function testSimpleHL() external {
        vm.selectFork(L1_FORK_ID);

        // ||
        // ||
        // \/ This is the part of the code you could copy to use the HyperlaneHelper
        //    in your own tests.
        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        hyperlaneHelper.help(L1_HLMailbox, L2_FORK_ID, logs);
        // /\
        // ||
        // ||

        vm.selectFork(L2_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testSimpleHLWithEstimates() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        hyperlaneHelper.helpWithEstimates(L1_HLMailbox, L1_DOMAIN, L2_FORK_ID, logs);

        vm.selectFork(L2_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testFancyHL() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _aMoreFancyCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(anotherTarget)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        hyperlaneHelper.help(L1_HLMailbox, L2_FORK_ID, logs);

        vm.selectFork(L2_FORK_ID);
        assertEq(anotherTarget.value(), 12);
        assertEq(anotherTarget.kevin(), msg.sender);
        assertEq(anotherTarget.bob(), keccak256("bob"));
    }

    function _someCrossChainFunctionInYourContract(uint32 targetDomain, bytes32 L2Target) internal {
        IMailbox mailbox = IMailbox(L1_HLMailbox);
        bytes32 id = mailbox.dispatch(targetDomain, L2Target, abi.encode(uint256(12)));
        IInterchainGasPaymaster paymaster = IInterchainGasPaymaster(L1_HLPaymaster);
        paymaster.payForGas(id, targetDomain, 100000, msg.sender);
    }

    function _aMoreFancyCrossChainFunctionInYourContract(uint32 targetDomain, bytes32 L2Target) internal {
        IMailbox mailbox = IMailbox(L1_HLMailbox);
        bytes32 id = mailbox.dispatch(targetDomain, L2Target, abi.encode(uint256(12), msg.sender, keccak256("bob")));
        IInterchainGasPaymaster paymaster = IInterchainGasPaymaster(L1_HLPaymaster);
        paymaster.payForGas(id, targetDomain, 100000, msg.sender);
    }
}
