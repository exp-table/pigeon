// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";

/// local imports
import "src/wormhole/specialized-relayer/lib/IWormhole.sol";
import "src/wormhole/specialized-relayer/WormholeHelper.sol";

contract Target {
    uint256 public value;
    IWormhole public wormhole;

    constructor(IWormhole _wormhole) {
        wormhole = _wormhole;
    }

    function receiveMessage(bytes memory encodedMessage) public {
        // call the Wormhole core contract to parse and verify the encodedMessage
        (IWormhole.VM memory wormholeMessage, bool valid, string memory reason) =
            wormhole.parseAndVerifyVM(encodedMessage);
        // do security checks and set value
        require(valid);
        value = abi.decode(wormholeMessage.payload, (uint256));
    }
}

contract WormholeSpecializedRelayerHelperTest is Test {
    WormholeHelper wormholeHelper;
    Target target;

    uint32 nonce;

    uint256 L1_FORK_ID;
    uint256 POLYGON_FORK_ID;

    uint256 CROSS_CHAIN_MESSAGE = UINT256_MAX;

    uint16 L1_CHAIN_ID = 2;
    uint16 L2_1_CHAIN_ID = 5;

    address constant L1_CORE = 0x98f3c9e6E3fAce36bAAd05FE09d375Ef1464288B;
    address constant L2_1_CORE = 0x7A4B5a56256163F07b2C80A7cA55aBE66c4ec4d7;

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    receive() external payable {}

    function setUp() external {
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET);
        wormholeHelper = new WormholeHelper();

        POLYGON_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET);
        target = new Target(IWormhole(L2_1_CORE));
    }

    /// @dev is a simple cross-chain message
    function testSimpleWormhole() external {
        vm.selectFork(L1_FORK_ID);

        vm.recordLogs();
        _someCrossChainFunctionInYourContract();

        wormholeHelper.help(
            L1_CHAIN_ID, L2_1_CHAIN_ID, POLYGON_FORK_ID, L2_1_CORE, address(target), vm.getRecordedLogs()
        );

        vm.selectFork(POLYGON_FORK_ID);
        assertEq(target.value(), CROSS_CHAIN_MESSAGE);
    }

    /// @dev is a simple cross-chain message to be published by wormhole
    function _someCrossChainFunctionInYourContract() internal {
        IWormhole wormhole = IWormhole(L1_CORE);

        /// @dev publish a new message
        ++nonce;

        /// @dev by sending `0` in the last argument, we get instant finality
        /// @notice should use your optimal finality in development
        wormhole.publishMessage{value: wormhole.messageFee()}(nonce, abi.encode(CROSS_CHAIN_MESSAGE), 0);
    }
}
