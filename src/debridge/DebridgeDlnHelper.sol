// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import {IExternalCallExecutor} from "./interfaces/IExternalCallExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IDlnDestination, Order} from "./interfaces/IDlnDestination.sol";

/// @title Debridge DLN Helper
/// @notice helps simulate Debridge DLN message relaying with hooks
contract DebridgeDlnHelper is Test {
    bytes32 constant DlnOrderCreated = keccak256(
        "CreatedOrder((uint64,bytes,uint256,bytes,uint256,uint256,bytes,uint256,bytes,bytes,bytes,bytes,bytes,bytes),bytes32,bytes,uint256,uint256,uint32,bytes)"
    );

    address constant TAKER_ADDRESS = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;
    uint256 constant TAKER_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    struct HelpArgs {
        address dlnSource;
        address dlnDestination;
        uint256 forkId;
        uint256 destinationChainId;
        bytes32 eventSelector;
        Vm.Log[] logs;
    }

    struct LocalVars {
        uint256 prevForkId;
        uint256 originChainId;
        uint256 destinationChainId;
        DebridgeLogData logData;
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
        LocalVars memory vars;
        vars.originChainId = uint256(block.chainid);
        vars.prevForkId = vm.activeFork();

        uint256 count = args.logs.length;
        for (uint256 i; i < count;) {
            if (args.logs[i].emitter == args.dlnSource && args.logs[i].topics[0] == args.eventSelector) {
                (
                    Order memory order,
                    bytes32 orderId,
                    bytes memory affiliateFee,
                    uint256 nativeFixFee,
                    uint256 percentFee,
                    uint32 reeferralCode,
                    bytes memory metadata
                ) = abi.decode(args.logs[i].data, (Order, bytes32, bytes, uint256, uint256, uint32, bytes));

                if (order.takeChainId == args.destinationChainId) {
                    vm.selectFork(args.forkId);

                    DebridgeLogData memory logData = DebridgeLogData({
                        order: order,
                        orderId: orderId,
                        affiliateFee: affiliateFee,
                        nativeFixFee: nativeFixFee,
                        percentFee: percentFee,
                        reeferralCode: reeferralCode,
                        metadata: metadata
                    });
                    vars.logData = logData;

                    address dlnDestinationAddress = args.dlnDestination;
                    address takerAddress = TAKER_ADDRESS;
                    address unlockAuthority = takerAddress;
                    uint256 fulfillAmount = order.takeAmount;
                    address tokenAddress = address(bytes20(order.takeTokenAddress));
                    bytes memory permitEnvelope;
                    uint256 msgValue = 0;

                    if (tokenAddress == address(0)) {
                        msgValue = fulfillAmount;
                        vm.deal(takerAddress, takerAddress.balance + msgValue);
                    } else {
                        vm.deal(tokenAddress, takerAddress, fulfillAmount);
                        bytes32 domainSeparator = IERC20Permit(tokenAddress).DOMAIN_SEPARATOR();
                        uint256 nonce = IERC20Permit(tokenAddress).nonces(takerAddress);
                        uint256 deadline = block.timestamp + 1 hours;

                        bytes32 permitStructHash = keccak256(
                            abi.encode(
                                PERMIT_TYPEHASH, takerAddress, dlnDestinationAddress, fulfillAmount, nonce, deadline
                            )
                        );

                        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitStructHash));

                        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TAKER_PRIVATE_KEY, digest);

                        permitEnvelope = abi.encodePacked(r, s, v);
                    }

                    vm.prank(takerAddress, takerAddress);
                    IDlnDestination(dlnDestinationAddress).fulfillOrder{value: msgValue}(
                        order, fulfillAmount, orderId, permitEnvelope, unlockAuthority, address(0)
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
