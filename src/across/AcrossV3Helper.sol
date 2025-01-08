// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import {IAcrossSpokePoolV3} from "./interfaces/IAcrossSpokePoolV3.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title AcrossV3 Helper
/// @notice helps simulate AcrossV3 message relaying
contract AcrossV3Helper is Test {
    bytes32 constant V3FundsDeposited = keccak256(
        "V3FundsDeposited(address,address,uint256,uint256,uint256,uint32,uint32,uint32,uint32,address,address,address,bytes)"
    );

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice helps process multiple destination messages to relay
    /// @param sourceSpokePool represents the across spoke pool on the source chain
    /// @param destinationSpokePools represents the across spoke pools on the destination chain
    /// @param relayer represents the relayer address
    /// @param forkIds represents the destination chain fork ids
    /// @param destinationChainIds represents the destination chain ids
    /// @param refundChainIds represents the refund chain ids
    /// @param logs represents the recorded message logs
    function help(
        address sourceSpokePool,
        address[] memory destinationSpokePools,
        address relayer,
        uint256[] memory forkIds,
        uint256[] memory destinationChainIds,
        uint256[] memory refundChainIds,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i; i < destinationSpokePools.length; ++i) {
            console.log("i", i);
            _help(
                HelpArgs({
                    sourceSpokePool: sourceSpokePool,
                    destinationSpokePool: destinationSpokePools[i],
                    relayer: relayer,
                    forkId: forkIds[i],
                    destinationChainId: destinationChainIds[i],
                    refundChainId: refundChainIds[i],
                    eventSelector: V3FundsDeposited,
                    logs: logs
                })
            );
        }
    }

    /// @notice helps process multiple destination messages to relay
    /// @param sourceSpokePool represents the across spoke pool on the source chain
    /// @param destinationSpokePools represents the across spoke pools on the destination chain
    /// @param relayer represents the relayer address
    /// @param forkIds represents the destination chain fork ids
    /// @param destinationChainIds represents the destination chain ids
    /// @param refundChainIds represents the refund chain ids
    /// @param eventSelector represents a custom event selector
    /// @param logs represents the recorded message logs
    function help(
        address sourceSpokePool,
        address[] memory destinationSpokePools,
        address relayer,
        uint256[] memory forkIds,
        uint256[] memory destinationChainIds,
        uint256[] memory refundChainIds,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        for (uint256 i; i < destinationSpokePools.length; ++i) {
            _help(
                HelpArgs({
                    sourceSpokePool: sourceSpokePool,
                    destinationSpokePool: destinationSpokePools[i],
                    relayer: relayer,
                    forkId: forkIds[i],
                    destinationChainId: destinationChainIds[i],
                    refundChainId: refundChainIds[i],
                    eventSelector: eventSelector,
                    logs: logs
                })
            );
        }
    }

    /// @notice helps process a single destination message to relay
    /// @param sourceSpokePool represents the across spoke pool on the source chain
    /// @param destinationSpokePool represents the across spoke pool on the destination chain
    /// @param relayer represents the relayer address
    /// @param forkId represents the destination chain fork id
    /// @param destinationChainId represents the destination chain id
    /// @param refundChainId represents the refund chain id
    /// @param logs represents the recorded message logs
    function help(
        address sourceSpokePool,
        address destinationSpokePool,
        address relayer,
        uint256 forkId,
        uint256 destinationChainId,
        uint256 refundChainId,
        Vm.Log[] calldata logs
    ) external {
        _help(
            HelpArgs({
                sourceSpokePool: sourceSpokePool,
                destinationSpokePool: destinationSpokePool,
                relayer: relayer,
                forkId: forkId,
                destinationChainId: destinationChainId,
                refundChainId: refundChainId,
                eventSelector: V3FundsDeposited,
                logs: logs
            })
        );
    }

    /// @notice helps process a single destination message to relay
    /// @param sourceSpokePool represents the across spoke pool on the source chain
    /// @param destinationSpokePool represents the across spoke pool on the destination chain
    /// @param relayer represents the relayer address
    /// @param forkId represents the destination chain fork id
    /// @param refundChainId represents the refund chain id
    /// @param eventSelector represents a custom bytes32 event selector
    /// @param logs represents the recorded message logs
    function help(
        address sourceSpokePool,
        address destinationSpokePool,
        address relayer,
        uint256 forkId,
        uint256 destinationChainId,
        uint256 refundChainId,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        _help(
            HelpArgs({
                sourceSpokePool: sourceSpokePool,
                destinationSpokePool: destinationSpokePool,
                relayer: relayer,
                forkId: forkId,
                destinationChainId: destinationChainId,
                refundChainId: refundChainId,
                eventSelector: eventSelector,
                logs: logs
            })
        );
    }

    struct HelpArgs {
        address sourceSpokePool;
        address destinationSpokePool;
        address relayer;
        uint256 forkId;
        uint256 destinationChainId;
        uint256 refundChainId;
        bytes32 eventSelector;
        Vm.Log[] logs;
    }

    struct AcrossV3LogData {
        address inputToken;
        address outputToken;
        uint256 inputAmount;
        uint256 outputAmount;
        uint32 quoteTimestamp;
        uint32 fillDeadline;
        uint32 exclusivityDeadline;
        address recipient;
        address exclusiveRelayer;
        bytes message;
    }

    struct LocalVars {
        uint256 prevForkId;
        uint256 originChainId;
        uint256 destinationChainId;
        AcrossV3LogData logData;
    }

    /// @notice internal function to process a single destination message to relay
    /// @param args represents the help arguments
    function _help(HelpArgs memory args) internal {
        LocalVars memory vars;
        vars.originChainId = uint256(block.chainid);
        vars.prevForkId = vm.activeFork();

        vm.selectFork(args.forkId);
        vm.startBroadcast(args.relayer);
        for (uint256 i; i < args.logs.length; i++) {
            // https://docs.across.to/introduction/migration-guides/migration-from-v2-to-v3
            // V3FundsDeposited is the event selector for the V3FundsDeposited event emitted by the SpokePool contract
            // Relayers should note that all deposits in V3 are associated with V3FundsDeposited events
            // and must be filled using the fillV3Relay function of the SpokePool contract.
            if (args.logs[i].topics[0] == args.eventSelector && args.logs[i].emitter == args.sourceSpokePool) {
                vars.destinationChainId = uint256(args.logs[i].topics[1]);

                if (vars.destinationChainId == args.destinationChainId) {
                    vars.logData = _decodeLogData(args.logs[i]);

                    assertEq(vars.destinationChainId, args.destinationChainId);
                    deal(vars.logData.outputToken, args.relayer, vars.logData.outputAmount);

                    IERC20(vars.logData.outputToken).approve(args.destinationSpokePool, vars.logData.outputAmount);
                    IAcrossSpokePoolV3(args.destinationSpokePool).fillV3Relay(
                        IAcrossSpokePoolV3.V3RelayData({
                            depositor: address(uint160(uint256(args.logs[i].topics[2]))),
                            recipient: vars.logData.recipient,
                            exclusiveRelayer: vars.logData.exclusiveRelayer,
                            inputToken: vars.logData.inputToken,
                            outputToken: vars.logData.outputToken,
                            inputAmount: vars.logData.inputAmount,
                            outputAmount: vars.logData.outputAmount,
                            originChainId: vars.originChainId,
                            depositId: uint32(uint256(args.logs[i].topics[1])),
                            fillDeadline: vars.logData.fillDeadline,
                            exclusivityDeadline: vars.logData.exclusivityDeadline,
                            message: vars.logData.message
                        }),
                        args.refundChainId
                    );
                }
            }
        }
        vm.stopBroadcast();
        vm.selectFork(vars.prevForkId);
    }

    function _decodeLogData(Vm.Log memory log) internal pure returns (AcrossV3LogData memory data) {
        (
            address inputToken,
            address outputToken,
            uint256 inputAmount,
            uint256 outputAmount,
            uint32 quoteTimestamp,
            uint32 fillDeadline,
            uint32 exclusivityDeadline,
            address recipient,
            address exclusiveRelayer,
            bytes memory message
        ) = abi.decode(log.data, (address, address, uint256, uint256, uint32, uint32, uint32, address, address, bytes));
        return AcrossV3LogData({
            inputToken: inputToken,
            outputToken: outputToken,
            inputAmount: inputAmount,
            outputAmount: outputAmount,
            quoteTimestamp: quoteTimestamp,
            fillDeadline: fillDeadline,
            exclusivityDeadline: exclusivityDeadline,
            recipient: recipient,
            exclusiveRelayer: exclusiveRelayer,
            message: message
        });
    }
}
