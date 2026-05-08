// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import {CctpV2Helper} from "src/cctp/CctpV2Helper.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface ITokenMessengerV2 {
    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes memory hookData
    ) external;
}

contract CctpV2HelperTest is Test {
    CctpV2Helper cctpHelper;

    uint256 ETH_FORK_ID;
    uint256 ARB_FORK_ID;

    /// @dev CCTP domain IDs (NOT EVM chain IDs)
    uint32 constant DOMAIN_ETH = 0;
    uint32 constant DOMAIN_ARBITRUM = 3;

    /// @dev CCTP V2 contracts (same address on all chains via CREATE2)
    address constant TOKEN_MESSENGER_V2 = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;

    /// @dev USDC addresses
    address constant USDC_ETH = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_ARB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    /// @dev USDC balances mapping storage slot (FiatTokenV2)
    uint256 constant USDC_BALANCE_SLOT = 9;

    /// @dev test account
    address constant ALICE = address(0xA11CE);

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        ETH_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 25_035_000);
        cctpHelper = new CctpV2Helper(0);

        ARB_FORK_ID = vm.createFork(RPC_ARBITRUM_MAINNET, 459_930_000);
    }

    /// @dev sets USDC balance directly via vm.store (avoids deal breaking USDC proxy)
    function _dealUsdc(address token, address to, uint256 amount) internal {
        bytes32 slot = keccak256(abi.encode(to, USDC_BALANCE_SLOT));
        vm.store(token, slot, bytes32(amount));
    }

    /// @notice end-to-end: burn USDC on ETH, relay via helper, verify mint on Arbitrum
    function testSimpleCctpV2() external {
        uint256 amount = 1000e6; // 1000 USDC

        /// source chain: burn USDC on ETH
        vm.selectFork(ETH_FORK_ID);
        _dealUsdc(USDC_ETH, ALICE, amount);

        vm.startPrank(ALICE);
        IERC20(USDC_ETH).approve(TOKEN_MESSENGER_V2, amount);

        vm.recordLogs();

        ITokenMessengerV2(TOKEN_MESSENGER_V2).depositForBurnWithHook(
            amount,
            DOMAIN_ARBITRUM,
            bytes32(uint256(uint160(ALICE))), // mintRecipient
            USDC_ETH,
            bytes32(0), // destinationCaller: anyone can relay
            0, // maxFee
            2000, // minFinalityThreshold: standard finality
            abi.encode(uint256(1)) // hookData: non-empty required
        );
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        /// record destination balance before relay
        vm.selectFork(ARB_FORK_ID);
        uint256 balanceBefore = IERC20(USDC_ARB).balanceOf(ALICE);
        vm.selectFork(ETH_FORK_ID);

        /// relay the CCTP message to destination
        cctpHelper.help(DOMAIN_ARBITRUM, ARB_FORK_ID, logs);

        /// verify USDC minted on destination
        vm.selectFork(ARB_FORK_ID);
        uint256 balanceAfter = IERC20(USDC_ARB).balanceOf(ALICE);
        assertGt(balanceAfter, balanceBefore, "USDC should have been minted on Arbitrum");
        /// amount minus any fees
        assertGe(balanceAfter - balanceBefore, amount - 1e6, "Minted amount should be close to burned amount");
    }

    /// @notice test that destinationCaller restriction works
    function testCctpV2WithDestinationCaller() external {
        uint256 amount = 500e6;
        address relayer = address(0xBEEF);

        vm.selectFork(ETH_FORK_ID);
        _dealUsdc(USDC_ETH, ALICE, amount);

        vm.startPrank(ALICE);
        IERC20(USDC_ETH).approve(TOKEN_MESSENGER_V2, amount);

        vm.recordLogs();

        ITokenMessengerV2(TOKEN_MESSENGER_V2).depositForBurnWithHook(
            amount,
            DOMAIN_ARBITRUM,
            bytes32(uint256(uint160(ALICE))),
            USDC_ETH,
            bytes32(uint256(uint160(relayer))), // only relayer can call receiveMessage
            0,
            2000,
            abi.encode(uint256(1))
        );
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        /// relay — helper should prank as destinationCaller
        cctpHelper.help(DOMAIN_ARBITRUM, ARB_FORK_ID, logs);

        /// verify USDC minted
        vm.selectFork(ARB_FORK_ID);
        uint256 balance = IERC20(USDC_ARB).balanceOf(ALICE);
        assertGt(balance, 0, "USDC should have been minted for restricted relay");
    }

    /// @notice test that anonymous events (zero topics) don't cause OOB revert
    function testCctpV2HandlesZeroTopicLogs() external {
        uint256 amount = 100e6;

        vm.selectFork(ETH_FORK_ID);
        _dealUsdc(USDC_ETH, ALICE, amount);

        vm.startPrank(ALICE);
        IERC20(USDC_ETH).approve(TOKEN_MESSENGER_V2, amount);

        vm.recordLogs();

        ITokenMessengerV2(TOKEN_MESSENGER_V2).depositForBurnWithHook(
            amount,
            DOMAIN_ARBITRUM,
            bytes32(uint256(uint160(ALICE))),
            USDC_ETH,
            bytes32(0),
            0,
            2000,
            abi.encode(uint256(1))
        );
        vm.stopPrank();

        Vm.Log[] memory realLogs = vm.getRecordedLogs();

        /// build a new array with a zero-topic log prepended
        Vm.Log[] memory logs = new Vm.Log[](realLogs.length + 1);
        /// anonymous event: zero topics, some data, arbitrary emitter
        logs[0].topics = new bytes32[](0);
        logs[0].data = abi.encode(uint256(42));
        logs[0].emitter = address(0xDEAD);
        for (uint256 i; i < realLogs.length; i++) {
            logs[i + 1] = realLogs[i];
        }

        /// should not revert and should still relay the real message
        vm.selectFork(ARB_FORK_ID);
        uint256 balanceBefore = IERC20(USDC_ARB).balanceOf(ALICE);
        vm.selectFork(ETH_FORK_ID);

        cctpHelper.help(DOMAIN_ARBITRUM, ARB_FORK_ID, logs);

        vm.selectFork(ARB_FORK_ID);
        uint256 balanceAfter = IERC20(USDC_ARB).balanceOf(ALICE);
        assertGt(balanceAfter, balanceBefore, "USDC should still be minted despite zero-topic log");
    }

    /// @notice test that replaying the same logs doesn't double-mint
    function testCctpV2NoDuplicateRelay() external {
        uint256 amount = 1000e6;

        vm.selectFork(ETH_FORK_ID);
        _dealUsdc(USDC_ETH, ALICE, amount);

        vm.startPrank(ALICE);
        IERC20(USDC_ETH).approve(TOKEN_MESSENGER_V2, amount);

        vm.recordLogs();

        ITokenMessengerV2(TOKEN_MESSENGER_V2).depositForBurnWithHook(
            amount,
            DOMAIN_ARBITRUM,
            bytes32(uint256(uint160(ALICE))),
            USDC_ETH,
            bytes32(0),
            0,
            2000,
            abi.encode(uint256(1))
        );
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        /// first relay
        cctpHelper.help(DOMAIN_ARBITRUM, ARB_FORK_ID, logs);

        vm.selectFork(ARB_FORK_ID);
        uint256 balanceAfterFirst = IERC20(USDC_ARB).balanceOf(ALICE);
        vm.selectFork(ETH_FORK_ID);

        /// second relay with the same logs — should be a no-op
        cctpHelper.help(DOMAIN_ARBITRUM, ARB_FORK_ID, logs);

        vm.selectFork(ARB_FORK_ID);
        uint256 balanceAfterSecond = IERC20(USDC_ARB).balanceOf(ALICE);
        assertEq(balanceAfterSecond, balanceAfterFirst, "Balance should not change on duplicate relay");
    }

    /// @notice test that emitter filter skips MessageSent from wrong address
    function testCctpV2EmitterFilter() external {
        uint256 amount = 100e6;

        vm.selectFork(ETH_FORK_ID);
        _dealUsdc(USDC_ETH, ALICE, amount);

        vm.startPrank(ALICE);
        IERC20(USDC_ETH).approve(TOKEN_MESSENGER_V2, amount);

        vm.recordLogs();

        ITokenMessengerV2(TOKEN_MESSENGER_V2).depositForBurnWithHook(
            amount,
            DOMAIN_ARBITRUM,
            bytes32(uint256(uint160(ALICE))),
            USDC_ETH,
            bytes32(0),
            0,
            2000,
            abi.encode(uint256(1))
        );
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        vm.selectFork(ARB_FORK_ID);
        uint256 balanceBefore = IERC20(USDC_ARB).balanceOf(ALICE);
        vm.selectFork(ETH_FORK_ID);

        /// use a bogus emitter filter — no logs should match
        address bogusEmitter = address(0x1234);
        cctpHelper.help(DOMAIN_ARBITRUM, ARB_FORK_ID, logs, bogusEmitter);

        vm.selectFork(ARB_FORK_ID);
        uint256 balanceAfter = IERC20(USDC_ARB).balanceOf(ALICE);
        assertEq(balanceAfter, balanceBefore, "Balance should be unchanged when emitter doesn't match");
    }

    /// @notice test that non-matching domain logs are skipped
    function testCctpV2SkipsNonMatchingDomain() external {
        uint256 amount = 100e6;

        vm.selectFork(ETH_FORK_ID);
        _dealUsdc(USDC_ETH, ALICE, amount);

        vm.startPrank(ALICE);
        IERC20(USDC_ETH).approve(TOKEN_MESSENGER_V2, amount);

        vm.recordLogs();

        /// send to Arbitrum (domain 3) but filter for Base (domain 6)
        ITokenMessengerV2(TOKEN_MESSENGER_V2).depositForBurnWithHook(
            amount,
            DOMAIN_ARBITRUM,
            bytes32(uint256(uint160(ALICE))),
            USDC_ETH,
            bytes32(0),
            0,
            2000,
            abi.encode(uint256(1))
        );
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();

        /// record balance on Arbitrum before
        vm.selectFork(ARB_FORK_ID);
        uint256 balanceBefore = IERC20(USDC_ARB).balanceOf(ALICE);
        vm.selectFork(ETH_FORK_ID);

        /// try to relay with wrong domain (Base = 6); should be a no-op
        uint32 DOMAIN_BASE = 6;
        cctpHelper.help(DOMAIN_BASE, ARB_FORK_ID, logs);

        /// balance should be unchanged
        vm.selectFork(ARB_FORK_ID);
        uint256 balanceAfter = IERC20(USDC_ARB).balanceOf(ALICE);
        assertEq(balanceAfter, balanceBefore, "Balance should be unchanged for non-matching domain");
    }
}
