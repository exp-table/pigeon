// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import {IDebridgeGate} from "./interfaces/IDebridgeGate.sol";
import {DeBridgeSignatureVerifierMock} from "./mocks/DeBridgeSignatureVerifierMock.sol";

/// @title Debridge Helper
/// @notice helps simulate Debridge message relaying
contract DebridgeHelper is Test {
    bytes32 constant DebridgeSend = keccak256(
        "Sent(bytes32,bytes32,uint256,bytes,uint256,uint256,uint32,(uint256,uint256,uint256,bool,bool),bytes,address)"
    );

    struct HelpArgs {
        address srcGate;
        address dstGate;
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
        bytes32 submissionId;
        bytes32 debridgeId;
        uint256 amount;
        bytes receiver;
        uint256 nonce;
        uint256 chainIdTo;
        uint32 referralCode;
        IDebridgeGate.FeeParams feeParams;
        bytes autoParams;
        address nativeSender;
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////
    /// @notice helps process multiple destination messages to relay
    /// @param srcGate represents the source deBridge gate
    /// @param dstGates represents the destination deBridge gates
    /// @param forkIds represents the destination chain fork ids
    /// @param destinationChainIds represents the destination chain ids
    /// @param debridgeGateAdmins represents the admin of the debridge gate
    /// @param logs represents the recorded message logs
    function help(
        address srcGate,
        address[] memory dstGates,
        uint256[] memory forkIds,
        uint256[] memory destinationChainIds,
        address[] memory debridgeGateAdmins,
        Vm.Log[] calldata logs
    ) external {
        uint256 chains = destinationChainIds.length;
        for (uint256 i; i < chains;) {
            _help(
                HelpArgs({
                    srcGate: srcGate,
                    dstGate: dstGates[i],
                    forkId: forkIds[i],
                    destinationChainId: destinationChainIds[i],
                    eventSelector: DebridgeSend,
                    logs: logs
                }),
                debridgeGateAdmins[i]
            );
            unchecked {
                ++i;
            }
        }
    }
    /// @notice helps process multiple destination messages to relay
    /// @param srcGate represents the source deBridge gate
    /// @param dstGates represents the destination deBridge gate
    /// @param forkIds represents the destination chain fork ids
    /// @param destinationChainIds represents the destination chain ids
    /// @param debridgeGateAdmins represents the admin of the debridge gate
    /// @param eventSelector represents a custom event selector
    /// @param logs represents the recorded message logs

    function help(
        address srcGate,
        address[] memory dstGates,
        uint256[] memory forkIds,
        uint256[] memory destinationChainIds,
        address[] memory debridgeGateAdmins,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        uint256 chains = destinationChainIds.length;
        for (uint256 i; i < chains;) {
            _help(
                HelpArgs({
                    srcGate: srcGate,
                    dstGate: dstGates[i],
                    forkId: forkIds[i],
                    destinationChainId: destinationChainIds[i],
                    eventSelector: eventSelector,
                    logs: logs
                }),
                debridgeGateAdmins[i]
            );
            unchecked {
                ++i;
            }
        }
    }

    /// @notice helps process single destination message to relay
    /// @param debridgeGateAdmin represents the admin of the debridge gate
    /// @param srcGate represents the source deBridge gate
    /// @param dstGate represents the destination deBridge gate
    /// @param forkId represents the destination chain fork id
    /// @param destinationChainId represents the destination chain id
    /// @param logs represents the recorded message logs
    function help(
        address debridgeGateAdmin,
        address srcGate,
        address dstGate,
        uint256 forkId,
        uint256 destinationChainId,
        Vm.Log[] calldata logs
    ) external {
        _help(
            HelpArgs({
                srcGate: srcGate,
                dstGate: dstGate,
                forkId: forkId,
                destinationChainId: destinationChainId,
                eventSelector: DebridgeSend,
                logs: logs
            }),
            debridgeGateAdmin
        );
    }

    /// @notice helps process single destination message to relay
    /// @param debridgeGateAdmin represents the admin of the debridge gate
    /// @param srcGate represents the source deBridge gate
    /// @param dstGate represents the destination deBridge gate
    /// @param forkId represents the destination chain fork id
    /// @param destinationChainId represents the destination chain id
    /// @param eventSelector represents a custom event selector
    /// @param logs represents the recorded message logs
    function help(
        address debridgeGateAdmin,
        address srcGate,
        address dstGate,
        uint256 forkId,
        uint256 destinationChainId,
        bytes32 eventSelector,
        Vm.Log[] calldata logs
    ) external {
        _help(
            HelpArgs({
                srcGate: srcGate,
                dstGate: dstGate,
                forkId: forkId,
                destinationChainId: destinationChainId,
                eventSelector: eventSelector,
                logs: logs
            }),
            debridgeGateAdmin
        );
    }

    /// @notice internal function to process a single destination message to relay
    /// @param args represents the help arguments
    function _help(HelpArgs memory args, address debridgeGateAdmin) internal {
        LocalVars memory vars;
        vars.originChainId = uint256(block.chainid);
        vars.prevForkId = vm.activeFork();

        uint256 count = args.logs.length;
        for (uint256 i; i < count;) {
            // https://docs.debridge.finance/the-debridge-messaging-protocol/development-guides/building-an-evm-based-dapp/evm-smart-contract-interfaces
            // DeBridgeSend is the event selector for the Sent event emitted by the DeBridge gate contract
            // Requests must be filled using the `.claim()` function of the DeBridge gate contract.
            if (args.logs[i].topics[0] == args.eventSelector && args.logs[i].emitter == args.srcGate) {
                vm.selectFork(args.forkId);
                vars.destinationChainId = uint256(args.logs[i].topics[2]);

                if (vars.destinationChainId == args.destinationChainId) {
                    DebridgeLogData memory logData =
                        _decodeLogData(args.logs[i], args.logs[i].topics[1], vars.destinationChainId);
                    vars.logData = logData;

                    // simulate signature verification
                    // -- create verification contract
                    DeBridgeSignatureVerifierMock _verifier = new DeBridgeSignatureVerifierMock();
                    // -- need to overwrite the signature verifier address
                    vm.startPrank(debridgeGateAdmin);
                    IDebridgeGate(args.dstGate).setSignatureVerifier(address(_verifier));
                    vm.stopPrank();

                    IDebridgeGate.DebridgeInfo memory debridgeInfo =
                        IDebridgeGate(args.dstGate).getDebridge(logData.debridgeId);
                    deal(debridgeInfo.tokenAddress, args.dstGate, logData.amount);

                    address receiver = address(bytes20(logData.receiver));
                    IDebridgeGate(args.dstGate).claim(
                        logData.debridgeId,
                        logData.amount,
                        vars.originChainId,
                        receiver,
                        logData.nonce,
                        "",
                        logData.autoParams
                    );
                }
            }

            unchecked {
                ++i;
            }
        }

        vm.selectFork(vars.prevForkId);
    }

    function _decodeLogData(Vm.Log memory log, bytes32 debridgeId, uint256 chainIdTo)
        internal
        pure
        returns (DebridgeLogData memory data)
    {
        (
            bytes32 submissionId,
            uint256 amount,
            bytes memory receiver,
            uint256 nonce,
            uint32 referralCode,
            IDebridgeGate.FeeParams memory feeParams,
            bytes memory autoParams,
            address nativeSender
        ) = abi.decode(log.data, (bytes32, uint256, bytes, uint256, uint32, IDebridgeGate.FeeParams, bytes, address));

        return DebridgeLogData({
            submissionId: submissionId,
            debridgeId: debridgeId,
            amount: amount,
            receiver: receiver,
            nonce: nonce,
            chainIdTo: chainIdTo,
            referralCode: referralCode,
            feeParams: feeParams,
            autoParams: autoParams,
            nativeSender: nativeSender
        });
    }
}
