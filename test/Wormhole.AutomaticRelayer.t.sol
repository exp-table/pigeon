// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
import "src/wormhole/automatic-relayer/WormholeHelper.sol";
import "src/wormhole/specialized-relayer/lib/IWormhole.sol";
import "solady/src/tokens/ERC20.sol";

interface IWormholeRelayerSend {
    struct MessageKey {
        uint8 keyType;
        bytes encodedKey;
    }

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence);

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundAddress
    ) external payable returns (uint64 sequence);

    function sendVaasToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        VaaKey[] memory vaaKeys
    ) external payable returns (uint64 sequence);

    function sendToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 paymentForExtraReceiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundAddress,
        address deliveryProviderAddress,
        MessageKey[] memory messageKeys,
        uint8 consistencyLevel
    ) external payable returns (uint64 sequence);

    function quoteEVMDeliveryPrice(uint16 targetChain, uint256 receiverValue, uint256 gasLimit)
        external
        view
        returns (uint256 nativePriceQuote, uint256 targetChainRefundPerGasUnused);

    function getDefaultDeliveryProvider() external view returns (address);
}

interface IWormholeRelayer is IWormholeRelayerSend {}

interface ITokenManager {
    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller
    ) external returns (uint64 nonce);
}

contract Target is IWormholeReceiver {
    uint256 public value;

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, /*additionalVaas*/
        bytes32, /*sourceAddress*/
        uint16, /*sourceChain*/
        bytes32 /*deliveryHash*/
    ) external payable {
        value = abi.decode(payload, (uint256));
    }
}

contract AdditionalVAATarget is IWormholeReceiver {
    uint256 public value;
    uint256 public vaalen;

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalVaas,
        bytes32, /*sourceAddress*/
        uint16, /*sourceChain*/
        bytes32 /*deliveryHash*/
    ) external payable {
        value = abi.decode(payload, (uint256));
        vaalen = additionalVaas.length;
    }
}

contract AnotherTarget {
    uint256 public value;
    address public kevin;
    bytes32 public bob;

    uint16 expectedChainId;

    constructor(uint16 _expectedChainId) {
        expectedChainId = _expectedChainId;
    }

    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, /*additionalVaas*/
        bytes32, /*sourceAddress*/
        uint16 sourceChain,
        bytes32 /*deliveryHash*/
    ) external payable {
        require(sourceChain == expectedChainId, "Unexpected origin");
        (value, kevin, bob) = abi.decode(payload, (uint256, address, bytes32));
    }
}

contract CCTPTarget {
    IMessageTransmitter transmitter;

    constructor(IMessageTransmitter transmitter_) {
        transmitter = transmitter_;
    }

    function receiveWormholeMessages(
        bytes memory, /*payload*/
        bytes[] memory additionalVaas,
        bytes32, /*sourceAddress*/
        uint16, /*sourceChain*/
        bytes32 /*deliveryHash*/
    ) external payable {
        (bytes memory message, bytes memory attestation) = abi.decode(additionalVaas[0], (bytes, bytes));
        transmitter.receiveMessage(message, attestation);
    }
}

