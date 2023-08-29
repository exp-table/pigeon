// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
import "src/wormhole/automatic-relayer/WormholeHelper.sol";

interface IWormholeRelayerSend {
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence);

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundAddress
    ) external payable returns (uint64 sequence);

    function quoteEVMDeliveryPrice(uint16 targetChain, uint256 receiverValue, uint256 gasLimit)
        external
        view
        returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);
}

interface IWormholeRelayer is IWormholeRelayerSend {}

contract Target is IWormholeReceiver {
    uint256 public value;

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        value = abi.decode(payload, (uint256));
    }
}

contract AnotherTarget {
    uint256 public value;
    address public kevin;
    bytes32 public bob;

    uint16 expectedChainId;

    constructor(uint16 _expectedChainId) {
        expectedChainId = _expectedChainId;
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        require(sourceChain == expectedChainId, "Unexpected origin");
        (value, kevin, bob) = abi.decode(payload, (uint256, address, bytes32));
    }
}

contract WormholeAutomaticRelayerHelperTest is Test {
    WormholeHelper wormholeHelper;
    Target target;
    Target altTarget;

    AnotherTarget anotherTarget;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint256 CROSS_CHAIN_MESSAGE = UINT256_MAX;

    uint16 constant L1_CHAIN_ID = 2;
    uint16 constant L2_1_CHAIN_ID = 5;
    uint16 constant L2_2_CHAIN_ID = 23;

    address constant L1_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address constant L2_1_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address constant L2_2_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;

    address[] public allDstRelayers;
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
        target = new Target();
        anotherTarget = new AnotherTarget(L1_CHAIN_ID);

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 38063686);
        altTarget = new Target();

        allDstChainIds.push(L2_1_CHAIN_ID);
        allDstChainIds.push(L2_2_CHAIN_ID);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstRelayers.push(L2_1_RELAYER);
        allDstRelayers.push(L2_2_RELAYER);

        allDstTargets.push(address(target));
        allDstTargets.push(address(altTarget));

        console.log(address(target));
        console.log(address(altTarget));
    }

    /// @dev is a normal cross-chain message
    function testSimpleWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_1_RELAYER, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev is a fancy cross-chain message
    function testFancyWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _aMoreFancyCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(anotherTarget));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_2_RELAYER, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(anotherTarget.value(), 12);
        assertEq(anotherTarget.kevin(), msg.sender);
        assertEq(anotherTarget.bob(), keccak256("bob"));
    }

    /// @dev test event log re-ordering
    function testCustomOrderingWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();

        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));
        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory WormholeLogs = wormholeHelper.findLogs(logs, 2);
        Vm.Log[] memory reorderedLogs = new Vm.Log[](2);

        reorderedLogs[0] = WormholeLogs[1];
        reorderedLogs[1] = WormholeLogs[0];

        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_1_RELAYER, reorderedLogs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev test multi-dst wormhole helper
    function testMultiDstWormhole() external {
        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();

        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));
        _someCrossChainFunctionInYourContract(L2_2_CHAIN_ID, address(altTarget));

        Vm.Log[] memory logs = vm.getRecordedLogs();

        wormholeHelper.help(L1_CHAIN_ID, allDstForks, allDstTargets, allDstRelayers, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.value(), CROSS_CHAIN_MESSAGE);
    }

    function _aMoreFancyCrossChainFunctionInYourContract(uint16 dstChainId, address receiver) internal {
        IWormholeRelayer relayer = IWormholeRelayer(L1_RELAYER);

        (uint256 msgValue,) = relayer.quoteEVMDeliveryPrice(dstChainId, 0, 500000);

        relayer.sendPayloadToEvm{value: msgValue}(
            dstChainId,
            receiver,
            abi.encode(uint256(12), msg.sender, keccak256("bob")),
            0,
            500000,
            L1_CHAIN_ID,
            address(this)
        );
    }

    function _someCrossChainFunctionInYourContract(uint16 dstChainId, address receiver) internal {
        IWormholeRelayer relayer = IWormholeRelayer(L1_RELAYER);

        (uint256 msgValue,) = relayer.quoteEVMDeliveryPrice(dstChainId, 0, 500000);

        relayer.sendPayloadToEvm{value: msgValue}(
            dstChainId, receiver, abi.encode(CROSS_CHAIN_MESSAGE), 0, 500000, L1_CHAIN_ID, address(this)
        );
    }
}
