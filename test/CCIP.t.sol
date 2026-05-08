// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {Client} from "src/ccip/interfaces/Client.sol";
import {IRouterClient} from "src/ccip/interfaces/IRouterClient.sol";
import {IAny2EVMMessageReceiver} from "src/ccip/interfaces/IAny2EVMMessageReceiver.sol";

import {CcipHelper} from "src/ccip/CcipHelper.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

interface IERC165 {
    function supportsInterface(bytes4) external view returns (bool);
}

contract Target is IAny2EVMMessageReceiver, IERC165 {
    bytes32 public lastMessageId;
    uint64 public lastSourceChainSelector;
    address public lastSender;
    bytes public lastData;
    address public lastToken;
    uint256 public lastAmount;
    uint256 public callCount;

    function ccipReceive(Client.Any2EVMMessage calldata m) external override {
        lastMessageId = m.messageId;
        lastSourceChainSelector = m.sourceChainSelector;
        lastSender = abi.decode(m.sender, (address));
        lastData = m.data;
        if (m.destTokenAmounts.length == 1) {
            lastToken = m.destTokenAmounts[0].token;
            lastAmount = m.destTokenAmounts[0].amount;
        }
        callCount += 1;
    }

    function supportsInterface(bytes4 id) external pure override returns (bool) {
        return id == type(IAny2EVMMessageReceiver).interfaceId || id == type(IERC165).interfaceId;
    }
}

