// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

import {DebridgeDlnHelper} from "../src/debridge/DebridgeDlnHelper.sol";
// Bring in the Order struct definition
import {DebridgeDlnHelper as DlnHelperContract} from "../src/debridge/DebridgeDlnHelper.sol";

import {IDlnSource} from "../src/debridge/interfaces/IDlnSource.sol";
import {IExternalCallExecutor} from "../src/debridge/interfaces/IExternalCallExecutor.sol";
import {DlnExternalCallLib} from "../src/debridge/libraries/DlnExternalCallLib.sol";

contract SampleExecutor is IExternalCallExecutor {
    uint256 public counter;
    address public lastToken;
    uint256 public lastAmount;
    bytes32 public lastOrderId;
    address public lastFallbackAddress;
    bytes public lastPayload;
    uint256 public lastReceivedValue;

    event Log(bool callSucceeded, uint256 transferredAmount, uint256 expectedAmount);
    // Allow receiving ETH

    receive() external payable {}

    /**
     * @notice Increments counter if the expected amount matches msg.value.
     * @dev Expected amount is decoded from _payload.
     */
    function onEtherReceived(bytes32 _orderId, address _fallbackAddress, bytes memory _payload)
        external
        payable
        override
        returns (bool callSucceeded, bytes memory)
    {
        lastOrderId = _orderId;
        lastFallbackAddress = _fallbackAddress;
        lastPayload = _payload;
        lastReceivedValue = msg.value; // Amount received by *this* contract from adapter

        // uint256 expectedAmount = abi.decode(_payload, (uint256));

        counter++;
        callSucceeded = true;

        emit Log(callSucceeded, msg.value, 0);
    }

    /**
     * @notice Increments counter if the expected amount matches _transferredAmount.
     * @dev Expected amount is decoded from _payload.
     */
    function onERC20Received(
        bytes32 _orderId,
        address _token,
        uint256 _transferredAmount, // Amount received by *this* contract from adapter
        address _fallbackAddress,
        bytes memory _payload
    ) external override returns (bool callSucceeded, bytes memory) {
        lastOrderId = _orderId;
        lastToken = _token;
        lastAmount = _transferredAmount;
        lastFallbackAddress = _fallbackAddress;
        lastPayload = _payload;

        //uint256 expectedAmount = abi.decode(_payload, (uint256));

        counter++;
        callSucceeded = true;

        emit Log(callSucceeded, _transferredAmount, 0);
        // callResult can be used to return data if needed
    }
}

