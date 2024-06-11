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

    function lzReceive(
        uint16, /*_srcChainId*/
        bytes calldata, /*_srcAddress*/
        uint64, /*_nonce*/
        bytes calldata _payload
    ) external {
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

    function lzReceive(uint16 _srcChainId, bytes calldata, /*_srcAddress*/ uint64, /*_nonce*/ bytes calldata _payload)
        external
    {
        require(_srcChainId == expectedId, "Unexpected id");
        (value, kevin, bob) = abi.decode(_payload, (uint256, address, bytes32));
    }
}

contract LayerZeroHelperTest is Test {
    LayerZeroHelper lzHelper;
    Target target;
    Target altTarget;
    AnotherTarget anotherTarget;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint16 constant L1_ID = 101;
    uint16 constant POLYGON_ID = 109;
    uint16 constant ARBITRUM_ID = 110;

    address constant L1_lzEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
    address constant polygonEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
    address constant arbitrumEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;

    address[] public allDstTargets;
    address[] public allDstEndpoints;
    uint16[] public allDstChainIds;
    uint256[] public allDstForks;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 16400467);
        lzHelper = new LayerZeroHelper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 38063686);
        target = new Target();
        anotherTarget = new AnotherTarget(L1_ID);

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 38063686);
        altTarget = new Target();

        allDstTargets.push(address(target));
        allDstTargets.push(address(altTarget));

        allDstChainIds.push(POLYGON_ID);
        allDstChainIds.push(ARBITRUM_ID);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstEndpoints.push(polygonEndpoint);
        allDstEndpoints.push(arbitrumEndpoint);
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
        lzHelper.help(polygonEndpoint, 100000, POLYGON_FORK_ID, logs);
        // /\
        // ||
        // ||

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testSimpleLZWithEstimates() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.helpWithEstimates(polygonEndpoint, 100000, POLYGON_FORK_ID, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testFancyLZ() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _aMoreFancyCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(polygonEndpoint, 100000, POLYGON_FORK_ID, logs);

        vm.selectFork(POLYGON_FORK_ID);
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
        lzHelper.help(polygonEndpoint, 100000, POLYGON_FORK_ID, reorderedLogs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 12);
    }

    function testMultiDstLZ() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _manyCrossChainFunctionInYourContract();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(allDstEndpoints, allDstChainIds, 100000, allDstForks, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), 12);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.value(), 21);
    }

    function _manyCrossChainFunctionInYourContract() internal {
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(L1_lzEndpoint);

        bytes memory remoteAndLocalAddresses_1 = abi.encodePacked(address(target), address(this));
        bytes memory remoteAndLocalAddresses_2 = abi.encodePacked(address(altTarget), address(this));

        endpoint.send{value: 1 ether}(
            POLYGON_ID, remoteAndLocalAddresses_1, abi.encode(uint256(12)), payable(msg.sender), address(0), ""
        );

        endpoint.send{value: 1 ether}(
            ARBITRUM_ID, remoteAndLocalAddresses_2, abi.encode(uint256(21)), payable(msg.sender), address(0), ""
        );
    }

    function _someCrossChainFunctionInYourContract() internal {
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(L1_lzEndpoint);
        bytes memory remoteAndLocalAddresses = abi.encodePacked(address(target), address(this));
        endpoint.send{value: 1 ether}(
            POLYGON_ID, remoteAndLocalAddresses, abi.encode(uint256(12)), payable(msg.sender), address(0), ""
        );
    }

    function _someOtherCrossChainFunctionInYourContract() internal {
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(L1_lzEndpoint);
        bytes memory remoteAndLocalAddresses = abi.encodePacked(address(target), address(this));
        endpoint.send{value: 1 ether}(
            POLYGON_ID, remoteAndLocalAddresses, abi.encode(uint256(6)), payable(msg.sender), address(0), ""
        );
    }

    function _aMoreFancyCrossChainFunctionInYourContract() internal {
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(L1_lzEndpoint);
        bytes memory remoteAndLocalAddresses = abi.encodePacked(address(anotherTarget), address(this));
        endpoint.send{value: 1 ether}(
            POLYGON_ID,
            remoteAndLocalAddresses,
            abi.encode(uint256(12), msg.sender, keccak256("bob")),
            payable(msg.sender),
            address(0),
            ""
        );
    }
}
