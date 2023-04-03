// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {LayerZeroHelper} from "src/layerzero/LayerZeroHelper.sol";

interface ILayerZeroEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;
}

contract Target {
    uint256 public value;

    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload)
        external
    {
        value = abi.decode(_payload, (uint256));
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

    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload)
        external
    {
        require(_srcChainId == expectedId, "Unexpected id");
        (value, kevin, bob) = abi.decode(_payload, (uint256, address, bytes32));
    }
}

contract LayerZeroHelperTest is Test {
    LayerZeroHelper lzHelper;
    Target target;
    AnotherTarget anotherTarget;

    uint256 L1_FORK_ID;
    uint256 L2_FORK_ID;
    uint16 constant L1_ID = 101;
    uint16 constant L2_ID = 109;
    address constant L1_lzEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
    address constant L2_lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 16400467);
        lzHelper = new LayerZeroHelper();

        L2_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 38063686);
        target = new Target();
        anotherTarget = new AnotherTarget(L1_ID);
    }

    function testSimpleLZ() external {
        vm.selectFork(L1_FORK_ID);

        // ||
        // ||
        // \/ This is the part of the code you could copy to use the LayerZeroHelper
        //    in your own tests.
        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(L2_lzEndpoint, 100000, L2_FORK_ID, logs);
        // /\
        // ||
        // ||

        vm.selectFork(L2_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testSimpleLZWithEstimates() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.helpWithEstimates(L2_lzEndpoint, 100000, L2_FORK_ID, logs);

        vm.selectFork(L2_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testFancyLZ() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _aMoreFancyCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(L2_lzEndpoint, 100000, L2_FORK_ID, logs);

        vm.selectFork(L2_FORK_ID);
        assertEq(anotherTarget.value(), 12);
        assertEq(anotherTarget.kevin(), msg.sender);
        assertEq(anotherTarget.bob(), keccak256("bob"));
    }

    function testCustomOrderingLZ() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        _someOtherCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory lzLogs = lzHelper.findLogs(logs, 2);
        Vm.Log[] memory reorderedLogs = new Vm.Log[](2);
        reorderedLogs[0] = lzLogs[1];
        reorderedLogs[1] = lzLogs[0];
        lzHelper.help(L2_lzEndpoint, 100000, L2_FORK_ID, reorderedLogs);

        vm.selectFork(L2_FORK_ID);
        assertEq(target.value(), 12);
    }

    function _someCrossChainFunctionInYourContract() internal {
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(L1_lzEndpoint);
        bytes memory remoteAndLocalAddresses = abi.encodePacked(address(target), address(this));
        endpoint.send{value: 1 ether}(
            L2_ID, remoteAndLocalAddresses, abi.encode(uint256(12)), payable(msg.sender), address(0), ""
        );
    }

    function _someOtherCrossChainFunctionInYourContract() internal {
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(L1_lzEndpoint);
        bytes memory remoteAndLocalAddresses = abi.encodePacked(address(target), address(this));
        endpoint.send{value: 1 ether}(
            L2_ID, remoteAndLocalAddresses, abi.encode(uint256(6)), payable(msg.sender), address(0), ""
        );
    }

    function _aMoreFancyCrossChainFunctionInYourContract() internal {
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(L1_lzEndpoint);
        bytes memory remoteAndLocalAddresses = abi.encodePacked(address(anotherTarget), address(this));
        endpoint.send{value: 1 ether}(
            L2_ID,
            remoteAndLocalAddresses,
            abi.encode(uint256(12), msg.sender, keccak256("bob")),
            payable(msg.sender),
            address(0),
            ""
        );
    }
}
