// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title Relay Helper
/// @notice helps simulate Relay Protocol (relay.link) solver fills
/// @dev Relay differs structurally from Across/deBridge: the origin deposit
///      (RelayDepository.depositErc20/depositNative) carries only a bytes32 order id — NO
///      destination payload. The destination execution (txs[]) is quoted off-chain and executed
///      by the solver atomically via a router multicall (allowFailure = false). Consequently this
///      helper cannot derive the destination calls from origin logs; the caller supplies them as
///      parameters, and the helper (1) verifies a matching deposit event was emitted by the
///      depository and (2) executes the supplied txs[] in order on the destination fork under a
///      synthetic solver, reverting on the first failure to model the atomic batch.
contract RelayHelper is Test {
    /// @dev Relay deposit events carry no indexed parameters — decode everything from log.data
    bytes32 constant RelayErc20Deposit = keccak256("RelayErc20Deposit(address,address,uint256,bytes32)");
    bytes32 constant RelayNativeDeposit = keccak256("RelayNativeDeposit(address,uint256,bytes32)");

    /// @notice a destination call in the solver's atomic fill batch (mirrors the quote API txs[])
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    struct HelpArgs {
        address depository;
        bytes32 depositId;
        address solver;
        address outputToken;
        uint256 outputAmount;
        uint256 dstForkId;
        Call[] dstTxs;
        Vm.Log[] logs;
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice simulates a Relay solver fill for a recorded deposit
    /// @param depository the RelayDepository on the source chain (event emitter to match)
    /// @param depositId the Relay order id the fill corresponds to (bytes32(0) = match any)
    /// @param solver the synthetic solver address executing the fill
    /// @param outputToken the token the solver delivers on the destination (address(0) = native)
    /// @param outputAmount the amount the solver funds itself with before executing dstTxs
    /// @param dstForkId the destination chain fork id
    /// @param dstTxs the destination calls executed in order, atomically (first failure reverts)
    /// @param logs the recorded source-chain logs (vm.getRecordedLogs())
    function help(
        address depository,
        bytes32 depositId,
        address solver,
        address outputToken,
        uint256 outputAmount,
        uint256 dstForkId,
        Call[] memory dstTxs,
        Vm.Log[] calldata logs
    ) external {
        _help(
            HelpArgs({
                depository: depository,
                depositId: depositId,
                solver: solver,
                outputToken: outputToken,
                outputAmount: outputAmount,
                dstForkId: dstForkId,
                dstTxs: dstTxs,
                logs: logs
            })
        );
    }

    /// @notice convenience wrapper: deliver funds to `account` then call `target` with `data`
    /// @dev models the primary Superform integration path — transfer to the smart account,
    ///      then call SuperDestinationExecutor.processBridgedExecution
    function helpRelayDirect(
        address depository,
        bytes32 depositId,
        address solver,
        address outputToken,
        uint256 outputAmount,
        uint256 dstForkId,
        address account,
        address target,
        bytes memory data,
        Vm.Log[] calldata logs
    ) external {
        Call[] memory txs = new Call[](2);
        if (outputToken == address(0)) {
            txs[0] = Call({to: account, value: outputAmount, data: ""});
        } else {
            txs[0] =
                Call({to: outputToken, value: 0, data: abi.encodeWithSelector(IERC20.transfer.selector, account, outputAmount)});
        }
        txs[1] = Call({to: target, value: 0, data: data});

        _help(
            HelpArgs({
                depository: depository,
                depositId: depositId,
                solver: solver,
                outputToken: outputToken,
                outputAmount: outputAmount,
                dstForkId: dstForkId,
                dstTxs: txs,
                logs: logs
            })
        );
    }

    /// @notice convenience wrapper: deliver funds to `adapter` then call adapter's entrypoint
    /// @dev models the optional Superform adapter path — transfer to RelayAdapter, then
    ///      processRelayExecution; for native, value rides on the adapter call itself
    function helpRelayViaAdapter(
        address depository,
        bytes32 depositId,
        address solver,
        address outputToken,
        uint256 outputAmount,
        uint256 dstForkId,
        address adapter,
        bytes memory adapterCalldata,
        Vm.Log[] calldata logs
    ) external {
        Call[] memory txs;
        if (outputToken == address(0)) {
            txs = new Call[](1);
            txs[0] = Call({to: adapter, value: outputAmount, data: adapterCalldata});
        } else {
            txs = new Call[](2);
            txs[0] =
                Call({to: outputToken, value: 0, data: abi.encodeWithSelector(IERC20.transfer.selector, adapter, outputAmount)});
            txs[1] = Call({to: adapter, value: 0, data: adapterCalldata});
        }

        _help(
            HelpArgs({
                depository: depository,
                depositId: depositId,
                solver: solver,
                outputToken: outputToken,
                outputAmount: outputAmount,
                dstForkId: dstForkId,
                dstTxs: txs,
                logs: logs
            })
        );
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    function _help(HelpArgs memory args) internal {
        // 1. verify a matching deposit event was emitted by the depository on the source chain
        require(_depositEventFound(args), "RelayHelper: no matching Relay deposit event");

        // 2. execute the fill on the destination fork under the synthetic solver
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(args.dstForkId);

        // fund the solver with the output it delivers (solvers fill from their own capital)
        if (args.outputToken == address(0)) {
            vm.deal(args.solver, args.solver.balance + args.outputAmount);
        } else {
            deal(args.outputToken, args.solver, args.outputAmount);
        }

        // execute txs[] in order; revert on first failure — models the router's atomic
        // multicall with allowFailure = false (a failed fill unwinds entirely into refund)
        vm.startPrank(args.solver);
        for (uint256 i; i < args.dstTxs.length; i++) {
            (bool success, bytes memory ret) = args.dstTxs[i].to.call{value: args.dstTxs[i].value}(args.dstTxs[i].data);
            if (!success) {
                // bubble the inner revert reason for debuggability
                if (ret.length > 0) {
                    assembly {
                        revert(add(ret, 0x20), mload(ret))
                    }
                }
                revert("RelayHelper: destination call failed");
            }
        }
        vm.stopPrank();

        vm.selectFork(prevForkId);
    }

    /// @dev scans logs for a RelayErc20Deposit/RelayNativeDeposit emitted by the depository,
    ///      optionally matching a specific deposit id (both events have NO indexed params)
    function _depositEventFound(HelpArgs memory args) internal pure returns (bool) {
        for (uint256 i; i < args.logs.length; i++) {
            if (args.logs[i].emitter != args.depository || args.logs[i].topics.length == 0) {
                continue;
            }

            if (args.logs[i].topics[0] == RelayErc20Deposit) {
                (,,, bytes32 id) = abi.decode(args.logs[i].data, (address, address, uint256, bytes32));
                if (args.depositId == bytes32(0) || id == args.depositId) return true;
            } else if (args.logs[i].topics[0] == RelayNativeDeposit) {
                (,, bytes32 id) = abi.decode(args.logs[i].data, (address, uint256, bytes32));
                if (args.depositId == bytes32(0) || id == args.depositId) return true;
            }
        }
        return false;
    }
}
