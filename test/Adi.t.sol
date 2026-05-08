// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {AdiHelper} from "src/adi/AdiHelper.sol";
import {ArbitrumNativeHelper} from "src/arbitrum/ArbitrumNativeHelper.sol";
import {CcipHelper} from "src/ccip/CcipHelper.sol";
import {LayerZeroV2Helper} from "src/layerzero-v2/LayerZeroV2Helper.sol";
import {HyperlaneHelper} from "src/hyperlane/HyperlaneHelper.sol";

interface ICrossChainController {
    function forwardMessage(uint256 destinationChainId, address destination, uint256 gasLimit, bytes memory message)
        external
        returns (bytes32, bytes32);

    function approveSenders(address[] memory senders) external;
    function isSenderApproved(address sender) external view returns (bool);
    function owner() external view returns (address);
}

/// @notice Minimal a.DI receiver portal — implements `IBaseReceiverPortal.receiveCrossChainMessage`.
contract Target {
    address public lastOriginSender;
    uint256 public lastOriginChainId;
    bytes public lastMessage;
    uint256 public callCount;

    function receiveCrossChainMessage(address originSender, uint256 originChainId, bytes memory message) external {
        lastOriginSender = originSender;
        lastOriginChainId = originChainId;
        lastMessage = message;
        callCount += 1;
    }
}

