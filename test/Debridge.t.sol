// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "src/across/interfaces/IERC20.sol";
import "forge-std/Test.sol";

import {DebridgeHelper} from "src/debridge/DebridgeHelper.sol";
import {IDebridgeGate} from "src/debridge/interfaces/IDebridgeGate.sol";

contract DebridgeHelperTest is Test {
    DebridgeHelper debridgeHelper;

    address public target = address(this);

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    address constant L1_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ARBITRUM_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant POLYGON_USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    uint256 constant L1_ID = 1;
    uint256 constant ARBITRUM_ID = 42161;
    uint256 constant POLYGON_ID = 137;

    address constant L1_debridge = 0x43dE2d77BF8027e25dBD179B491e8d64f38398aA;
    address constant ARBITRUM_debridge = 0x43dE2d77BF8027e25dBD179B491e8d64f38398aA;
    address constant POLYGON_debridge = 0x43dE2d77BF8027e25dBD179B491e8d64f38398aA;

    address[] public allDstTargets;
    uint256[] public allDstChainIds;
    uint256[] public allDstForks;

    address constant L1_ADMIN = 0x6bec1faF33183e1Bc316984202eCc09d46AC92D5;
    address constant ARBITRUM_ADMIN = 0xA52842cD43fA8c4B6660E443194769531d45b265;
    address constant POLYGON_ADMIN = 0xA52842cD43fA8c4B6660E443194769531d45b265;

    address constant ARBITRUM_DEBRIDGE_TOKEN = 0x1dDcaa4Ed761428ae348BEfC6718BCb12e63bFaa;
    address constant POLYGON_DEBRIDGE_TOKEN = 0x1dDcaa4Ed761428ae348BEfC6718BCb12e63bFaa;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    // eth refund
    receive() external payable {}

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 21580621);
        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 293298223);
        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET);

        vm.selectFork(L1_FORK_ID);
        debridgeHelper = new DebridgeHelper();

        allDstTargets.push(target);
        allDstTargets.push(target);
        allDstChainIds.push(ARBITRUM_ID);
        allDstChainIds.push(POLYGON_ID);
        allDstForks.push(ARBITRUM_FORK_ID);
        allDstForks.push(POLYGON_FORK_ID);
    }

    function testSimpleDebridge() external {
        vm.selectFork(L1_FORK_ID);
        uint256 amount = 1e10;

        // ||
        // ||
        // \/ This is the part of the code you could copy to use the DebridgeHelper
        //    in your own tests.
        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L1_debridge, ARBITRUM_ID, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        debridgeHelper.help(ARBITRUM_ADMIN, L1_debridge, ARBITRUM_debridge, ARBITRUM_FORK_ID, ARBITRUM_ID, logs);
        // /\
        // ||
        // ||

        vm.selectFork(ARBITRUM_FORK_ID);
        assertApproxEqAbs(IERC20(ARBITRUM_DEBRIDGE_TOKEN).balanceOf(target), amount, amount * 1e4 / 1e5);
    }

    function _someCrossChainFunctionInYourContract(
        address sourceDebridgeGate,
        uint256 destinationChainId,
        uint256 amount
    ) internal {
        deal(L1_USDC, address(this), amount);
        IERC20(L1_USDC).approve(sourceDebridgeGate, amount);

        IDebridgeGate(sourceDebridgeGate).send{value: 1 ether}(
            L1_USDC,
            amount,
            destinationChainId,
            abi.encodePacked(target),
            "", //permit envelope
            false, // use asset fee
            0, // referral code
            "" // auto params
        );
    }

    function testMultiDstDebridge() external {
        vm.selectFork(L1_FORK_ID);
        uint256 amount = 1e10;

        vm.recordLogs();
        _manyCrossChainFunctionInYourContract(amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        address[] memory debridgeGateAdmins = new address[](2);
        debridgeGateAdmins[0] = ARBITRUM_ADMIN;
        debridgeGateAdmins[1] = POLYGON_ADMIN;

        address[] memory dstGates = new address[](2);
        dstGates[0] = ARBITRUM_debridge;
        dstGates[1] = POLYGON_debridge;

        debridgeHelper.help(L1_debridge, dstGates, allDstForks, allDstChainIds, debridgeGateAdmins, logs);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertApproxEqAbs(IERC20(ARBITRUM_DEBRIDGE_TOKEN).balanceOf(target), amount, amount * 1e4 / 1e5);
    }

    function _manyCrossChainFunctionInYourContract(uint256 amount) internal {
        uint256 count = allDstForks.length;

        deal(L1_USDC, address(this), amount * count);
        IERC20(L1_USDC).approve(L1_debridge, amount * count);

        IDebridgeGate(L1_debridge).send{value: 1 ether}(
            L1_USDC,
            amount,
            ARBITRUM_ID,
            abi.encodePacked(target),
            "", //permit envelope
            false, // use asset fee
            0, // referral code
            "" // auto params
        );

        IDebridgeGate(L1_debridge).send{value: 1 ether}(
            L1_USDC,
            amount,
            POLYGON_ID,
            abi.encodePacked(target),
            "", //permit envelope
            false, // use asset fee
            0, // referral code
            "" // auto params
        );
    }
}
