// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
import {CcipHelper} from "../ccip/CcipHelper.sol";
import {LayerZeroV2Helper} from "../layerzero-v2/LayerZeroV2Helper.sol";
import {HyperlaneHelper} from "../hyperlane/HyperlaneHelper.sol";
import {ArbitrumNativeHelper} from "../arbitrum/ArbitrumNativeHelper.sol";

/// @title a.DI Helper
/// @notice Helps simulate Aave Delivery Infrastructure (a.DI) envelope flows by composing pigeon's existing
/// per-AMB helpers (CCIP, LayerZero V2, Hyperlane) and a new Arbitrum-native primitive.
/// @dev a.DI's `CrossChainForwarder.forwardMessage` broadcasts an envelope to a (possibly shuffled) subset of
/// configured bridge adapters; the destination CCC executes the receiver once `requiredConfirmation` adapters
/// have delivered. This helper does not assume which adapters fired — each child helper self-filters its own
/// AMB's events and silently no-ops if none appear.
/// @dev IMPORTANT: a.DI's CCC must hold native to pay AMB fees. Callers MUST `vm.deal(address(CCC), ...)` BEFORE
/// invoking `forwardMessage`. This helper does NOT fund the CCC.
contract AdiHelper is Test {
    CcipHelper public immutable ccipHelper;
    LayerZeroV2Helper public immutable lzHelper;
    HyperlaneHelper public immutable hlHelper;
    ArbitrumNativeHelper public immutable arbHelper;

    /// @dev keccak256("TransactionForwardingAttempted(bytes32,bytes32,bytes,uint256,address,address,bool,bytes)")
    bytes32 public constant TRANSACTION_FORWARDING_ATTEMPTED_SELECTOR =
        0x935aa87d643578e6395c90fdbd5d50ffee5f2c1f6ce2cd01274740412bb679f4;

    struct EthToArbArgs {
        uint256 l2ForkId;
        address l1Inbox; // 0 = any
        address l1Bridge; // 0 = any
        address expectedL1CCC; // expected L1 sender on the retryable (CCC due to delegatecall)
        Vm.Log[] logs;
    }

    /// @notice Args for any "multi-bridge consensus" lane (Arb→Eth in v1; future Arb→Op etc.).
    /// @dev Set any endpoint/router to address(0) to disable that AMB. Each child helper self-filters.
    struct MultiBridgeArgs {
        uint256 dstForkId;
        // CCIP
        address dstCcipRouter; // 0 disables CCIP relay
        uint64 dstCcipChainSelector; // 0 = no selector filter
        address srcCcipOnRamp; // 0 = no emitter filter
        // LayerZero V2
        address dstLzEndpoint; // 0 disables LZ relay
        // Hyperlane
        address srcHlMailbox; // 0 disables HL relay (HyperlaneHelper requires both)
        address dstHlMailbox; // 0 disables HL relay
        Vm.Log[] logs;
    }

    constructor(CcipHelper c, LayerZeroV2Helper l, HyperlaneHelper h, ArbitrumNativeHelper a) {
        ccipHelper = c;
        lzHelper = l;
        hlHelper = h;
        arbHelper = a;
        vm.makePersistent(address(this));
        vm.makePersistent(address(c));
        vm.makePersistent(address(l));
        vm.makePersistent(address(h));
        vm.makePersistent(address(a));
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice Relay an Eth → Arb a.DI envelope via the Arbitrum native bridge.
    /// @dev Caller must `vm.deal(L1_CCC, ...)` BEFORE `forwardMessage` to fund the retryable.
    /// @param args the relay arguments
    function helpEthToArb(EthToArbArgs memory args) external {
        ArbitrumNativeHelper.HelpArgs memory inner = ArbitrumNativeHelper.HelpArgs({
            l2ForkId: args.l2ForkId,
            l1Inbox: args.l1Inbox,
            l1Bridge: args.l1Bridge,
            expectedL1Sender: args.expectedL1CCC,
            logs: args.logs
        });
        arbHelper.help(inner);
    }

    /// @notice Relay any multi-bridge consensus a.DI envelope (Arb → Eth canonical lane; future Arb → Op).
    /// @dev Each child helper self-filters from `args.logs`. Setting an endpoint to address(0) skips that AMB.
    /// @dev Over-delivery is fine: once the destination CCC's threshold is met the envelope transitions to
    /// `Delivered`, and subsequent adapter deliveries just increment `confirmations` without re-executing the
    /// receiver. The receive path through each adapter must succeed though — the per-adapter `onlyMailBox` /
    /// `onlyEndpoint` / `onlyRouter` checks must match the prank target you pass in. Read each deployed adapter's
    /// configured AMB endpoint via its public getter (e.g., `HL_MAIL_BOX()`, `LZ_ENDPOINT()`, `getRouter()`) — do
    /// NOT hardcode canonical AMB addresses, since deployments may use custom AMB infrastructure.
    /// @param args the relay arguments
    function helpMultiBridge(MultiBridgeArgs memory args) external {
        if (args.dstCcipRouter != address(0)) {
            CcipHelper.HelpArgs memory ccipArgs = CcipHelper.HelpArgs({
                dstForkId: args.dstForkId,
                dstRouter: args.dstCcipRouter,
                expDstChainSelector: args.dstCcipChainSelector,
                srcOnRamp: args.srcCcipOnRamp,
                logs: args.logs
            });
            ccipHelper.help(ccipArgs);
        }
        if (args.dstLzEndpoint != address(0)) {
            lzHelper.help(args.dstLzEndpoint, args.dstForkId, args.logs);
        }
        if (args.srcHlMailbox != address(0) && args.dstHlMailbox != address(0)) {
            hlHelper.help(args.srcHlMailbox, args.dstHlMailbox, args.dstForkId, args.logs);
        }
    }

    /// @notice Count source-side `TransactionForwardingAttempted` events with `adapterSuccessful = true`.
    /// @dev Useful for tests that want to assert the shuffle picked >= N adapters and they succeeded.
    /// @param logs the recorded source-tx logs
    /// @return count number of successful forwarding attempts
    function countSuccessfulForwards(Vm.Log[] memory logs) external pure returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length < 4) continue;
            if (logs[i].topics[0] != TRANSACTION_FORWARDING_ATTEMPTED_SELECTOR) continue;
            // adapterSuccessful is the third indexed field; topic[3] = bytes32(uint256(1)) when true
            if (logs[i].topics[3] == bytes32(uint256(1))) ++count;
        }
    }
}
