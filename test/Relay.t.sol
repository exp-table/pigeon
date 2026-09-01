// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {RelayHelper} from "src/relay/RelayHelper.sol";
import {IERC20} from "src/relay/interfaces/IERC20.sol";

/// @dev minimal RelayDepository stand-in: RelayHelper only matches the deposit events by
///      emitter + topic, so a mock emitting the canonical event signatures is sufficient
contract MockRelayDepository {
    event RelayErc20Deposit(address from, address token, uint256 amount, bytes32 id);
    event RelayNativeDeposit(address from, uint256 amount, bytes32 id);

    function depositErc20(address token, uint256 amount, bytes32 id) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        emit RelayErc20Deposit(msg.sender, token, amount, id);
    }

    function depositNative(bytes32 id) external payable {
        emit RelayNativeDeposit(msg.sender, msg.value, id);
    }
}

/// @dev destination target standing in for SuperDestinationExecutor.processBridgedExecution
contract Target {
    uint256 public value;
    address public caller;

    error BOOM();

    function processBridgedExecution(uint256 _value) external payable {
        value = _value;
        caller = msg.sender;
    }

    function alwaysReverts() external pure {
        revert BOOM();
    }
}

/// @dev destination adapter standing in for RelayAdapter.processRelayExecution
contract MockAdapter {
    address public token;
    uint256 public value;
    uint256 public fundsAtExecution;

    constructor(address _token) {
        token = _token;
    }

    function processRelayExecution(uint256 _value) external payable {
        value = _value;
        fundsAtExecution = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }
}