contract CcipHelperTest is Test {
    CcipHelper ccipHelper;
    Target target;
    Target altTarget;

    uint256 ETH_FORK_ID;
    uint256 ARB_FORK_ID;

    uint64 constant ETH_CHAIN_SELECTOR = 5009297550715157269;
    uint64 constant ARB_CHAIN_SELECTOR = 4949039107694359620;

    address constant ETH_ROUTER = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    address constant ARB_ROUTER = 0x141fa059441E0ca23ce184B6A78bafD2A517DdE8;

    address constant LINK_ETH = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant USDC_ETH = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDC_ARB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    string RPC_ETH = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_ARB = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        // Pinned to recent post-CCIP-1.6 cutover blocks. Adjust if RPC pruning rejects the height.
        ETH_FORK_ID = vm.createSelectFork(RPC_ETH, 23_000_000);
        ccipHelper = new CcipHelper();

        ARB_FORK_ID = vm.createSelectFork(RPC_ARB, 380_000_000);
        target = new Target();
        altTarget = new Target();
    }

    function testSimpleCCIP() external {
        vm.selectFork(ETH_FORK_ID);

        vm.recordLogs();
        // ||
        // ||
        // \/ This is the part of the code you could copy to use the CcipHelper
        //    in your own tests.
        _ccipSendDataOnly(ARB_CHAIN_SELECTOR, address(target), abi.encode(uint256(42)));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        ccipHelper.help(
            CcipHelper.HelpArgs({
                dstForkId: ARB_FORK_ID,
                dstRouter: ARB_ROUTER,
                expDstChainSelector: ARB_CHAIN_SELECTOR,
                srcOnRamp: address(0),
                logs: logs
            })
        );
        // /\
        // ||
        // ||

        vm.selectFork(ARB_FORK_ID);
        assertEq(target.callCount(), 1, "Target.ccipReceive not called");
        assertEq(target.lastSourceChainSelector(), ETH_CHAIN_SELECTOR, "Source selector mismatch");
        assertEq(target.lastSender(), address(this), "Sender mismatch");
        assertEq(abi.decode(target.lastData(), (uint256)), 42, "Data mismatch");
    }

    function testMultiDstCCIP() external {
        vm.selectFork(ETH_FORK_ID);

        vm.recordLogs();
        _ccipSendDataOnly(ARB_CHAIN_SELECTOR, address(target), abi.encode(uint256(1)));
        _ccipSendDataOnly(ARB_CHAIN_SELECTOR, address(altTarget), abi.encode(uint256(2)));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        ccipHelper.help(
            CcipHelper.HelpArgs({
                dstForkId: ARB_FORK_ID,
                dstRouter: ARB_ROUTER,
                expDstChainSelector: ARB_CHAIN_SELECTOR,
                srcOnRamp: address(0),
                logs: logs
            })
        );

        vm.selectFork(ARB_FORK_ID);
        assertEq(target.callCount(), 1);
        assertEq(altTarget.callCount(), 1);
        assertEq(abi.decode(target.lastData(), (uint256)), 1);
        assertEq(abi.decode(altTarget.lastData(), (uint256)), 2);
    }

    function testCCIPWithEstimates() external {
        vm.selectFork(ETH_FORK_ID);

        vm.recordLogs();
        _ccipSendDataOnly(ARB_CHAIN_SELECTOR, address(target), abi.encode(uint256(7)));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        ccipHelper.helpWithEstimates(
            CcipHelper.HelpArgs({
                dstForkId: ARB_FORK_ID,
                dstRouter: ARB_ROUTER,
                expDstChainSelector: ARB_CHAIN_SELECTOR,
                srcOnRamp: address(0),
                logs: logs
            })
        );

        vm.selectFork(ARB_FORK_ID);
        assertEq(target.callCount(), 1);
        assertEq(abi.decode(target.lastData(), (uint256)), 7);
    }

    function testCCIPFundsOnly() external {
        vm.selectFork(ETH_FORK_ID);

        uint256 amount = 100_000_000; // 100 USDC (6 decimals)

        vm.recordLogs();
        _ccipSendWithToken(ARB_CHAIN_SELECTOR, address(target), USDC_ETH, amount, bytes(""));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        ccipHelper.help(
            CcipHelper.HelpArgs({
                dstForkId: ARB_FORK_ID,
                dstRouter: ARB_ROUTER,
                expDstChainSelector: ARB_CHAIN_SELECTOR,
                srcOnRamp: address(0),
                logs: logs
            })
        );

        vm.selectFork(ARB_FORK_ID);
        // funds-only with empty data still goes through routeMessage because gasLimit > 0 in extraArgs;
        // ccipReceive runs and observes the credited destination tokens.
        assertEq(target.callCount(), 1, "Target.ccipReceive not called");
        assertEq(target.lastToken(), USDC_ARB, "destination token mismatch");
        assertEq(target.lastAmount(), amount, "destination amount mismatch");
        assertEq(IERC20(USDC_ARB).balanceOf(address(target)), amount, "target USDC balance mismatch");
        assertEq(target.lastData().length, 0, "expected empty data");
    }

    function testCCIPFundsAndData() external {
        vm.selectFork(ETH_FORK_ID);

        uint256 amount = 50_000_000; // 50 USDC
        bytes memory payload = abi.encode("hello", uint256(7));

        vm.recordLogs();
        _ccipSendWithToken(ARB_CHAIN_SELECTOR, address(target), USDC_ETH, amount, payload);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        ccipHelper.help(
            CcipHelper.HelpArgs({
                dstForkId: ARB_FORK_ID,
                dstRouter: ARB_ROUTER,
                expDstChainSelector: ARB_CHAIN_SELECTOR,
                srcOnRamp: address(0),
                logs: logs
            })
        );

        vm.selectFork(ARB_FORK_ID);
        assertEq(target.callCount(), 1);
        assertEq(target.lastToken(), USDC_ARB);
        assertEq(target.lastAmount(), amount);
        assertEq(IERC20(USDC_ARB).balanceOf(address(target)), amount);
        assertEq(target.lastData(), payload, "data mismatch");
        assertEq(target.lastSender(), address(this));
    }

    function testFindLogsFiltersCCIPMessageSent() external {
        vm.selectFork(ETH_FORK_ID);

        vm.recordLogs();
        _ccipSendDataOnly(ARB_CHAIN_SELECTOR, address(target), abi.encode(uint256(99)));
        Vm.Log[] memory logs = vm.getRecordedLogs();

        Vm.Log[] memory ccipLogs = ccipHelper.findLogs(logs, 1);
        assertEq(ccipLogs.length, 1);
        bytes32 sel = ccipLogs[0].topics[0];
        bool isCcipEvent =
            sel == ccipHelper.CCIP_MESSAGE_SENT_SELECTOR() || sel == ccipHelper.CCIP_SEND_REQUESTED_SELECTOR();
        assertTrue(isCcipEvent, "matched log is not a CCIP event");
    }

    /// @dev Sends a data-only CCIP message paying the fee in LINK.
    function _ccipSendDataOnly(uint64 dstSelector, address receiver, bytes memory data) internal {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: LINK_ETH,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: true})
            )
        });

        uint256 fee = IRouterClient(ETH_ROUTER).getFee(dstSelector, message);
        deal(LINK_ETH, address(this), fee);
        IERC20(LINK_ETH).approve(ETH_ROUTER, fee);

        IRouterClient(ETH_ROUTER).ccipSend(dstSelector, message);
    }

    /// @dev Sends a CCIP message carrying 1 token (and optional data) paying the fee in LINK.
    function _ccipSendWithToken(
        uint64 dstSelector,
        address receiver,
        address token,
        uint256 amount,
        bytes memory data
    ) internal {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: token, amount: amount});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: data,
            tokenAmounts: tokenAmounts,
            feeToken: LINK_ETH,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: 500_000, allowOutOfOrderExecution: true})
            )
        });

        uint256 fee = IRouterClient(ETH_ROUTER).getFee(dstSelector, message);
        deal(LINK_ETH, address(this), fee);
        IERC20(LINK_ETH).approve(ETH_ROUTER, fee);

        deal(token, address(this), amount);
        IERC20(token).approve(ETH_ROUTER, amount);

        IRouterClient(ETH_ROUTER).ccipSend(dstSelector, message);
    }
}
