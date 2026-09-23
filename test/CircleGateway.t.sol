// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {CircleGatewayHelper} from "src/circle-gateway/CircleGatewayHelper.sol";
import {IGatewayMinter} from "src/circle-gateway/interfaces/IGatewayMinter.sol";
import {IERC20} from "src/circle-gateway/interfaces/IERC20.sol";

/// @dev destination adapter standing in for Superform's CircleGatewayAdapter: it is the spec's
///      destinationRecipient + destinationCaller, calls gatewayMint itself, then forwards the minted delta to
///      the account named in hookData
contract MockGatewayAdapter {
    address public immutable minter;
    address public immutable usdc;
    uint256 public lastMinted;
    bytes public lastHookData;

    constructor(address _minter, address _usdc) {
        minter = _minter;
        usdc = _usdc;
    }

    function receiveAndExecute(bytes calldata attestationPayload, bytes calldata signature) external {
        uint256 before = IERC20(usdc).balanceOf(address(this));
        IGatewayMinter(minter).gatewayMint(attestationPayload, signature);
        lastMinted = IERC20(usdc).balanceOf(address(this)) - before;
        /// TransferSpec.hookData: absolute offset 40 (attestation header) + 340 (spec header) for a single attestation
        lastHookData = attestationPayload[380:];
        (address account) = abi.decode(lastHookData, (address));
        IERC20(usdc).transfer(account, lastMinted);
    }
}

contract CircleGatewayHelperTest is Test {
    CircleGatewayHelper helper;

    uint256 L1_FORK_ID;
    uint256 ARBITRUM_FORK_ID;

    address constant L1_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant ARBITRUM_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    uint32 constant DOMAIN_ETH = 0;
    uint32 constant DOMAIN_ARBITRUM = 3;

    address constant DEPOSITOR = address(0xDE905);
    address constant ACCOUNT = address(0xCAFE);
    address constant CALLER = address(0xCA11E5);

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        ARBITRUM_FORK_ID = vm.createFork(RPC_ARBITRUM_MAINNET);
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET);
        helper = new CircleGatewayHelper(0);
        /// the helper must exist on both forks (fork state is not shared)
        vm.makePersistent(address(helper));
    }

    /// @dev the wire format is right iff the minter marks EXACTLY our hash used
    function testGatewayMintDirect() external {
        helper.helpDeposit(L1_FORK_ID, L1_USDC, DEPOSITOR, 1000e6);
        assertEq(IERC20(L1_USDC).balanceOf(helper.GATEWAY_WALLET()) >= 1000e6, true, "deposited into GatewayWallet");

        CircleGatewayHelper.TransferSpec memory spec = helper.buildSpec(
            DOMAIN_ETH, DOMAIN_ARBITRUM, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, address(0), 1000e6, ""
        );
        CircleGatewayHelper.Attested memory attested = helper.help(ARBITRUM_FORK_ID, spec);

        assertEq(vm.activeFork(), L1_FORK_ID, "fork restored");
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1000e6, "USDC minted to the recipient on Arbitrum");
        assertEq(attested.transferSpecHashes.length, 1);
        assertTrue(
            IGatewayMinter(helper.GATEWAY_MINTER()).isTransferSpecHashUsed(attested.transferSpecHashes[0]),
            "minter marked our hand-encoded spec hash: encoding matches Circle"
        );
        assertEq(attested.transferSpecHashes[0], helper.transferSpecHash(spec));
    }

    function testGatewayMintPinnedCaller() external {
        CircleGatewayHelper.TransferSpec memory spec = helper.buildSpec(
            DOMAIN_ETH, DOMAIN_ARBITRUM, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, CALLER, 5e6, hex"c0ffee"
        );
        helper.help(ARBITRUM_FORK_ID, spec);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 5e6, "minted from the pinned caller");
    }

    function testGatewayMintViaAdapter() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        MockGatewayAdapter adapter = new MockGatewayAdapter(helper.GATEWAY_MINTER(), ARBITRUM_USDC);
        vm.selectFork(L1_FORK_ID);

        CircleGatewayHelper.TransferSpec memory spec = helper.buildSpec(
            DOMAIN_ETH,
            DOMAIN_ARBITRUM,
            L1_USDC,
            ARBITRUM_USDC,
            DEPOSITOR,
            address(adapter),
            address(adapter),
            250e6,
            abi.encode(ACCOUNT)
        );
        helper.helpMintViaAdapter(ARBITRUM_FORK_ID, address(adapter), spec);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(adapter.lastMinted(), 250e6, "adapter measured the mint");
        assertEq(keccak256(adapter.lastHookData()), keccak256(abi.encode(ACCOUNT)), "hookData reached the adapter");
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 250e6, "forwarded to the account");
    }

    function testGatewayMintSet() external {
        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](2);
        specs[0] =
            helper.buildSpec(DOMAIN_ETH, DOMAIN_ARBITRUM, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, CALLER, 3e6, "");
        specs[1] =
            helper.buildSpec(DOMAIN_ETH, DOMAIN_ARBITRUM, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, CALLER, 4e6, "");
        CircleGatewayHelper.Attested memory attested = helper.helpSet(ARBITRUM_FORK_ID, specs);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 7e6, "both members minted atomically");
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        assertTrue(minter.isTransferSpecHashUsed(attested.transferSpecHashes[0]));
        assertTrue(minter.isTransferSpecHashUsed(attested.transferSpecHashes[1]));
    }

    /// @dev attest-only: the test drives gatewayMint itself and sees the minter's own replay protection
    function testAttestOnly_ReplayRejectedByMinter() external {
        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](1);
        specs[0] = helper.buildSpec(
            DOMAIN_ETH, DOMAIN_ARBITRUM, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, address(0), 1e6, ""
        );
        CircleGatewayHelper.Attested memory attested = helper.attest(ARBITRUM_FORK_ID, specs);
        assertEq(vm.activeFork(), L1_FORK_ID, "attest restores the fork");

        vm.selectFork(ARBITRUM_FORK_ID);
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        minter.gatewayMint(attested.payload, attested.signature);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1e6);

        vm.expectRevert(abi.encodeWithSignature("TransferSpecHashUsed(bytes32)", attested.transferSpecHashes[0]));
        minter.gatewayMint(attested.payload, attested.signature);
    }

    function testWrongSigner_RejectedByMinter() external {
        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](1);
        specs[0] = helper.buildSpec(
            DOMAIN_ETH, DOMAIN_ARBITRUM, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, address(0), 1e6, ""
        );
        CircleGatewayHelper.Attested memory attested = helper.attest(ARBITRUM_FORK_ID, specs);

        vm.selectFork(ARBITRUM_FORK_ID);
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(attested.payload)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(0xBAD), digest);
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        vm.expectRevert(abi.encodeWithSignature("InvalidAttestationSigner()"));
        minter.gatewayMint(attested.payload, abi.encodePacked(r, s, v));
    }
}