contract WormholeAutomaticRelayerHelperTest is Test {
    IWormhole wormhole = IWormhole(0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B);
    ITokenManager tokenMessenger = ITokenManager(0xBd3fa81B58Ba92a82136038B25aDec7066af3155);
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 USDC_POLYGON = ERC20(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);

    WormholeHelper wormholeHelper;
    Target target;
    Target altTarget;
    CCTPTarget cctpTarget;

    AnotherTarget anotherTarget;
    AdditionalVAATarget addVaaTarget;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint256 CROSS_CHAIN_MESSAGE = UINT256_MAX;

    uint16 constant L1_CHAIN_ID = 2;
    uint16 constant L2_1_CHAIN_ID = 5;
    uint16 constant L2_2_CHAIN_ID = 23;

    address constant L1_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address constant L2_1_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;
    address constant L2_2_RELAYER = 0x27428DD2d3DD32A4D7f7C497eAaa23130d894911;

    address constant MESSAGE_TRANSMITTER_POLYGON = 0xF3be9355363857F3e001be68856A2f96b4C39Ba9;

    address[] public allDstRelayers;
    uint16[] public allDstChainIds;
    uint256[] public allDstForks;
    address[] public allDstTargets;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    receive() external payable {}

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET);
        wormholeHelper = new WormholeHelper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET);
        target = new Target();
        addVaaTarget = new AdditionalVAATarget();
        anotherTarget = new AnotherTarget(L1_CHAIN_ID);
        cctpTarget = new CCTPTarget(IMessageTransmitter(MESSAGE_TRANSMITTER_POLYGON));

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 38063686);
        altTarget = new Target();

        allDstChainIds.push(L2_1_CHAIN_ID);
        allDstChainIds.push(L2_2_CHAIN_ID);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstRelayers.push(L2_1_RELAYER);
        allDstRelayers.push(L2_2_RELAYER);

        allDstTargets.push(address(target));
        allDstTargets.push(address(altTarget));

        console.log(address(target));
        console.log(address(altTarget));
    }

    /// @dev is a normal cross-chain message
    function testSimpleWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_1_RELAYER, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev is a fancy cross-chain message
    function testFancyWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _aMoreFancyCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(anotherTarget));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_2_RELAYER, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(anotherTarget.value(), 12);
        assertEq(anotherTarget.kevin(), msg.sender);
        assertEq(anotherTarget.bob(), keccak256("bob"));
    }

    /// @dev test event log re-ordering
    function testCustomOrderingWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();

        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));
        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log[] memory WormholeLogs = wormholeHelper.findLogs(logs, 2);
        Vm.Log[] memory reorderedLogs = new Vm.Log[](2);

        reorderedLogs[0] = WormholeLogs[1];
        reorderedLogs[1] = WormholeLogs[0];

        wormholeHelper.help(L1_CHAIN_ID, POLYGON_FORK_ID, L2_1_RELAYER, reorderedLogs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev test multi-dst wormhole helper
    function testMultiDstWormhole() external {
        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();

        _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));
        _someCrossChainFunctionInYourContract(L2_2_CHAIN_ID, address(altTarget));

        Vm.Log[] memory logs = vm.getRecordedLogs();

        wormholeHelper.help(L1_CHAIN_ID, allDstForks, allDstTargets, allDstRelayers, logs);

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(altTarget.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev test multi-dst wormhole helper with additional VAAs
    function testMultiDstWormholeWithAdditionalVAA() external {
        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();

        _aMostFancyCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(addVaaTarget));

        uint256[] memory dstForkId = new uint256[](1);
        dstForkId[0] = POLYGON_FORK_ID;

        address[] memory dstAddress = new address[](1);
        dstAddress[0] = address(addVaaTarget);

        address[] memory dstRelayers = new address[](1);
        dstRelayers[0] = L2_1_RELAYER;

        address[] memory dstWormhole = new address[](1);
        dstWormhole[0] = 0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7;

        wormholeHelper.helpWithAdditionalVAA(
            L1_CHAIN_ID, dstForkId, dstAddress, dstRelayers, dstWormhole, vm.getRecordedLogs()
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(addVaaTarget.value(), CROSS_CHAIN_MESSAGE);
        assertEq(addVaaTarget.vaalen(), 1);
    }

    /// @dev test single dst cctp transfers with wormhole
    function testCctpWormhole() external {
        vm.selectFork(L1_FORK_ID);
        address bridgoor = address(32145);

        vm.deal(bridgoor, 2 ether);
        deal(address(USDC), bridgoor, 100e6);
        vm.startPrank(bridgoor);

        USDC.approve(address(tokenMessenger), 100e6);

        vm.recordLogs();
        uint64 nonce = tokenMessenger.depositForBurnWithCaller(
            100e6,
            7,
            bytes32(uint256(uint160(address(cctpTarget)))),
            address(USDC),
            bytes32(uint256(uint160(address(cctpTarget))))
        );

        IWormholeRelayer relayer = IWormholeRelayer(L1_RELAYER);

        IWormholeRelayerSend.MessageKey[] memory messageKeys = new IWormholeRelayerSend.MessageKey[](1);
        messageKeys[0] = IWormholeRelayerSend.MessageKey(2, abi.encodePacked(uint32(7), nonce));

        (uint256 msgValue,) = relayer.quoteEVMDeliveryPrice(L2_1_CHAIN_ID, 0, 500000);

        relayer.sendToEvm{value: msgValue}(
            L2_1_CHAIN_ID,
            address(cctpTarget),
            bytes(""),
            0,
            0,
            500000,
            L2_1_CHAIN_ID,
            address(0),
            relayer.getDefaultDeliveryProvider(),
            messageKeys,
            1
        );

        wormholeHelper.helpWithCctpAndWormhole(
            L1_CHAIN_ID,
            POLYGON_FORK_ID,
            address(cctpTarget),
            L2_1_RELAYER,
            0xF3be9355363857F3e001be68856A2f96b4C39Ba9,
            vm.getRecordedLogs()
        );
        vm.stopPrank();

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(USDC_POLYGON.balanceOf(address(cctpTarget)), 100e6);
    }

    function _aMostFancyCrossChainFunctionInYourContract(uint16 dstChainId, address receiver) internal {
        IWormholeRelayer relayer = IWormholeRelayer(L1_RELAYER);

        (uint256 msgValue,) = relayer.quoteEVMDeliveryPrice(dstChainId, 0, 500000);

        uint64 sequence = wormhole.publishMessage{value: wormhole.messageFee()}(0, abi.encode(CROSS_CHAIN_MESSAGE), 0);

        VaaKey[] memory vaaKeys = new VaaKey[](1);
        vaaKeys[0] = VaaKey(L1_CHAIN_ID, TypeCasts.addressToBytes32(address(this)), sequence);

        relayer.sendVaasToEvm{value: msgValue}(
            dstChainId, receiver, abi.encode(CROSS_CHAIN_MESSAGE), 0, 500000, vaaKeys
        );
    }

    function _aMoreFancyCrossChainFunctionInYourContract(uint16 dstChainId, address receiver) internal {
        IWormholeRelayer relayer = IWormholeRelayer(L1_RELAYER);

        (uint256 msgValue,) = relayer.quoteEVMDeliveryPrice(dstChainId, 0, 500000);

        relayer.sendPayloadToEvm{value: msgValue}(
            dstChainId,
            receiver,
            abi.encode(uint256(12), msg.sender, keccak256("bob")),
            0,
            500000,
            L1_CHAIN_ID,
            address(this)
        );
    }

    function _someCrossChainFunctionInYourContract(uint16 dstChainId, address receiver) internal {
        IWormholeRelayer relayer = IWormholeRelayer(L1_RELAYER);

        (uint256 msgValue,) = relayer.quoteEVMDeliveryPrice(dstChainId, 0, 500000);

        relayer.sendPayloadToEvm{value: msgValue}(
            dstChainId, receiver, abi.encode(CROSS_CHAIN_MESSAGE), 0, 500000, L1_CHAIN_ID, address(this)
        );
    }
}
