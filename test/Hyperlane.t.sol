// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import "src/hyperlane/HyperlaneHelper.sol";

interface IMailbox {
    event Dispatch(address indexed sender, uint32 indexed destination, bytes32 indexed recipient, bytes message);

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

    function handle(uint32, /*_origin*/ bytes32, /*_sender*/ bytes calldata _message) external {
        value = abi.decode(_message, (uint256));
    }
}

contract AnotherTarget {
    uint256 public value;
    address public kevin;
    bytes32 public bob;

    uint32 expectedOrigin;

    constructor(uint32 _expectedOrigin) {
        expectedOrigin = _expectedOrigin;
    }

    function handle(uint32 _origin, bytes32, /*_sender*/ bytes calldata _message) external {
        require(_origin == expectedOrigin, "Unexpected origin");
        (value, kevin, bob) = abi.decode(_message, (uint256, address, bytes32));
    }
}

contract HyperlaneHelperTest is Test {
    HyperlaneHelper hyperlaneHelper;
    Target target;
    Target altTarget;
    /// @dev is alternative target on arbitrum

    AnotherTarget anotherTarget;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint32 constant L1_DOMAIN = 1;
    uint32 constant L2_1_DOMAIN = 137;
    uint32 constant L2_2_DOMAIN = 42161;

    address constant L1_HLMailbox = 0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70;
    address constant L1_HLPaymaster = 0xdE86327fBFD04C4eA11dC0F270DA6083534c2582;
    address constant POLYGON_HLMailbox = 0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70;
    address constant POLYGON_HLPaymaster = 0xdE86327fBFD04C4eA11dC0F270DA6083534c2582;
    address constant ARBITRUM_HLMailbox = 0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70;
    address constant ARBITRUM_HLPaymaster = 0xdE86327fBFD04C4eA11dC0F270DA6083534c2582;

    address[] public allDstTargets;
    address[] public allDstMailbox;
    uint32[] public allDstDomains;
    uint256[] public allDstForks;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 16400467);
        hyperlaneHelper = new HyperlaneHelper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 38063686);
        target = new Target();
        anotherTarget = new AnotherTarget(L1_DOMAIN);

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 38063686);
        altTarget = new Target();

        allDstTargets.push(address(target));
        allDstTargets.push(address(altTarget));

        allDstDomains.push(L2_1_DOMAIN);
        allDstDomains.push(L2_2_DOMAIN);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstMailbox.push(POLYGON_HLMailbox);
        allDstMailbox.push(ARBITRUM_HLMailbox);
    }

    function testSimpleHL() external {
        vm.selectFork(L1_FORK_ID);

        // ||
        // ||
        // \/ This is the part of the code you could copy to use the HyperlaneHelper
        //    in your own tests.
        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_1_DOMAIN, TypeCasts.addressToBytes32(address(target)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        hyperlaneHelper.help(L1_HLMailbox, POLYGON_HLMailbox, POLYGON_FORK_ID, logs);
        // /\
        // ||
        // ||

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testSimpleHLWithEstimates() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_1_DOMAIN, TypeCasts.addressToBytes32(address(target)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        hyperlaneHelper.helpWithEstimates(L1_HLMailbox, POLYGON_HLMailbox, POLYGON_FORK_ID, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testFancyHL() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _aMoreFancyCrossChainFunctionInYourContract(L2_1_DOMAIN, TypeCasts.addressToBytes32(address(anotherTarget)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        hyperlaneHelper.help(L1_HLMailbox, POLYGON_HLMailbox, POLYGON_FORK_ID, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(anotherTarget.value(), 12);
        assertEq(anotherTarget.kevin(), msg.sender);
        assertEq(anotherTarget.bob(), keccak256("bob"));
    }

    function testCustomOrderingHL() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_1_DOMAIN, TypeCasts.addressToBytes32(address(target)));
        _someOtherCrossChainFunctionInYourContract(L2_1_DOMAIN, TypeCasts.addressToBytes32(address(target)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory HLLogs = hyperlaneHelper.findLogs(logs, 2);
        Vm.Log[] memory reorderedLogs = new Vm.Log[](2);
        reorderedLogs[0] = HLLogs[1];
        reorderedLogs[1] = HLLogs[0];
        hyperlaneHelper.help(L1_HLMailbox, POLYGON_HLMailbox, POLYGON_FORK_ID, reorderedLogs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testMultiDstHL() external {
        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();

        _manyCrossChainFunctionInYourContract(
            [L2_1_DOMAIN, L2_2_DOMAIN],
            [TypeCasts.addressToBytes32(address(target)), TypeCasts.addressToBytes32(address(altTarget))]
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        hyperlaneHelper.help(L1_HLMailbox, allDstMailbox, allDstDomains, allDstForks, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 21);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.value(), 21);
    }

    function _manyCrossChainFunctionInYourContract(uint32[2] memory targetDomain, bytes32[2] memory L2Target)
        internal
    {
        IMailbox mailbox = IMailbox(L1_HLMailbox);

        for (uint256 i = 0; i < targetDomain.length; i++) {
            bytes32 id = mailbox.dispatch(targetDomain[i], L2Target[i], abi.encode(uint256(21)));
            IInterchainGasPaymaster paymaster = IInterchainGasPaymaster(L1_HLPaymaster);
            paymaster.payForGas(id, targetDomain[i], 100000, msg.sender);
        }
    }

    function _someCrossChainFunctionInYourContract(uint32 targetDomain, bytes32 L2Target) internal {
        IMailbox mailbox = IMailbox(L1_HLMailbox);
        bytes32 id = mailbox.dispatch(targetDomain, L2Target, abi.encode(uint256(12)));
        IInterchainGasPaymaster paymaster = IInterchainGasPaymaster(L1_HLPaymaster);
        paymaster.payForGas(id, targetDomain, 100000, msg.sender);
    }

    function _someOtherCrossChainFunctionInYourContract(uint32 targetDomain, bytes32 L2Target) internal {
        IMailbox mailbox = IMailbox(L1_HLMailbox);
        bytes32 id = mailbox.dispatch(targetDomain, L2Target, abi.encode(uint256(6)));
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
