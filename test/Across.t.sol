// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {AcrossV3Helper} from "src/across/AcrossV3Helper.sol";
import {IAcrossSpokePoolV3} from "src/across/interfaces/IAcrossSpokePoolV3.sol";
import {IAcrossV3Interpreter} from "src/across/interfaces/IAcrossV3Interpreter.sol";
import {IERC20} from "src/across/interfaces/IERC20.sol";
import {console} from "forge-std/console.sol";

contract Target {
    uint256 public amount;
    address acrossSpokePool;

    error INVALID_SENDER();

    constructor(address _acrossSpokePool) {
        acrossSpokePool = _acrossSpokePool;
    }

    function handleV3AcrossMessage(
        address,
        uint256, //amount
        address, //relayer; not used
        bytes memory message
    ) external {
        if (msg.sender != acrossSpokePool) revert INVALID_SENDER();

        // decode instruction
        uint256 amountDecoded = abi.decode(message, (uint256));
        amount = amountDecoded;
    }
}

contract AcrossV3HelperTest is Test {
    AcrossV3Helper acrossV3Helper;
    Target target;
    Target altTarget;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint256 constant L1_ID = 1;
    uint256 constant POLYGON_ID = 137;
    uint256 constant ARBITRUM_ID = 42161;

    address constant L1_spokePool = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
    address constant POLYGON_spokePool = 0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096;
    address constant ARBITRUM_spokePool = 0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A;
    address constant RELAYER = address(0x7777);
    address[] public allDstTargets;
    address[] public allDstSpokePools;
    uint256[] public allDstChainIds;
    uint256[] public allDstForks;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 21580621);
        acrossV3Helper = new AcrossV3Helper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 66450382);
        target = new Target(POLYGON_spokePool);

        console.log("BASE_TARGET", address(target));

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 293298223);
        altTarget = new Target(ARBITRUM_spokePool);

        allDstTargets.push(address(target));

        allDstChainIds.push(POLYGON_ID);
        allDstChainIds.push(ARBITRUM_ID);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstSpokePools.push(POLYGON_spokePool);
        allDstSpokePools.push(ARBITRUM_spokePool);
    }

    function testSimpleAcross() external {
        vm.selectFork(L1_FORK_ID);

        // ||
        // ||
        // \/ This is the part of the code you could copy to use the AcrossV3Helper
        //    in your own tests.
        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L1_spokePool, POLYGON_ID);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        acrossV3Helper.help(L1_spokePool, POLYGON_spokePool, RELAYER, POLYGON_FORK_ID, POLYGON_ID, L1_ID, logs);
        // /\
        // ||
        // ||

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.amount(), 12);
    }

    function _someCrossChainFunctionInYourContract(address sourceSpokePool, uint256 destinationChainId) internal {
        deal(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, address(this), 12);
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(sourceSpokePool, 12);
        // Call depositV3 on the SpokePool
        IAcrossSpokePoolV3(sourceSpokePool).depositV3(
            address(this), // depositor
            address(target),
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359,
            12,
            12,
            destinationChainId, // destinationChainId
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp) + 10 minutes,
            0,
            abi.encode(uint256(12)) // message
        );
    }

    function testMultiDstAcross() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _manyCrossChainFunctionInYourContract();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256[] memory refundChainIds = new uint256[](2);
        refundChainIds[0] = L1_ID;
        refundChainIds[1] = L1_ID;

        acrossV3Helper.help(L1_spokePool, allDstSpokePools, RELAYER, allDstForks, allDstChainIds, refundChainIds, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.amount(), 12);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.amount(), 21);
    }

    function _manyCrossChainFunctionInYourContract() internal {
        deal(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, address(this), 33); // 12 + 21
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48).approve(L1_spokePool, 33);

        // First deposit for POLYGON
        IAcrossSpokePoolV3(L1_spokePool).depositV3(
            address(this),
            address(target),
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359, // USDC
            12,
            12,
            POLYGON_ID,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp) + 10 minutes,
            0,
            abi.encode(uint256(12))
        );

        // Second deposit for Arbitrum
        IAcrossSpokePoolV3(L1_spokePool).depositV3(
            address(this),
            address(altTarget),
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831, // USDC
            21,
            21,
            ARBITRUM_ID,
            address(0),
            uint32(block.timestamp),
            uint32(block.timestamp) + 10 minutes,
            0,
            abi.encode(uint256(21))
        );
    }
}
