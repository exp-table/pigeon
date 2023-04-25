// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "src/axelar/AxelarHelper.sol";

interface IAxelarGateway {
    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external;
}

contract Target {
    uint256 public value;

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        value = abi.decode(payload, (uint256));
    }
}

contract AnotherTarget {
    uint256 public value;
    address public kevin;
    bytes32 public bob;

    string expectedChain;

    constructor(string memory _expectedChain) {
        expectedChain = _expectedChain;
    }

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        require(
            keccak256(abi.encodePacked(sourceChain)) ==
                keccak256(abi.encodePacked(expectedChain)),
            "Unexpected origin"
        );
        (value, kevin, bob) = abi.decode(payload, (uint256, address, bytes32));
    }
}

contract AxelarHelperTest is Test {
    AxelarHelper axelarHelper;
    Target target;
    Target altTarget;

    AnotherTarget anotherTarget;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    uint256 CROSS_CHAIN_MESSAGE = UINT256_MAX;

    string constant L1_CHAIN_ID = "ethereum";
    string constant L2_1_CHAIN_ID = "polygon";
    string constant L2_2_CHAIN_ID = "arbitrum";

    address constant L1_GATEWAY = 0x4F4495243837681061C4743b74B3eEdf548D56A5;
    address constant POLYGON_GATEWAY =
        0x6f015F16De9fC8791b234eF68D486d2bF203FBA8;
    address constant ARBITRUM_GATEWAY =
        0xe432150cce91c13a887f7D836923d5597adD8E31;

    address[] public allDstTargets;
    address[] public allDstGateways;
    string[] public allDstChainIds;
    uint256[] public allDstForks;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 16400467);
        axelarHelper = new AxelarHelper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET, 38063686);
        target = new Target();
        anotherTarget = new AnotherTarget(L1_CHAIN_ID);

        ARBITRUM_FORK_ID = vm.createSelectFork(RPC_ARBITRUM_MAINNET, 38063686);
        altTarget = new Target();

        allDstTargets.push(address(target));
        allDstTargets.push(address(altTarget));

        allDstChainIds.push(L2_1_CHAIN_ID);
        allDstChainIds.push(L2_2_CHAIN_ID);

        allDstForks.push(POLYGON_FORK_ID);
        allDstForks.push(ARBITRUM_FORK_ID);

        allDstGateways.push(POLYGON_GATEWAY);
        allDstGateways.push(ARBITRUM_GATEWAY);
    }

    function testSimpleAxelar() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract(
            L2_1_CHAIN_ID,
            toString(address(target))
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        axelarHelper.help(POLYGON_GATEWAY, POLYGON_FORK_ID, logs);

        vm.selectFork(POLYGON_FORK_ID);
        console.log(target.value());
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    // function testSimpleCelerWithEstimates() external {
    //     vm.selectFork(L1_FORK_ID);

    //     vm.recordLogs();
    //     _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

    //     Vm.Log[] memory logs = vm.getRecordedLogs();
    //     celerHelper.helpWithEstimates(
    //         L1_CHAIN_ID,
    //         L1_CelerMessageBus,
    //         POLYGON_CelerMessageBus,
    //         L2_1_CHAIN_ID,
    //         POLYGON_FORK_ID,
    //         logs
    //     );

    //     vm.selectFork(POLYGON_FORK_ID);
    //     assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    // }

    // function testFancyCeler() external {
    //     vm.selectFork(L1_FORK_ID);

    //     vm.recordLogs();
    //     _aMoreFancyCrossChainFunctionInYourContract(
    //         L2_1_CHAIN_ID,
    //         address(anotherTarget)
    //     );

    //     Vm.Log[] memory logs = vm.getRecordedLogs();
    //     celerHelper.helpWithEstimates(
    //         L1_CHAIN_ID,
    //         L1_CelerMessageBus,
    //         POLYGON_CelerMessageBus,
    //         L2_1_CHAIN_ID,
    //         POLYGON_FORK_ID,
    //         logs
    //     );

    //     vm.selectFork(POLYGON_FORK_ID);
    //     assertEq(anotherTarget.value(), 12);
    //     assertEq(anotherTarget.kevin(), msg.sender);
    //     assertEq(anotherTarget.bob(), keccak256("bob"));
    // }

    // function testCustomOrderingCeler() external {
    //     vm.selectFork(L1_FORK_ID);

    //     vm.recordLogs();

    //     _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));
    //     _someCrossChainFunctionInYourContract(L2_1_CHAIN_ID, address(target));

    //     Vm.Log[] memory logs = vm.getRecordedLogs();
    //     Vm.Log[] memory CelerLogs = celerHelper.findLogs(logs, 2);
    //     Vm.Log[] memory reorderedLogs = new Vm.Log[](2);

    //     reorderedLogs[0] = CelerLogs[1];
    //     reorderedLogs[1] = CelerLogs[0];

    //     celerHelper.help(
    //         L1_CHAIN_ID,
    //         L1_CelerMessageBus,
    //         POLYGON_CelerMessageBus,
    //         L2_1_CHAIN_ID,
    //         POLYGON_FORK_ID,
    //         reorderedLogs
    //     );

    //     vm.selectFork(POLYGON_FORK_ID);
    //     assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    // }

    // function testMultiDstCeler() external {
    //     vm.selectFork(L1_FORK_ID);
    //     vm.recordLogs();

    //     _manyCrossChainFunctionInYourContract(
    //         [L2_1_CHAIN_ID, L2_2_CHAIN_ID],
    //         [address(target), address(altTarget)]
    //     );

    //     Vm.Log[] memory logs = vm.getRecordedLogs();

    //     celerHelper.help(
    //         L1_CHAIN_ID,
    //         L1_CelerMessageBus,
    //         allDstMessageBus,
    //         allDstChainIds,
    //         allDstForks,
    //         logs
    //     );

    //     vm.selectFork(POLYGON_FORK_ID);
    //     assertEq(target.value(), CROSS_CHAIN_MESSAGE);

    //     vm.selectFork(ARBITRUM_FORK_ID);
    //     assertEq(altTarget.value(), CROSS_CHAIN_MESSAGE);
    // }

    // function _manyCrossChainFunctionInYourContract(
    //     uint64[2] memory dstChainIds,
    //     address[2] memory receivers
    // ) internal {
    //     IMessageBus bus = IMessageBus(L1_CelerMessageBus);

    //     for (uint256 i = 0; i < dstChainIds.length; i++) {
    //         bus.sendMessage{value: 2 ether}(
    //             receivers[i],
    //             dstChainIds[i],
    //             abi.encode(CROSS_CHAIN_MESSAGE)
    //         );
    //     }
    // }

    function _someCrossChainFunctionInYourContract(
        string memory dstChain,
        string memory receiver
    ) internal {
        IAxelarGateway gateway = IAxelarGateway(L1_GATEWAY);

        gateway.callContract(
            dstChain,
            receiver,
            abi.encode(CROSS_CHAIN_MESSAGE)
        );
    }

    // function _aMoreFancyCrossChainFunctionInYourContract(
    //     uint64 dstChainId,
    //     address receiver
    // ) internal {
    //     IMessageBus bus = IMessageBus(L1_CelerMessageBus);
    //     bus.sendMessage{value: 2 ether}(
    //         receiver,
    //         dstChainId,
    //         abi.encode(uint256(12), msg.sender, keccak256("bob"))
    //     );
    // }

    function toString(address addr) internal pure returns (string memory) {
        bytes memory addressBytes = abi.encodePacked(addr);
        uint256 length = addressBytes.length;
        bytes memory characters = "0123456789abcdef";
        bytes memory stringBytes = new bytes(2 + addressBytes.length * 2);

        stringBytes[0] = "0";
        stringBytes[1] = "x";

        for (uint256 i; i < length; ++i) {
            stringBytes[2 + i * 2] = characters[uint8(addressBytes[i] >> 4)];
            stringBytes[3 + i * 2] = characters[uint8(addressBytes[i] & 0x0f)];
        }
        return string(stringBytes);
    }
}
