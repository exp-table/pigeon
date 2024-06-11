// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {LayerZeroV2Helper} from "src/layerzero-v2/LayerZeroV2Helper.sol";

struct MessagingParams {
    uint32 dstEid;
    bytes32 receiver;
    bytes message;
    bytes options;
    bool payInLzToken;
}

struct MessagingReceipt {
    bytes32 guid;
    uint64 nonce;
    MessagingFee fee;
}

struct MessagingFee {
    uint256 nativeFee;
    uint256 lzTokenFee;
}

struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

interface ILayerZeroV2Endpoint {
    function send(MessagingParams calldata _params, address _refundAddress)
        external
        payable
        returns (MessagingReceipt memory);

    function quote(MessagingParams calldata _params, address _sender) external view returns (MessagingFee memory);
}

contract Target {
    uint256 public value;

    function lzReceive(
        Origin calldata, /*_origin*/
        bytes32, /*_guid*/
        bytes calldata _message,
        address, /*_executor*/
        bytes calldata /*_extraData*/
    ) external payable {
        value = abi.decode(_message, (uint256));
    }
}

contract LayerZeroV2HelperTest is Test {
    LayerZeroV2Helper lzHelper;
    Target target;
    Target altTarget;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint32 constant L1_ID = 30101;
    uint32 constant POLYGON_ID = 30109;
    uint16 constant ARBITRUM_ID = 30110;

    address constant lzV2Endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    address[] public allDstEndpoints;
    uint32[] public allDstChainIds;
    uint256[] public allDstForks;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 19_730_754);
        lzHelper = new LayerZeroV2Helper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 56_652_576);
        target = new Target();

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 38063686);
        altTarget = new Target();

        allDstChainIds.push(POLYGON_ID);
        allDstChainIds.push(ARBITRUM_ID);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstEndpoints.push(lzV2Endpoint);
        allDstEndpoints.push(lzV2Endpoint);
    }

    function testSingleDestination() external {
        console.log(address(this));
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(lzV2Endpoint, POLYGON_FORK_ID, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 420);
    }

    function testMultipleDestinations() external {
        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        _anotherCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(allDstEndpoints, allDstChainIds, allDstForks, logs);
        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 420);
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.value(), 69);
    }

    function testCustomEventSelector() external {
        bytes32 customSelector = 0x1ab700d4ced0c005b164c0f789fd09fcbb0156d4c2041b8a3bfbcd961cd1567f;

        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(lzV2Endpoint, POLYGON_FORK_ID, customSelector, logs);
        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 420);
    }

    function testMultipleDestinationsCustomEventSelector() external {
        bytes32 customSelector = 0x1ab700d4ced0c005b164c0f789fd09fcbb0156d4c2041b8a3bfbcd961cd1567f;

        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        _anotherCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(allDstEndpoints, allDstChainIds, allDstForks, customSelector, logs);
        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 420);
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.value(), 69);
    }

    function _someCrossChainFunctionInYourContract() internal {
        MessagingParams memory params = MessagingParams(
            POLYGON_ID,
            bytes32(uint256(uint160(address(target)))),
            abi.encode(420),
            abi.encodePacked(uint16(1), uint256(200_000)),
            false
        );

        uint256 fees = ILayerZeroV2Endpoint(lzV2Endpoint).quote(params, address(this)).nativeFee;
        ILayerZeroV2Endpoint(lzV2Endpoint).send{value: fees}(params, address(this));
    }

    function _anotherCrossChainFunctionInYourContract() internal {
        MessagingParams memory params = MessagingParams(
            ARBITRUM_ID,
            bytes32(uint256(uint160(address(altTarget)))),
            abi.encode(69),
            abi.encodePacked(uint16(1), uint256(200_000)),
            false
        );
        uint256 fees = ILayerZeroV2Endpoint(lzV2Endpoint).quote(params, address(this)).nativeFee;
        ILayerZeroV2Endpoint(lzV2Endpoint).send{value: fees}(params, address(this));
    }
}
