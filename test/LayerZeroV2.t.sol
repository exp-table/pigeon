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
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        value = abi.decode(_message, (uint256));
    }
}

contract LayerZeroV2HelperTest is Test {
    LayerZeroV2Helper lzHelper;
    Target target;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;

    uint32 constant L1_ID = 30101;
    uint32 constant POLYGON_ID = 30109;

    address constant lzV2Endpoint = 0x1a44076050125825900e736c501f859c50fE728c;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 19_730_754);
        lzHelper = new LayerZeroV2Helper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 56_652_576);
        target = new Target();
    }

    function testSimpleLzV2() external {
        console.log(address(this));
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(lzV2Endpoint, POLYGON_FORK_ID, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 420);
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
}