contract DebridgeDlnHelperTest is Test {
    DebridgeDlnHelper debridgeDlnHelper;

    address public target; // Receiver address for the test
    // State variables for deployed executors on different forks
    SampleExecutor executorArb;
    // Add executorPoly if testing Polygon external calls

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    // --- Token Addresses ---
    address constant L1_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ARBITRUM_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant POLYGON_USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359; // Native USDC on Polygon PoS

    // --- Chain IDs ---
    uint256 constant L1_ID = 1;
    uint256 constant ARBITRUM_ID = 42_161;
    uint256 constant POLYGON_ID = 137;

    // --- Debridge DLN Addresses (same on all chains based on user info) ---
    address constant DLN_SOURCE_ADDRESS = 0xeF4fB24aD0916217251F553c0596F8Edc630EB66;
    address constant DLN_DESTINATION_ADDRESS = 0xE7351Fd770A37282b91D153Ee690B63579D6dd7f;

    // --- RPC URLs ---
    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    // Constants for the maker simulation
    address constant MAKER_ADDRESS = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf; // Using TAKER_ADDRESS from helper as
        // maker

    function setUp() external {
        // Use block numbers known to have the contracts deployed and stable
        // Note: Polygon block number might need adjustment if test fails
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 19_000_000);
        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 180_000_000);
        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 50_000_000);

        vm.selectFork(L1_FORK_ID); // Select L1 fork
        debridgeDlnHelper = new DebridgeDlnHelper();
        target = address(this);
        vm.label(DLN_SOURCE_ADDRESS, "DLN_SOURCE_ADDRESS");
        vm.label(DLN_DESTINATION_ADDRESS, "DLN_DESTINATION_ADDRESS");

        vm.selectFork(ARBITRUM_FORK_ID); // Select Arbitrum fork
        executorArb = new SampleExecutor(); // Deploy on Arbitrum
        vm.label(address(executorArb), "Executor_Arb");

        vm.selectFork(L1_FORK_ID); // Return to L1 fork as default state for tests
    }

    function testSingleDstDln_L1_to_Arbitrum_USDC() external {
        vm.selectFork(L1_FORK_ID);
        uint256 giveAmount = 100 * 1e6; // 100 USDC
        uint256 takeAmount = 99 * 1e6; // Expect ~99 USDC on destination (slippage/fees simulated)
        uint256 destinationChainId = ARBITRUM_ID;
        address giveToken = L1_USDC;
        address takeToken = ARBITRUM_USDC; // The token expected on the destination
        address makerAddress = MAKER_ADDRESS; // Use the defined constant

        // 1. Prepare OrderCreation Struct & Maker
        // Ensure the maker address has USDC
        deal(giveToken, makerAddress, giveAmount);
        // Re-add approve call
        vm.prank(makerAddress); // Prank as maker to approve
        IERC20(giveToken).approve(DLN_SOURCE_ADDRESS, giveAmount);

        // Use OrderCreation struct now
        IDlnSource.OrderCreation memory orderCreation = IDlnSource.OrderCreation({
            giveTokenAddress: giveToken,
            giveAmount: giveAmount,
            takeTokenAddress: abi.encodePacked(takeToken),
            takeAmount: takeAmount,
            takeChainId: destinationChainId,
            receiverDst: abi.encodePacked(target), // Receiver is the target address
            givePatchAuthoritySrc: address(0), // No patch authority
            orderAuthorityAddressDst: abi.encodePacked(address(0)), // No patch/cancel authority on dst
            allowedTakerDst: "", // Allow any taker
            externalCall: "", // No external call for this simple test
            allowedCancelBeneficiarySrc: "" // Allow any cancel beneficiary
        });

        // 3. Simulate Order Creation on Source Chain (using Approve)
        vm.recordLogs();
        // Fetch the required fixed fee from the contract
        uint256 requiredFee = IDlnSource(DLN_SOURCE_ADDRESS).globalFixedNativeFee();

        // The maker needs ETH for the fee
        vm.deal(makerAddress, makerAddress.balance + requiredFee);

        // Prank as the maker to call createOrder
        vm.prank(makerAddress);
        // Pass the OrderCreation struct and the correct fee
        // Pass empty bytes for permitEnvelope as we are using approve
        IDlnSource(DLN_SOURCE_ADDRESS).createOrder{value: requiredFee}(
            orderCreation, // The OrderCreation struct
            "", // affiliateFee (bytes)
            0, // referralCode (uint32)
            "" // permitEnvelope (empty)
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // 4. Use Helper to Process on Destination Chain (Helper handles the *destination* permit correctly)
        debridgeDlnHelper.help(DLN_SOURCE_ADDRESS, DLN_DESTINATION_ADDRESS, ARBITRUM_FORK_ID, ARBITRUM_ID, logs);

        // 5. Assert Final State on Destination Chain
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

    // ==================== External Call Tests ==================== //

    function testExternalCall_ERC20_L1_to_Arbitrum() external {
        // --- Setup ---
        vm.selectFork(L1_FORK_ID);
        // Use the executor deployed on Arbitrum fork as the target
        address targetExecutorAddress = address(executorArb);

        console.log("targetExecutorAddress", targetExecutorAddress);

        uint256 giveAmount = 100 * 1e6; // 100 L1 USDC
        uint256 takeAmount = 99 * 1e6; // Expect 99 Arb USDC
        uint256 destinationChainId = ARBITRUM_ID;
        address giveToken = L1_USDC;
        address takeToken = ARBITRUM_USDC;
        address makerAddress = MAKER_ADDRESS;

        // --- Prepare Order ---
        deal(giveToken, makerAddress, giveAmount);
        vm.prank(makerAddress);
        IERC20(giveToken).approve(DLN_SOURCE_ADDRESS, giveAmount);

        // 1. Create the inner payload for the SampleExecutor
        bytes memory executorPayload = abi.encode(takeAmount);

        // 2. Create the Debridge External Call Envelope V1
        DlnExternalCallLib.ExternalCallEnvelopV1 memory dataEnvelope = DlnExternalCallLib.ExternalCallEnvelopV1({
            executorAddress: targetExecutorAddress, // Explicitly target our executor
            executionFee: 0,
            fallbackAddress: address(0), // No fallback needed for this test
            payload: executorPayload,
            allowDelayedExecution: true, // Allow fallback if needed, though test expects direct execution
            requireSuccessfullExecution: false // Don't revert outer tx if executor fails (though we assert success
                // later)
        });

        // 3. Prepend version byte (1) to the encoded envelope
        bytes memory externalCall = abi.encodePacked(uint8(1), abi.encode(dataEnvelope));

        // 4. Create the DLN Order pointing to the *Adapter's target executor*
        //    (which is our SampleExecutor instance on the Arb fork)
        IDlnSource.OrderCreation memory orderCreation = IDlnSource.OrderCreation({
            giveTokenAddress: giveToken,
            giveAmount: giveAmount,
            takeTokenAddress: abi.encodePacked(takeToken),
            takeAmount: takeAmount,
            takeChainId: destinationChainId,
            // receiverDst MUST be the executor address for the adapter to call it
            receiverDst: abi.encodePacked(targetExecutorAddress),
            givePatchAuthoritySrc: address(0),
            orderAuthorityAddressDst: abi.encodePacked(address(0)),
            allowedTakerDst: "",
            externalCall: externalCall, // Use the correctly formatted envelope
            allowedCancelBeneficiarySrc: ""
        });

        // --- Create Order ---
        vm.recordLogs();
        uint256 requiredFee = IDlnSource(DLN_SOURCE_ADDRESS).globalFixedNativeFee();
        vm.deal(makerAddress, makerAddress.balance + requiredFee);
        vm.prank(makerAddress);
        IDlnSource(DLN_SOURCE_ADDRESS).createOrder{value: requiredFee}(orderCreation, "", 0, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // --- Process with Helper ---
        debridgeDlnHelper.help(DLN_SOURCE_ADDRESS, DLN_DESTINATION_ADDRESS, ARBITRUM_FORK_ID, ARBITRUM_ID, logs);

        // --- Assert Destination State ---
        vm.selectFork(ARBITRUM_FORK_ID);
        // Now the counter check should pass as the adapter calls the correct executor
        assertEq(executorArb.counter(), 1, "Executor counter mismatch (ERC20)");
        // Optional checks on Arbitrum executor state:
        assertEq(executorArb.lastToken(), takeToken, "Executor last token mismatch");
        assertEq(executorArb.lastAmount(), takeAmount, "Executor last amount mismatch");

        vm.selectFork(L1_FORK_ID); // Revert fork
    }

    function testExternalCall_Native_L1_to_Arbitrum() external {
        // --- Setup ---
        vm.selectFork(L1_FORK_ID);
        // Use the executor deployed on Arbitrum fork as the target
        address targetExecutorAddress = address(executorArb);

        uint256 giveAmount = 0.1 ether;
        uint256 takeAmount = 0.099 ether;
        uint256 destinationChainId = ARBITRUM_ID;
        address giveToken = address(0); // Native ETH
        address takeToken = address(0); // Native ETH on Arbitrum
        address makerAddress = MAKER_ADDRESS;

        // --- Prepare Order ---
        // 1. Create the inner payload for the SampleExecutor
        bytes memory executorPayload = abi.encode(takeAmount);

        // 2. Create the Debridge External Call Envelope V1
        DlnExternalCallLib.ExternalCallEnvelopV1 memory dataEnvelope = DlnExternalCallLib.ExternalCallEnvelopV1({
            executorAddress: targetExecutorAddress,
            executionFee: 0,
            fallbackAddress: address(0),
            payload: executorPayload,
            allowDelayedExecution: true,
            requireSuccessfullExecution: false
        });

        // 3. Prepend version byte (1) to the encoded envelope
        bytes memory externalCall = abi.encodePacked(uint8(1), abi.encode(dataEnvelope));

        // 4. Create the DLN Order
        IDlnSource.OrderCreation memory orderCreation = IDlnSource.OrderCreation({
            giveTokenAddress: giveToken,
            giveAmount: giveAmount,
            takeTokenAddress: abi.encodePacked(takeToken),
            takeAmount: takeAmount,
            takeChainId: destinationChainId,
            receiverDst: abi.encodePacked(targetExecutorAddress), // Target the executor
            givePatchAuthoritySrc: address(0),
            orderAuthorityAddressDst: abi.encodePacked(address(0)),
            allowedTakerDst: "",
            externalCall: externalCall, // Use the correctly formatted envelope
            allowedCancelBeneficiarySrc: ""
        });

        // --- Create Order ---
        vm.recordLogs();
        uint256 requiredFee = IDlnSource(DLN_SOURCE_ADDRESS).globalFixedNativeFee();
        vm.deal(makerAddress, makerAddress.balance + giveAmount + requiredFee);
        vm.prank(makerAddress);
        IDlnSource(DLN_SOURCE_ADDRESS).createOrder{value: giveAmount + requiredFee}(orderCreation, "", 0, "");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // --- Process with Helper ---
        debridgeDlnHelper.help(DLN_SOURCE_ADDRESS, DLN_DESTINATION_ADDRESS, ARBITRUM_FORK_ID, ARBITRUM_ID, logs);

        // --- Assert Destination State ---
        vm.selectFork(ARBITRUM_FORK_ID);
        // Now the counter check should pass
        assertEq(executorArb.counter(), 1, "Executor counter mismatch (Native)");
        // Optional checks on Arbitrum executor state:
        assertEq(executorArb.lastToken(), address(0), "Executor last token mismatch (Native)");
        assertEq(executorArb.lastReceivedValue(), takeAmount, "Executor last received value mismatch");

        vm.selectFork(L1_FORK_ID); // Revert fork
    }
}
