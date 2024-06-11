// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "src/celer/CelerHelper.sol";

contract Target {
    uint256 public value;

    enum ExecutionStatus {
        Fail, // execution failed, finalized
        Success, // execution succeeded, finalized
        Retry // execution rejected, can retry later

    }

    function executeMessage(
        address, /*_sender*/
        uint64, /*_srcChainId*/
        bytes calldata _message,
        address /*_executor*/
    ) external payable returns (ExecutionStatus) {
        value = abi.decode(_message, (uint256));

        return ExecutionStatus.Success;
    }
}

contract AnotherTarget {
    uint256 public value;
    address public kevin;
    bytes32 public bob;

    uint64 expectedChainId;

    enum ExecutionStatus {
        Fail, // execution failed, finalized
        Success, // execution succeeded, finalized
        Retry // execution rejected, can retry later

    }

    constructor(uint64 _expectedChainId) {
        expectedChainId = _expectedChainId;
    }

    function executeMessage(address, /*_sender*/ uint64 _srcChainId, bytes calldata _message, address /*_executor*/ )
        external
        payable
        returns (ExecutionStatus)
    {
        require(_srcChainId == expectedChainId, "Unexpected origin");
        (value, kevin, bob) = abi.decode(_message, (uint256, address, bytes32));

        return ExecutionStatus.Success;
    }
}

contract CelerHelperTest is Test {
    CelerHelper celerHelper;
    Target target;
    Target altTarget;

    AnotherTarget anotherTarget;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint256 CROSS_CHAIN_MESSAGE = UINT256_MAX;

    uint64 constant L1_CHAIN_ID = 1;
    uint64 constant L2_1_CHAIN_ID = 137;
    uint64 constant L2_2_CHAIN_ID = 42161;

    address constant L1_CelerMessageBus = 0x4066D196A423b2b3B8B054f4F40efB47a74E200C;
    address constant POLYGON_CelerMessageBus = 0x95714818fdd7a5454F73Da9c777B3ee6EbAEEa6B;
    address constant ARBITRUM_CelerMessageBus = 0x3Ad9d0648CDAA2426331e894e980D0a5Ed16257f;

    address[] public allDstTargets;
    address[] public allDstMessageBus;
    uint64[] public allDstChainIds;
    uint256[] public allDstForks;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 16400467);
        celerHelper = new CelerHelper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 38063686);
        target = new Target();
        anotherTarget = new AnotherTarget(L1_CHAIN_ID);

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 38063686);
        altTarget = new Target();

        allDstTargets.push(address(target));
        allDstTargets.push(address(altTarget));

        allDstChainIds.push(L2_1_CHAIN_ID);
        allDstChainIds.push(L2_2_CHAIN_ID);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstMessageBus.push(POLYGON_CelerMessageBus);
        allDstMessageBus.push(ARBITRUM_CelerMessageBus);
    }

    function testSimpleCeler() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        celerHelper.help(L1_CHAIN_ID, L1_CelerMessageBus, POLYGON_CelerMessageBus, L2_1_CHAIN_ID, POLYGON_FORK_ID, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    function testSimpleCelerWithEstimates() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        celerHelper.helpWithEstimates(
            L1_CHAIN_ID, L1_CelerMessageBus, POLYGON_CelerMessageBus, L2_1_CHAIN_ID, POLYGON_FORK_ID, logs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    function testFancyCeler() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _aMoreFancyCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(anotherTarget));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        celerHelper.helpWithEstimates(
            L1_CHAIN_ID, L1_CelerMessageBus, POLYGON_CelerMessageBus, L2_1_CHAIN_ID, POLYGON_FORK_ID, logs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(anotherTarget.value(), 12);
        assertEq(anotherTarget.kevin(), msg.sender);
        assertEq(anotherTarget.bob(), keccak256("bob"));
    }

    function testCustomOrderingCeler() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();

        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));
        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory CelerLogs = celerHelper.findLogs(logs, 2);
        Vm.Log[] memory reorderedLogs = new Vm.Log[](2);

        reorderedLogs[0] = CelerLogs[1];
        reorderedLogs[1] = CelerLogs[0];

        celerHelper.help(
            L1_CHAIN_ID, L1_CelerMessageBus, POLYGON_CelerMessageBus, L2_1_CHAIN_ID, POLYGON_FORK_ID, reorderedLogs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    function testMultiDstCeler() external {
        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();

        _manyCrossChainFunctionInYourContract([L2_1_CHAIN_ID, L2_2_CHAIN_ID], [address(target), address(altTarget)]);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        celerHelper.help(L1_CHAIN_ID, L1_CelerMessageBus, allDstMessageBus, allDstChainIds, allDstForks, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.value(), CROSS_CHAIN_MESSAGE);
    }

    function _manyCrossChainFunctionInYourContract(uint64[2] memory dstChainIds, address[2] memory receivers)
        internal
    {
        IMessageBus bus = IMessageBus(L1_CelerMessageBus);

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            bus.sendMessage{value: 2 ether}(receivers[i], dstChainIds[i], abi.encode(CROSS_CHAIN_MESSAGE));
        }
    }

    function _someCrossChainFunctionInYourContract(uint64 dstChainId, address receiver) internal {
        IMessageBus bus = IMessageBus(L1_CelerMessageBus);
        bus.sendMessage{value: 2 ether}(receiver, dstChainId, abi.encode(CROSS_CHAIN_MESSAGE));
    }

    function _aMoreFancyCrossChainFunctionInYourContract(uint64 dstChainId, address receiver) internal {
        IMessageBus bus = IMessageBus(L1_CelerMessageBus);
        bus.sendMessage{value: 2 ether}(receiver, dstChainId, abi.encode(uint256(12), msg.sender, keccak256("bob")));
    }
}
