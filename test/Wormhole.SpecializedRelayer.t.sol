// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
import "src/wormhole/specialized-relayer/lib/IWormhole.sol";
import "src/wormhole/specialized-relayer/WormholeHelper.sol";

contract Target {
    uint256 public value;
    IWormhole public wormhole;

    event ValueAdded(uint256 value);

    constructor(IWormhole _wormhole) {
        wormhole = _wormhole;
    }

    function receiveMessage(bytes memory encodedMessage) public {
        // call the Wormhole core contract to parse and verify the encodedMessage
        (IWormhole.VM memory wormholeMessage, bool valid,) = wormhole.parseAndVerifyVM(encodedMessage);
        // do security checks and set value
        require(valid);
        value = abi.decode(wormholeMessage.payload, (uint256));

        emit ValueAdded(value);
    }
}

contract AnotherTarget {
    uint256 public value;
    IWormhole public wormhole;
    address expEmitter;

    constructor(IWormhole _wormhole, address _expEmitter) {
        wormhole = _wormhole;
        expEmitter = _expEmitter;
    }

    function receiveMessage(bytes memory encodedMessage) public {
        // call the Wormhole core contract to parse and verify the encodedMessage
        (IWormhole.VM memory wormholeMessage, bool valid,) = wormhole.parseAndVerifyVM(encodedMessage);
        // do security checks and set value
        require(valid);
        require(wormholeMessage.emitterChainId == 2);
        require(TypeCasts.bytes32ToAddress(wormholeMessage.emitterAddress) == expEmitter);

        value = abi.decode(wormholeMessage.payload, (uint256));
    }
}

contract WormholeSpecializedRelayerHelperTest is Test {
    WormholeHelper wormholeHelper;
    Target target;
    Target altTarget;

    AnotherTarget anotherTarget;

    uint32 nonce;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint256 CROSS_CHAIN_MESSAGE = UINT256_MAX;

    uint16 L1_CHAIN_ID = 2;
    uint16 L2_1_CHAIN_ID = 5;
    uint16 constant L2_2_CHAIN_ID = 23;

    address constant L1_CORE = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;
    address constant L2_1_CORE = 0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7;
    address constant L2_2_CORE = 0xa5f208e072434bC67592E4C49C1B991BA79BCA46;

    address[] public allDstCore;
    uint16[] public allDstChainIds;
    uint256[] public allDstForks;
    address[] public allDstTargets;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    receive() external payable {}

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET);
        wormholeHelper = new WormholeHelper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET);
        target = new Target(IWormhole(L2_1_CORE));
        anotherTarget = new AnotherTarget(IWormhole(L2_1_CORE), address(this));

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET);
        altTarget = new Target(IWormhole(L2_2_CORE));

        allDstChainIds.push(L2_1_CHAIN_ID);
        allDstChainIds.push(L2_2_CHAIN_ID);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstCore.push(L2_1_CORE);
        allDstCore.push(L2_2_CORE);

        allDstTargets.push(address(target));
        allDstTargets.push(address(altTarget));
    }

    /// @dev is a simple cross-chain message
    function testSimpleWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();

        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_1_CORE, address(target), vm.getRecordedLogs());

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev is a fancy cross-chain message with more validatins on target
    function testFancyWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_1_CORE, address(anotherTarget), vm.getRecordedLogs());

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(anotherTarget.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev test event log re-ordering
    function testCustomOrderingWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();

        _someCrossChainFunctionInYourContract(abi.encode(type(uint32).max));
        _someCrossChainFunctionInYourContract();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory WormholeLogs = wormholeHelper.findLogs(logs, 2);
        Vm.Log[] memory reorderedLogs = new Vm.Log[](2);

        reorderedLogs[0] = WormholeLogs[1];
        reorderedLogs[1] = WormholeLogs[0];

        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_1_CORE, address(target), reorderedLogs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), type(uint32).max);
    }

    /// @dev test multi-dst wormhole helper
    function testMultiDstWormhole() external {
        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();

        _someCrossChainFunctionInYourContract();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        wormholeHelper.help(L1_CHAIN_ID, allDstForks, allDstCore, allDstTargets, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev is a simple cross-chain message to be published by wormhole
    function _someCrossChainFunctionInYourContract() internal {
        IWormhole wormhole = IWormhole(L1_CORE);

        /// @dev publish a new message
        ++nonce;

        /// @dev by sending `0` in the last argument, we get instant finality
        /// @notice should use your optimal finality in development
        wormhole.publishMessage{value: wormhole.messageFee()}(nonce, abi.encode(CROSS_CHAIN_MESSAGE), 0);
    }

    /// @dev is a simple cross-chain message to be published by wormhole
    function _someCrossChainFunctionInYourContract(bytes memory message) internal {
        IWormhole wormhole = IWormhole(L1_CORE);

        /// @dev publish a new message
        ++nonce;

        /// @dev by sending `0` in the last argument, we get instant finality
        /// @notice should use your optimal finality in development
        wormhole.publishMessage{value: wormhole.messageFee()}(nonce, message, 0);
    }
}
