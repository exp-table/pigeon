// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import {IExternalCallExecutor} from "./interfaces/IExternalCallExecutor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Debridge DLN Helper
/// @notice helps simulate Debridge DLN message relaying with hooks
contract DebridgeDlnHelper is Test {
    bytes32 constant DlnOrderCreated = keccak256(
        "CreatedOrder((uint64,bytes,uint256,bytes,uint256,uint256,bytes,uint256,bytes,bytes,bytes,bytes,bytes,bytes),bytes32,bytes,uint256,uint256,uint32,bytes)"
    );

    address constant TAKER_ADDRESS = 0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf;

    /// @dev  Struct representing an order.
    struct Order {
        /// Nonce for each maker.
        uint64 makerOrderNonce;
        /// Order maker address (EOA signer for EVM) in the source chain.
        bytes makerSrc;
        /// Chain ID where the order's was created.
        uint256 giveChainId;
        /// Address of the ERC-20 token that the maker is offering as part of this order.
        /// Use the zero address to indicate that the maker is offering a native blockchain token (such as Ether, Matic, etc.).
        bytes giveTokenAddress;
        /// Amount of tokens the maker is offering.
        uint256 giveAmount;
        // the ID of the chain where an order should be fulfilled.
        uint256 takeChainId;
        /// Address of the ERC-20 token that the maker is willing to accept on the destination chain.
        bytes takeTokenAddress;
        /// Amount of tokens the maker is willing to accept on the destination chain.
        uint256 takeAmount;
        /// Address on the destination chain where funds should be sent upon order fulfillment.
        bytes receiverDst;
        /// Address on the source (current) chain authorized to patch the order by adding more input tokens, making it more attractive to takers.
        bytes givePatchAuthoritySrc;
        /// Address on the destination chain authorized to patch the order by reducing the take amount, making it more attractive to takers,
        /// and can also cancel the order in the take chain.
        bytes orderAuthorityAddressDst;
        // An optional address restricting anyone in the open market from fulfilling
        // this order but the given address. This can be useful if you are creating a order
        // for a specific taker. By default, set to empty bytes array (0x)
        bytes allowedTakerDst;
        // An optional address on the source (current) chain where the given input tokens
        // would be transferred to in case order cancellation is initiated by the orderAuthorityAddressDst
        // on the destination chain. This property can be safely set to an empty bytes array (0x):
        // in this case, tokens would be transferred to the arbitrary address specified
        // by the orderAuthorityAddressDst upon order cancellation
        bytes allowedCancelBeneficiarySrc;
        /// An optional external call data payload.
        bytes externalCall;
    }

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

    interface IDlnDestination {
        function fulfillOrder(
            Order memory _order,
            uint256 _fulFillAmount,
            bytes32 _orderId,
            bytes calldata _permitEnvelope,
            address _unlockAuthority,
            address _externalCallRewardBeneficiary
        ) external payable;
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
                    bytes memory permitEnvelope = "";
                    uint256 msgValue = 0;

                    if (tokenAddress == address(0)) {
                        msgValue = fulfillAmount;
                        vm.deal(takerAddress, takerAddress.balance + msgValue);
                    } else {
                        vm.deal(tokenAddress, takerAddress, fulfillAmount);
                        vm.prank(takerAddress);
                        IERC20(tokenAddress).approve(dlnDestinationAddress, fulfillAmount);
                    }

                    vm.prank(takerAddress, takerAddress);
                    IDlnDestination(dlnDestinationAddress).fulfillOrder{value: msgValue}(
                        order,
                        fulfillAmount,
                        orderId,
                        permitEnvelope,
                        unlockAuthority,
                        address(0)
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
