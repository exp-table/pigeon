// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "src/wormhole/WormholeHelper.sol";

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

    function quoteEVMDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    )
        external
        view
        returns (
            uint256 nativePriceQuote,
            uint256 targetChainRefundPerGasUnused
        );
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

contract WormholeHelperTest is Test {
    WormholeHelper wormholeHelper;
    Target target;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;

    uint256 CROSS_CHAIN_MESSAGE = UINT256_MAX;

    uint16 L1_CHAIN_ID = 2;
    uint16 L2_1_CHAIN_ID = 5;

    address constant L1_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address constant L2_1_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    receive() external payable {}

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET);
        wormholeHelper = new WormholeHelper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET);
        target = new Target();
    }

    function testSimpleWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        wormholeHelper.help(
            L2_1_CHAIN_ID,
            POLYGON_FORK_ID,
            address(target),
            L2_1_RELAYER,
            logs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    function _someCrossChainFunctionInYourContract() internal {
        IWormholeRelayer relayer = IWormholeRelayer(L1_RELAYER);

        (uint256 msgValue, ) = relayer.quoteEVMDeliveryPrice(
            L2_1_CHAIN_ID,
            0,
            500000
        );

        relayer.sendPayloadToEvm{value: msgValue}(
            L2_1_CHAIN_ID,
            address(target),
            abi.encode(CROSS_CHAIN_MESSAGE),
            0,
            500000,
            L1_CHAIN_ID,
            address(this)
        );
    }
}