contract AdiHelperTest is Test {
    AdiHelper adiHelper;
    ArbitrumNativeHelper arbHelper;
    CcipHelper ccipHelper;
    LayerZeroV2Helper lzHelper;
    HyperlaneHelper hlHelper;

    Target targetEth;
    Target targetArb;

    uint256 ETH_FORK_ID;
    uint256 ARB_FORK_ID;

    /// @dev Aave Labs forked a.DI deployment (extracted from sample txs in the spec).
    address constant L1_CCC = 0x1dbb574D08311eecb57D6616bC8AC3E94a3C6De6;
    address constant L2_CCC = 0x0910012Dd03cBA3Ed747cee17d65Ef5B80b490Ba;
    address constant CCC_OWNER = 0xfB65C68526969DA4AA3cEDF30b1C53846116D5a2;

    /// @dev AMB infrastructure addresses (mainnet).
    address constant ARB_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    address constant ARB_BRIDGE = 0x8315177aB297bA92A06054cE80a67Ed4DBd7ed3a;
    address constant ETH_CCIP_ROUTER = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    uint64 constant ETH_CCIP_CHAIN_SELECTOR = 5009297550715157269;
    address constant LZ_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
    /// @dev Aave Labs Eth-side HL mailbox is a custom deployment, NOT the canonical
    /// `0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70`. Verified via the HL adapter's `HL_MAIL_BOX()` getter.
    address constant ETH_HL_MAILBOX = 0xc005dc82818d67AF737725bD4bf75435d065D239;
    address constant ARB_HL_MAILBOX = 0x979Ca5202784112f4738403dBec5D0F3B9daabB9;

    uint256 constant ETH_CHAIN_ID = 1;
    uint256 constant ARB_CHAIN_ID = 42161;

    string RPC_ETH = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_ARB = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        ETH_FORK_ID = vm.createSelectFork(RPC_ETH, 25_030_000);
        targetEth = new Target();

        ARB_FORK_ID = vm.createSelectFork(RPC_ARB, 459_800_000);
        targetArb = new Target();

        // Deploy helpers on ARB; AdiHelper constructor calls vm.makePersistent on each so they live across forks.
        ccipHelper = new CcipHelper();
        lzHelper = new LayerZeroV2Helper();
        hlHelper = new HyperlaneHelper();
        arbHelper = new ArbitrumNativeHelper();
        adiHelper = new AdiHelper(ccipHelper, lzHelper, hlHelper, arbHelper);
    }

    function testAdiEthToArb() external {
        vm.selectFork(ETH_FORK_ID);

        // Approve this test as a sender on the L1 CCC (owner-gated).
        address[] memory senders = new address[](1);
        senders[0] = address(this);
        vm.prank(CCC_OWNER);
        ICrossChainController(L1_CCC).approveSenders(senders);

        // Fund the L1 CCC to pay the retryable submission fee.
        vm.deal(L1_CCC, 5 ether);

        vm.recordLogs();
        // ||
        // ||
        // \/ This is the part of the code you could copy to use the AdiHelper in your own tests.
        ICrossChainController(L1_CCC).forwardMessage(ARB_CHAIN_ID, address(targetArb), 200_000, abi.encode("hello-arb"));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        adiHelper.helpEthToArb(
            AdiHelper.EthToArbArgs({
                l2ForkId: ARB_FORK_ID,
                l1Inbox: ARB_INBOX,
                l1Bridge: ARB_BRIDGE,
                expectedL1CCC: L1_CCC,
                logs: logs
            })
        );
        // /\
        // ||
        // ||

        vm.selectFork(ARB_FORK_ID);
        assertEq(targetArb.callCount(), 1, "Target.receiveCrossChainMessage not called");
        assertEq(targetArb.lastOriginChainId(), ETH_CHAIN_ID, "Origin chainId mismatch");
        assertEq(targetArb.lastOriginSender(), address(this), "Origin sender mismatch");
        assertEq(abi.decode(targetArb.lastMessage(), (string)), "hello-arb", "Message mismatch");
    }

    function testAdiArbToEth() external {
        vm.selectFork(ARB_FORK_ID);

        address[] memory senders = new address[](1);
        senders[0] = address(this);
        vm.prank(CCC_OWNER);
        ICrossChainController(L2_CCC).approveSenders(senders);

        // Fund the L2 CCC to pay CCIP+LZ V2+Hyperlane fees.
        vm.deal(L2_CCC, 10 ether);

        vm.recordLogs();
        ICrossChainController(L2_CCC).forwardMessage(ETH_CHAIN_ID, address(targetEth), 200_000, abi.encode("hello-eth"));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Relay via all 3 AMBs (CCIP + LZ V2 + Hyperlane). Threshold is 2/N — once met the envelope is `Delivered`
        // and any subsequent adapter delivery just increments confirmations without re-executing the receiver.
        adiHelper.helpMultiBridge(
            AdiHelper.MultiBridgeArgs({
                dstForkId: ETH_FORK_ID,
                dstCcipRouter: ETH_CCIP_ROUTER,
                dstCcipChainSelector: ETH_CCIP_CHAIN_SELECTOR,
                srcCcipOnRamp: address(0),
                dstLzEndpoint: LZ_ENDPOINT_V2,
                srcHlMailbox: ARB_HL_MAILBOX,
                dstHlMailbox: ETH_HL_MAILBOX,
                logs: logs
            })
        );

        vm.selectFork(ETH_FORK_ID);
        assertEq(targetEth.callCount(), 1, "Target.receiveCrossChainMessage not called after consensus");
        assertEq(targetEth.lastOriginChainId(), ARB_CHAIN_ID);
        assertEq(targetEth.lastOriginSender(), address(this));
        assertEq(abi.decode(targetEth.lastMessage(), (string)), "hello-eth");
    }

    function testAdiCountSuccessfulForwards() external {
        vm.selectFork(ARB_FORK_ID);

        address[] memory senders = new address[](1);
        senders[0] = address(this);
        vm.prank(CCC_OWNER);
        ICrossChainController(L2_CCC).approveSenders(senders);
        vm.deal(L2_CCC, 10 ether);

        vm.recordLogs();
        ICrossChainController(L2_CCC).forwardMessage(ETH_CHAIN_ID, address(targetEth), 200_000, abi.encode("count"));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Aave Labs Arb→Eth has 3 forwarder adapter pairs configured; expect all 3 to fire successfully.
        uint256 successful = adiHelper.countSuccessfulForwards(logs);
        assertEq(successful, 3, "expected all 3 AMB adapters to forward successfully");
    }
}
