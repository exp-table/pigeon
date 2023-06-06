// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "src/axelar/AxelarHelper.sol";
import "src/axelar/lib/AddressHelper.sol";

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
            AddressHelper.toString(address(target))
        );

        Vm.Log[] memory logs = vm.getRecordedLogs();
        axelarHelper.help(
            L1_CHAIN_ID,
            POLYGON_GATEWAY,
            L2_1_CHAIN_ID,
            POLYGON_FORK_ID,
            logs
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

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
}