contract RelayHelperTest is Test {
    RelayHelper relayHelper;
    MockRelayDepository depository;
    Target target;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;

    address constant L1_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant POLYGON_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    address constant SOLVER = address(0x501e4);
    address constant ACCOUNT = address(0xCAFE);
    bytes32 constant DEPOSIT_ID = keccak256("relay-order-1");

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 21580621);
        relayHelper = new RelayHelper();
        depository = new MockRelayDepository();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 66450382);
        target = new Target();

        vm.selectFork(L1_FORK_ID);
    }

    //////////////////////////////////////////////////////////////
    //                      DIRECT PATH                         //
    //////////////////////////////////////////////////////////////

    function testRelayErc20Direct() external {
        vm.recordLogs();
        _depositErc20(100e6, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        relayHelper.helpRelayDirect(
            address(depository),
            DEPOSIT_ID,
            SOLVER,
            POLYGON_USDC,
            99e6, // output < input models the solver fee
            POLYGON_FORK_ID,
            ACCOUNT,
            address(target),
            abi.encodeCall(Target.processBridgedExecution, (42)),
            logs
        );

        // helper must restore the source fork
        assertEq(vm.activeFork(), L1_FORK_ID);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(IERC20(POLYGON_USDC).balanceOf(ACCOUNT), 99e6);
        assertEq(target.value(), 42);
        assertEq(target.caller(), SOLVER);
    }

    function testRelayNativeDirect() external {
        vm.recordLogs();
        _depositNative(1 ether, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        vm.selectFork(POLYGON_FORK_ID);
        uint256 accountBalanceBefore = ACCOUNT.balance;
        vm.selectFork(L1_FORK_ID);

        relayHelper.helpRelayDirect(
            address(depository),
            DEPOSIT_ID,
            SOLVER,
            address(0),
            0.99 ether,
            POLYGON_FORK_ID,
            ACCOUNT,
            address(target),
            abi.encodeCall(Target.processBridgedExecution, (7)),
            logs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(ACCOUNT.balance - accountBalanceBefore, 0.99 ether);
        assertEq(target.value(), 7);
        assertEq(target.caller(), SOLVER);
    }

    //////////////////////////////////////////////////////////////
    //                      ADAPTER PATH                        //
    //////////////////////////////////////////////////////////////

    function testRelayViaAdapterErc20() external {
        vm.selectFork(POLYGON_FORK_ID);
        MockAdapter adapter = new MockAdapter(POLYGON_USDC);
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _depositErc20(100e6, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        relayHelper.helpRelayViaAdapter(
            address(depository),
            DEPOSIT_ID,
            SOLVER,
            POLYGON_USDC,
            99e6,
            POLYGON_FORK_ID,
            address(adapter),
            abi.encodeCall(MockAdapter.processRelayExecution, (42)),
            logs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(adapter.value(), 42);
        // tokens must arrive BEFORE the adapter entrypoint runs
        assertEq(adapter.fundsAtExecution(), 99e6);
        assertEq(IERC20(POLYGON_USDC).balanceOf(address(adapter)), 99e6);
    }

    function testRelayViaAdapterNative() external {
        vm.selectFork(POLYGON_FORK_ID);
        MockAdapter adapter = new MockAdapter(address(0));
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _depositNative(1 ether, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        relayHelper.helpRelayViaAdapter(
            address(depository),
            DEPOSIT_ID,
            SOLVER,
            address(0),
            0.99 ether,
            POLYGON_FORK_ID,
            address(adapter),
            abi.encodeCall(MockAdapter.processRelayExecution, (7)),
            logs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(adapter.value(), 7);
        // for native, value rides on the adapter call itself
        assertEq(adapter.fundsAtExecution(), 0.99 ether);
        assertEq(address(adapter).balance, 0.99 ether);
    }

    //////////////////////////////////////////////////////////////
    //                      RAW help()                          //
    //////////////////////////////////////////////////////////////

    function testRelayCustomTxs() external {
        vm.recordLogs();
        _depositErc20(100e6, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        RelayHelper.Call[] memory txs = new RelayHelper.Call[](3);
        txs[0] = RelayHelper.Call({
            to: POLYGON_USDC,
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, ACCOUNT, 60e6)
        });
        txs[1] = RelayHelper.Call({
            to: POLYGON_USDC,
            value: 0,
            data: abi.encodeWithSelector(IERC20.transfer.selector, address(target), 39e6)
        });
        txs[2] = RelayHelper.Call({to: address(target), value: 0, data: abi.encodeCall(Target.processBridgedExecution, (99))});

        relayHelper.help(address(depository), DEPOSIT_ID, SOLVER, POLYGON_USDC, 99e6, POLYGON_FORK_ID, txs, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(IERC20(POLYGON_USDC).balanceOf(ACCOUNT), 60e6);
        assertEq(IERC20(POLYGON_USDC).balanceOf(address(target)), 39e6);
        assertEq(target.value(), 99);
    }

    function testRelayMatchesAnyDepositId() external {
        vm.recordLogs();
        _depositErc20(100e6, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        relayHelper.helpRelayDirect(
            address(depository),
            bytes32(0), // wildcard
            SOLVER,
            POLYGON_USDC,
            99e6,
            POLYGON_FORK_ID,
            ACCOUNT,
            address(target),
            abi.encodeCall(Target.processBridgedExecution, (42)),
            logs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 42);
    }

    //////////////////////////////////////////////////////////////
    //                      FAILURE MODES                       //
    //////////////////////////////////////////////////////////////

    function testRelayRevertsOnDepositIdMismatch() external {
        vm.recordLogs();
        _depositErc20(100e6, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        vm.expectRevert("RelayHelper: no matching Relay deposit event");
        relayHelper.helpRelayDirect(
            address(depository),
            keccak256("some-other-order"),
            SOLVER,
            POLYGON_USDC,
            99e6,
            POLYGON_FORK_ID,
            ACCOUNT,
            address(target),
            abi.encodeCall(Target.processBridgedExecution, (42)),
            logs
        );
    }

    function testRelayRevertsOnWrongEmitter() external {
        MockRelayDepository otherDepository = new MockRelayDepository();

        vm.recordLogs();
        _depositErc20(100e6, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        vm.expectRevert("RelayHelper: no matching Relay deposit event");
        relayHelper.helpRelayDirect(
            address(otherDepository),
            DEPOSIT_ID,
            SOLVER,
            POLYGON_USDC,
            99e6,
            POLYGON_FORK_ID,
            ACCOUNT,
            address(target),
            abi.encodeCall(Target.processBridgedExecution, (42)),
            logs
        );
    }

    function testRelayRevertsOnEmptyLogs() external {
        Vm.Log[] memory logs = new Vm.Log[](0);

        vm.expectRevert("RelayHelper: no matching Relay deposit event");
        relayHelper.helpRelayDirect(
            address(depository),
            DEPOSIT_ID,
            SOLVER,
            POLYGON_USDC,
            99e6,
            POLYGON_FORK_ID,
            ACCOUNT,
            address(target),
            abi.encodeCall(Target.processBridgedExecution, (42)),
            logs
        );
    }

    function testRelayAtomicBatchBubblesInnerRevert() external {
        vm.recordLogs();
        _depositErc20(100e6, DEPOSIT_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        vm.expectRevert(Target.BOOM.selector);
        relayHelper.helpRelayDirect(
            address(depository),
            DEPOSIT_ID,
            SOLVER,
            POLYGON_USDC,
            99e6,
            POLYGON_FORK_ID,
            ACCOUNT,
            address(target),
            abi.encodeCall(Target.alwaysReverts, ()),
            logs
        );
    }

    //////////////////////////////////////////////////////////////
    //                        HELPERS                           //
    //////////////////////////////////////////////////////////////

    function _depositErc20(uint256 amount, bytes32 id) internal {
        deal(L1_USDC, address(this), amount);
        IERC20(L1_USDC).approve(address(depository), amount);
        depository.depositErc20(L1_USDC, amount, id);
    }

    function _depositNative(uint256 amount, bytes32 id) internal {
        vm.deal(address(this), amount);
        depository.depositNative{value: amount}(id);
    }
}
