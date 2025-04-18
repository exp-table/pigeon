// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "forge-std/Test.sol";

import {DebridgeDlnHelper} from "../src/debridge/DebridgeDlnHelper.sol";
// Bring in the Order struct definition
import {DebridgeDlnHelper as DlnHelperContract} from "../src/debridge/DebridgeDlnHelper.sol";

// Placeholder interface for DlnSource - adjust if necessary
interface IDlnSource {
    function createOrder(DlnHelperContract.Order calldata order) external payable;
    // Add other relevant functions if needed
}

// Minimal interface for DlnDestination - matching the one in DebridgeDlnHelper
interface IDlnDestination {
    function fulfillOrder(
        DlnHelperContract.Order memory _order,
        uint256 _fulFillAmount,
        bytes32 _orderId,
        bytes calldata _permitEnvelope,
        address _unlockAuthority,
        address _externalCallRewardBeneficiary
    ) external payable;
}

contract DebridgeDlnHelperTest is Test {
    DebridgeDlnHelper debridgeDlnHelper;

    address public target; // Receiver address for the test

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    // --- Token Addresses ---
    address constant L1_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ARBITRUM_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant POLYGON_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359; // Native USDC on Polygon PoS

    // --- Chain IDs ---
    uint256 constant L1_ID = 1;
    uint256 constant ARBITRUM_ID = 42161;
    uint256 constant POLYGON_ID = 137;

    // --- Debridge DLN Addresses (same on all chains based on user info) ---
    address constant DLN_SOURCE_ADDRESS = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;
    address constant DLN_DESTINATION_ADDRESS = 0x33B72F60F2CEB7BDb64873Ac10015a35bed81717;

    // --- RPC URLs ---
    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    // eth refund / receive funds
    receive() external payable {}

    function setUp() external {
        // Use block numbers known to have the contracts deployed and stable
        // Note: Polygon block number might need adjustment if test fails
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 19000000);
        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 180000000);
        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 50000000);

        vm.selectFork(L1_FORK_ID); // Start on L1 fork
        debridgeDlnHelper = new DebridgeDlnHelper();
        target = address(this); // Use the test contract itself as the receiver
    }

    function testSingleDstDln_L1_to_Arbitrum_USDC() external {
        vm.selectFork(L1_FORK_ID);
        uint256 giveAmount = 100 * 1e6; // 100 USDC
        uint256 takeAmount = 99 * 1e6; // Expect ~99 USDC on destination (slippage/fees simulated)
        uint256 destinationChainId = ARBITRUM_ID;
        address giveToken = L1_USDC;
        address takeToken = ARBITRUM_USDC; // The token expected on the destination

        // 1. Prepare Order Struct
        // Ensure the test contract (maker) has USDC
        deal(giveToken, address(this), giveAmount);
        // Approve the DLN Source contract
        IERC20(giveToken).approve(DLN_SOURCE_ADDRESS, giveAmount);

        DlnHelperContract.Order memory order = DlnHelperContract.Order({
            makerOrderNonce: 0, // Example nonce
            makerSrc: abi.encodePacked(address(this)), // Maker is this contract
            giveChainId: L1_ID,
            giveTokenAddress: abi.encodePacked(giveToken),
            giveAmount: giveAmount,
            takeChainId: destinationChainId,
            takeTokenAddress: abi.encodePacked(takeToken),
            takeAmount: takeAmount,
            receiverDst: abi.encodePacked(target), // Receiver is the target address
            givePatchAuthoritySrc: abi.encodePacked(address(0)), // No patch authority
            orderAuthorityAddressDst: abi.encodePacked(address(0)), // No patch/cancel authority on dst
            allowedTakerDst: "", // Allow any taker
            allowedCancelBeneficiarySrc: "", // Allow any cancel beneficiary
            externalCall: "" // No external call for this simple test
        });

        // 2. Simulate Order Creation on Source Chain
        vm.recordLogs();
        // Call the actual DlnSource contract to emit the log the helper needs
        // We assume a simple `createOrder` function exists.
        // May require sending value if fees are involved (e.g., 0.1 ether)
        // Adjust msg.value if needed based on actual contract requirements
        uint256 fee = 0.01 ether; // Example fee, adjust if needed
        vm.deal(address(this), address(this).balance + fee); // Ensure contract has ETH for fee
        IDlnSource(DLN_SOURCE_ADDRESS).createOrder{value: fee}(order);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // 3. Use Helper to Process on Destination Chain
        // The helper internally switches forks, simulates the taker, etc.
        debridgeDlnHelper.help(DLN_SOURCE_ADDRESS, DLN_DESTINATION_ADDRESS, ARBITRUM_FORK_ID, ARBITRUM_ID, logs);

        // 4. Assert Final State on Destination Chain
        vm.selectFork(ARBITRUM_FORK_ID);
        uint256 expectedBalance = takeAmount; // For simulation, assume exact amount minus patches is received
        uint256 actualBalance = IERC20(takeToken).balanceOf(target);

        // Use assertApproxEqAbs due to potential minor differences if fees/patches were complex
        // Tolerance of 1 unit (e.g., 1 wei for USDC)
        assertApproxEqAbs(actualBalance, expectedBalance, 1, "Final balance on destination mismatch");

        // Optional: Check native balance if gas refunds are expected
        // uint256 finalNativeBalance = target.balance;
        // assertTrue(finalNativeBalance > initialNativeBalance, "Native balance did not increase");

        vm.selectFork(L1_FORK_ID); // Switch back to L1 fork for cleanup/next test
    }

    // TODO: Add testMultiDstDln similar to Debridge.t.sol
    // TODO: Add tests for native asset transfers (ETH)
    // TODO: Add tests involving externalCall hooks
}
