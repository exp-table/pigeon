// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {LayerZeroHelper} from "src/layerzero/LayerZeroHelper.sol";

interface IStargateRouter {
    struct lzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }

    function swap(
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        address payable _refundAddress,
        uint256 _amountLD,
        uint256 _minAmountLD,
        lzTxObj memory _lzTxParams,
        bytes calldata _to,
        bytes calldata _payload
    ) external payable;
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract Target {
    uint256 public value;

    function sgReceive(
        uint16,
        /// _srcChainId
        bytes memory,
        /// _srcAddress
        uint256,
        /// _nonce
        address,
        /// _token
        uint256,
        /// amountLD
        bytes memory payload
    ) external {
        value = abi.decode(payload, (uint256));
    }
}

contract AnotherTarget {
    uint256 public value;
    address public kevin;
    bytes32 public bob;

    uint16 expectedId;

    constructor(uint16 _expectedId) {
        expectedId = _expectedId;
    }

    function sgReceive(
        uint16 _srcChainId,
        bytes memory,
        /// _srcAddress
        uint256,
        /// _nonce
        address,
        /// _token
        uint256,
        /// _amount
        bytes memory payload
    ) external {
        require(_srcChainId == expectedId, "Unexpected id");
        (value, kevin, bob) = abi.decode(payload, (uint256, address, bytes32));
    }
}

contract StargateHelperTest is Test {
    LayerZeroHelper lzHelper;
    Target target;
    AnotherTarget anotherTarget;

    uint256 L1_FORK_ID;
    uint256 L2_FORK_ID;
    uint16 constant L1_ID = 101;
    uint16 constant L2_ID = 109;
    address constant L1_sgRouter = 0x8731d54E9D02c286767d56ac03e8037C07e01e98;
    address constant L2_lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;

    IERC20 L1token = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 L2token = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 16400467);
        lzHelper = new LayerZeroHelper();

        vm.broadcast(0x28C6c06298d514Db089934071355E5743bf21d60); // big boi USDC holder
        L1token.transfer(address(this), 10 ** 9);

        L2_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 38063686);
        target = new Target();
        anotherTarget = new AnotherTarget(L1_ID);
    }

    function testSimpleSG() external {
        vm.selectFork(L1_FORK_ID);

        // ||
        // ||
        // \/ This is the part of the code you could copy to use the LayerZeroHelper
        //    in your own tests.
        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(L2_lzEndpoint, 500000, L2_FORK_ID, logs);
        // /\
        // ||
        // ||

        vm.selectFork(L2_FORK_ID);
        assertEq(target.value(), 12);
        // tolerated margin of $2
        assertApproxEqAbs(L2token.balanceOf(address(target)), 10 ** 9, 2 * 10 ** 6);
    }

    function testSimpleSGWithEstimates() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.helpWithEstimates(L2_lzEndpoint, 500000, L2_FORK_ID, logs);

        vm.selectFork(L2_FORK_ID);
        assertEq(target.value(), 12);
        // tolerated margin of $2
        assertApproxEqAbs(L2token.balanceOf(address(target)), 10 ** 9, 2 * 10 ** 6);
    }

    function testFancySG() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _aMoreFancyCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(L2_lzEndpoint, 500000, L2_FORK_ID, logs);

        vm.selectFork(L2_FORK_ID);
        assertEq(anotherTarget.value(), 12);
        assertEq(anotherTarget.kevin(), msg.sender);
        assertEq(anotherTarget.bob(), keccak256("bob"));
        assertApproxEqAbs(L2token.balanceOf(address(anotherTarget)), 10 ** 9, 2 * 10 ** 6);
    }

    function testCustomOrderingSG() external {
        vm.selectFork(L1_FORK_ID);

        // Deal more USDC
        vm.broadcast(0x28C6c06298d514Db089934071355E5743bf21d60);
        L1token.transfer(address(this), 10 ** 9);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        _someOtherCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory lzLogs = lzHelper.findLogs(logs, 2);
        Vm.Log[] memory reorderedLogs = new Vm.Log[](2);
        reorderedLogs[0] = lzLogs[1];
        reorderedLogs[1] = lzLogs[0];
        lzHelper.help(L2_lzEndpoint, 500000, L2_FORK_ID, reorderedLogs);

        vm.selectFork(L2_FORK_ID);
        assertEq(target.value(), 12);
        assertApproxEqAbs(L2token.balanceOf(address(target)), 2 * 10 ** 9, 2 * 10 ** 6);
    }

    function _someCrossChainFunctionInYourContract() internal {
        L1token.approve(L1_sgRouter, 10 ** 9);
        IStargateRouter(L1_sgRouter).swap{value: 1 ether}(
            L2_ID,
            1,
            1,
            payable(msg.sender),
            10 ** 9,
            0,
            IStargateRouter.lzTxObj(500000, 0, "0x"),
            abi.encodePacked(address(target)),
            abi.encode(uint256(12))
        );
    }

    function _someOtherCrossChainFunctionInYourContract() internal {
        L1token.approve(L1_sgRouter, 10 ** 9);
        IStargateRouter(L1_sgRouter).swap{value: 1 ether}(
            L2_ID,
            1,
            1,
            payable(msg.sender),
            10 ** 9,
            0,
            IStargateRouter.lzTxObj(500000, 0, "0x"),
            abi.encodePacked(address(target)),
            abi.encode(uint256(6))
        );
    }

    function _aMoreFancyCrossChainFunctionInYourContract() internal {
        L1token.approve(L1_sgRouter, 10 ** 9);
        IStargateRouter(L1_sgRouter).swap{value: 1 ether}(
            L2_ID,
            1,
            1,
            payable(msg.sender),
            10 ** 9,
            0,
            IStargateRouter.lzTxObj(500000, 0, "0x"),
            abi.encodePacked(address(anotherTarget)),
            abi.encode(uint256(12), msg.sender, keccak256("bob"))
        );
    }
}
