// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import {IExternalCallExecutor} from "./interfaces/IExternalCallExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDlnDestination, Order} from "./interfaces/IDlnDestination.sol";

/// @title Debridge DLN Helper
/// @notice helps simulate Debridge DLN message relaying with hooks
contract DebridgeDlnHelper is Test {
    bytes32 constant DlnOrderCreated = keccak256(
        "CreatedOrder((uint64,bytes,uint256,bytes,uint256,uint256,bytes,uint256,bytes,bytes,bytes,bytes,bytes,bytes),bytes32,bytes,uint256,uint256,uint32,bytes)"
    );

    address constant TAKER_ADDRESS = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;

    struct HelpArgs {
        address dlnSource;
        address dlnDestination;
        uint256 forkId;
        uint256 destinationChainId;
        bytes32 eventSelector;
        Vm.Log[] logs;
    }

    struct DebridgeLogData {
        Order order;
        bytes32 orderId;
        bytes affiliateFee;
        uint256 nativeFixFee;
        uint256 percentFee;
        uint32 reeferralCode;
        bytes metadata;
    }

    struct HelpLocalVars {
        uint256 prevForkId;
        uint256 originChainId;
        address dlnDestination;
        address takerAddress;
        address unlockAuthority;
        uint256 fulfillAmount;
        address tokenAddress;
        bytes permitEnvelope;
        uint256 msgValue;
        DebridgeLogData logData;
        Order order;
        bytes32 orderId;
        bytes affiliateFee;
        uint256 nativeFixFee;
        uint256 percentFee;
        uint32 reeferralCode;
        bytes metadata;
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////
    /// @notice helps process multiple destination messages to relay
    /// @param dlnSource represents the source deBridge DLN
    /// @param dlnDestinations represents the destination deBridge DLNs
    /// @param forkIds represents the destination chain fork ids
    /// @param destinationChainIds represents the destination chain ids
    /// @param logs represents the recorded message logs
    function help(
        address dlnSource,
        address[] memory dlnDestinations,
        uint256[] memory forkIds,
        uint256[] memory destinationChainIds,
        Vm.Log[] calldata logs
    ) external {
        uint256 chains = destinationChainIds.length;
        for (uint256 i; i < chains;) {
            _help(
                HelpArgs({
                    dlnSource: dlnSource,
                    dlnDestination: dlnDestinations[i],
                    forkId: forkIds[i],
                    destinationChainId: destinationChainIds[i],
                    eventSelector: DlnOrderCreated,
                    logs: logs
                })
            );
            unchecked {
                ++i;
            }
        }
    }
    /// @notice helps process multiple destination messages to relay
    /// @param dlnSource represents the source deBridge gate
    /// @param dlnDestinations represents the destination deBridge gate
    /// @param forkIds represents the destination chain fork ids
    /// @param destinationChainIds represents the destination chain ids
    /// @param eventSelector represents a custom event selector
    /// @param logs represents the recorded message logs

    function help(
        address dlnSource,
        address[] memory dlnDestinations,
        uint256[] memory forkIds,
        uint256[] memory destinationChainIds,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        uint256 chains = destinationChainIds.length;
        for (uint256 i; i < chains;) {
            _help(
                HelpArgs({
                    dlnSource: dlnSource,
                    dlnDestination: dlnDestinations[i],
                    forkId: forkIds[i],
                    destinationChainId: destinationChainIds[i],
                    eventSelector: eventSelector,
                    logs: logs
                })
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @notice helps process single destination message to relay
    /// @param dlnSource represents the source deBridge gate
    /// @param dlnDestination represents the destination deBridge gate
    /// @param forkId represents the destination chain fork id
    /// @param destinationChainId represents the destination chain id
    /// @param logs represents the recorded message logs
    function help(
        address dlnSource,
        address dlnDestination,
        uint256 forkId,
        uint256 destinationChainId,
        Vm.Log[] calldata logs
    ) external {
        _help(
            HelpArgs({
                dlnSource: dlnSource,
                dlnDestination: dlnDestination,
                forkId: forkId,
                destinationChainId: destinationChainId,
                eventSelector: DlnOrderCreated,
                logs: logs
            })
        );
    }

    /// @notice helps process single destination message to relay
    /// @param dlnSource represents the source deBridge gate
    /// @param dlnDestination represents the destination deBridge gate
    /// @param forkId represents the destination chain fork id
    /// @param destinationChainId represents the destination chain id
    /// @param eventSelector represents a custom event selector
    /// @param logs represents the recorded message logs
    function help(
        address dlnSource,
        address dlnDestination,
        uint256 forkId,
        uint256 destinationChainId,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        _help(
            HelpArgs({
                dlnSource: dlnSource,
                dlnDestination: dlnDestination,
                forkId: forkId,
                destinationChainId: destinationChainId,
                eventSelector: eventSelector,
                logs: logs
            })
        );
    }

    /// @notice internal function to process a single destination message to relay
    /// @param args represents the help arguments
    function _help(HelpArgs memory args) internal {
        HelpLocalVars memory vars;
        vars.originChainId = uint256(block.chainid);
        vars.prevForkId = vm.activeFork();
        vars.dlnDestination = args.dlnDestination;
        vars.takerAddress = TAKER_ADDRESS;
        vars.unlockAuthority = vars.takerAddress; // Initially set unlockAuthority to takerAddress
        vars.permitEnvelope = ""; // Always empty now
        vars.msgValue = 0; // Initialize msgValue to 0

        uint256 count = args.logs.length;
        for (uint256 i; i < count;) {
            if (args.logs[i].emitter == args.dlnSource && args.logs[i].topics[0] == args.eventSelector) {
                (
                    vars.order,
                    vars.orderId,
                    vars.affiliateFee,
                    vars.nativeFixFee,
                    vars.percentFee,
                    vars.reeferralCode,
                    vars.metadata
                ) = abi.decode(args.logs[i].data, (Order, bytes32, bytes, uint256, uint256, uint32, bytes));

                if (vars.order.takeChainId == args.destinationChainId) {
                    vm.selectFork(args.forkId);

                    DebridgeLogData memory logData = DebridgeLogData({
                        order: vars.order,
                        orderId: vars.orderId,
                        affiliateFee: vars.affiliateFee,
                        nativeFixFee: vars.nativeFixFee,
                        percentFee: vars.percentFee,
                        reeferralCode: vars.reeferralCode,
                        metadata: vars.metadata
                    });
                    vars.logData = logData;
                    vars.fulfillAmount = vars.order.takeAmount;
                    vars.tokenAddress = address(bytes20(vars.order.takeTokenAddress));

                    if (vars.tokenAddress == address(0)) {
                        // Native token transfer
                        vars.msgValue = vars.fulfillAmount;
                        vm.deal(vars.takerAddress, vars.takerAddress.balance + vars.msgValue);
                    } else {
                        // ERC20 token transfer - Use approve instead of permit
                        // Ensure taker has the tokens
                        deal(vars.tokenAddress, vars.takerAddress, vars.fulfillAmount);
                        // Prank as taker to approve the DlnDestination contract
                        vm.prank(vars.takerAddress);
                        IERC20(vars.tokenAddress).approve(vars.dlnDestination, vars.fulfillAmount);
                    }

                    vm.prank(vars.takerAddress, vars.takerAddress);
                    IDlnDestination(vars.dlnDestination).fulfillOrder{value: vars.msgValue}(
                        vars.order,
                        vars.fulfillAmount,
                        vars.orderId,
                        vars.permitEnvelope,
                        vars.unlockAuthority,
                        vars.takerAddress
                    );

                    vm.selectFork(vars.prevForkId);
                }
            }

            unchecked {
                ++i;
            }
        }

        if (vm.activeFork() != vars.prevForkId) {
            vm.selectFork(vars.prevForkId);
        }
    }
}
