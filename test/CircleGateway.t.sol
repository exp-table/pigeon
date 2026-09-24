// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";

import {CircleGatewayHelper} from "src/circle-gateway/CircleGatewayHelper.sol";
import {IGatewayMinter} from "src/circle-gateway/interfaces/IGatewayMinter.sol";
import {IGatewayWallet} from "src/circle-gateway/interfaces/IGatewayWallet.sol";
import {IERC20} from "src/circle-gateway/interfaces/IERC20.sol";

/// @dev destination adapter standing in for Superform's CircleGatewayAdapter: it is the spec's
///      destinationRecipient + destinationCaller, calls gatewayMint itself, then forwards the minted delta to
///      the account named in hookData (single attestation) or to a default account (sets)
contract MockGatewayAdapter {
    address public immutable minter;
    address public immutable usdc;
    address public immutable defaultAccount;
    uint256 public lastMinted;
    bytes public lastHookData;

    constructor(address _minter, address _usdc, address _defaultAccount) {
        minter = _minter;
        usdc = _usdc;
        defaultAccount = _defaultAccount;
    }

    function receiveAndExecute(bytes calldata attestationPayload, bytes calldata signature) external {
        uint256 before = IERC20(usdc).balanceOf(address(this));
        IGatewayMinter(minter).gatewayMint(attestationPayload, signature);
        lastMinted = IERC20(usdc).balanceOf(address(this)) - before;
        address account = defaultAccount;
        if (bytes4(attestationPayload[:4]) == 0xff6fb334) {
            /// TransferSpec.hookData: 40 (attestation header) + 340 (spec header) for a single attestation
            lastHookData = attestationPayload[380:];
            account = abi.decode(lastHookData, (address));
        }
        IERC20(usdc).transfer(account, lastMinted);
    }
}

abstract contract CircleGatewayTestBase is Test {
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

    /// @dev known-good bytes produced by circlefin's TransferSpecLib / AttestationLib for FIXED_SPEC (see
    ///      _fixedSpec) with maxBlockHeight 123456 — catches field-order / width regressions without an RPC
    bytes constant VECTOR_SPEC =
        hex"ca85def700000001000000000000000300000000000000000000000077777777dcc4d5a8b6e418fd04d8997ef11000ee0000000000000000000000002222222d7164433c4c09b0b0d809a9b52c04c205000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e583100000000000000000000000000000000000000000000000000000000000de905000000000000000000000000000000000000000000000000000000000000cafe00000000000000000000000000000000000000000000000000000000000de9050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b9aca000000000000000000000000000000000000000000000000000000000000005a1700000003c0ffee";
    bytes constant VECTOR_ATTESTATION =
        hex"ff6fb334000000000000000000000000000000000000000000000000000000000001e24000000157ca85def700000001000000000000000300000000000000000000000077777777dcc4d5a8b6e418fd04d8997ef11000ee0000000000000000000000002222222d7164433c4c09b0b0d809a9b52c04c205000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e583100000000000000000000000000000000000000000000000000000000000de905000000000000000000000000000000000000000000000000000000000000cafe00000000000000000000000000000000000000000000000000000000000de9050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b9aca000000000000000000000000000000000000000000000000000000000000005a1700000003c0ffee";
    bytes constant VECTOR_SET =
        hex"1e12db7100000001ff6fb334000000000000000000000000000000000000000000000000000000000001e24000000157ca85def700000001000000000000000300000000000000000000000077777777dcc4d5a8b6e418fd04d8997ef11000ee0000000000000000000000002222222d7164433c4c09b0b0d809a9b52c04c205000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e583100000000000000000000000000000000000000000000000000000000000de905000000000000000000000000000000000000000000000000000000000000cafe00000000000000000000000000000000000000000000000000000000000de9050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003b9aca000000000000000000000000000000000000000000000000000000000000005a1700000003c0ffee";

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_ARBITRUM_MAINNET = vm.envString("ARBITRUM_MAINNET_RPC_URL");

    function setUp() external {
        /// same pins as CctpV2.t.sol so the RPC cache is shared (Gateway is live at both)
        ARBITRUM_FORK_ID = vm.createFork(RPC_ARBITRUM_MAINNET, 459_930_000);
        L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET, 25_035_000);
        helper = new CircleGatewayHelper(0); // persistent across forks by construction
    }

    function _spec(address recipient, address destinationCaller, uint256 value, bytes memory hookData)
        internal
        returns (CircleGatewayHelper.TransferSpec memory)
    {
        return helper.buildSpec(
            DOMAIN_ETH,
            DOMAIN_ARBITRUM,
            L1_USDC,
            ARBITRUM_USDC,
            DEPOSITOR,
            recipient,
            destinationCaller,
            value,
            hookData
        );
    }
}

contract CircleGatewayHelperTest is CircleGatewayTestBase {
    //////////////////////////////////////////////////////////////
    //                       HAPPY PATHS                        //
    //////////////////////////////////////////////////////////////

    /// @dev the wire format is right iff the LIVE minter marks EXACTLY our hand-computed hash used
    function testGatewayMintDirect() external {
        helper.helpDeposit(L1_FORK_ID, L1_USDC, DEPOSITOR, 1000e6);
        assertEq(
            IGatewayWallet(helper.GATEWAY_WALLET()).availableBalance(L1_USDC, DEPOSITOR),
            1000e6,
            "deposit credited the depositor's Gateway balance"
        );

        CircleGatewayHelper.TransferSpec memory spec = _spec(ACCOUNT, address(0), 1000e6, "");
        CircleGatewayHelper.Attested memory attested = helper.help(ARBITRUM_FORK_ID, spec);

        assertEq(vm.activeFork(), L1_FORK_ID, "fork restored");
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1000e6, "USDC minted to the recipient on Arbitrum");
        assertEq(bytes4(attested.payload), helper.ATTESTATION_MAGIC(), "single attestation format");
        assertEq(attested.transferSpecHashes.length, 1);
        /// independent recomputation: the spec slice starts at attestation offset 40
        bytes memory payload = attested.payload;
        bytes memory specBytes = new bytes(payload.length - 40);
        for (uint256 i; i < specBytes.length; ++i) {
            specBytes[i] = payload[40 + i];
        }
        assertEq(attested.transferSpecHashes[0], keccak256(specBytes), "hash is of the spec slice only");
        assertTrue(
            IGatewayMinter(helper.GATEWAY_MINTER()).isTransferSpecHashUsed(attested.transferSpecHashes[0]),
            "minter marked our hand-encoded spec hash: encoding matches Circle"
        );
    }

    function testGatewayMintPinnedCaller() external {
        helper.help(ARBITRUM_FORK_ID, _spec(ACCOUNT, CALLER, 5e6, hex"c0ffee"));

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 5e6, "minted from the pinned caller");
    }

    function testGatewayMintViaAdapter() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        MockGatewayAdapter adapter = new MockGatewayAdapter(helper.GATEWAY_MINTER(), ARBITRUM_USDC, ACCOUNT);
        vm.selectFork(L1_FORK_ID);

        CircleGatewayHelper.TransferSpec memory spec =
            _spec(address(adapter), address(adapter), 250e6, abi.encode(ACCOUNT));
        helper.helpMintViaAdapter(ARBITRUM_FORK_ID, address(adapter), spec);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(adapter.lastMinted(), 250e6, "adapter measured the mint");
        assertEq(keccak256(adapter.lastHookData()), keccak256(abi.encode(ACCOUNT)), "hookData reached the adapter");
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 250e6, "forwarded to the account");
    }

    function testGatewayMintViaAdapterSet() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        MockGatewayAdapter adapter = new MockGatewayAdapter(helper.GATEWAY_MINTER(), ARBITRUM_USDC, ACCOUNT);
        vm.selectFork(L1_FORK_ID);

        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](2);
        specs[0] = _spec(address(adapter), address(adapter), 1e6, "");
        specs[1] = _spec(address(adapter), address(adapter), 2e6, "");
        CircleGatewayHelper.Attested memory attested =
            helper.helpMintViaAdapterSet(ARBITRUM_FORK_ID, address(adapter), specs);

        assertEq(bytes4(attested.payload), helper.ATTESTATION_SET_MAGIC(), "set format");
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(adapter.lastMinted(), 3e6, "both members minted into the adapter atomically");
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 3e6);
    }

    function testGatewayMintSet() external {
        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](2);
        specs[0] = _spec(ACCOUNT, CALLER, 3e6, "");
        specs[1] = _spec(ACCOUNT, CALLER, 4e6, "");
        CircleGatewayHelper.Attested memory attested = helper.helpSet(ARBITRUM_FORK_ID, specs);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 7e6, "both members minted atomically");
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        assertTrue(minter.isTransferSpecHashUsed(attested.transferSpecHashes[0]));
        assertTrue(minter.isTransferSpecHashUsed(attested.transferSpecHashes[1]));
    }

    /// @dev a one-member set must still be emitted as a SET (consumers test their set-parsing branch with it)
    function testGatewaySetOfOneKeepsSetFormat() external {
        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](1);
        specs[0] = _spec(ACCOUNT, address(0), 1e6, "");
        CircleGatewayHelper.Attested memory attested = helper.helpSet(ARBITRUM_FORK_ID, specs);
        assertEq(bytes4(attested.payload), helper.ATTESTATION_SET_MAGIC(), "set magic");
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1e6, "the live minter accepts a set of one");
    }

    //////////////////////////////////////////////////////////////
    //              THE MINTER'S OWN CHECKS RUN                 //
    //////////////////////////////////////////////////////////////

    /// @dev attest-only: the test drives gatewayMint itself and sees the minter's own replay protection
    function testGatewayAttestOnlyReplayRejected() external {
        CircleGatewayHelper.Attested memory attested =
            helper.helpAttest(ARBITRUM_FORK_ID, _spec(ACCOUNT, address(0), 1e6, ""));
        assertEq(vm.activeFork(), L1_FORK_ID, "attest restores the fork");

        vm.selectFork(ARBITRUM_FORK_ID);
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        minter.gatewayMint(attested.payload, attested.signature);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1e6);

        vm.expectRevert(abi.encodeWithSignature("TransferSpecHashUsed(bytes32)", attested.transferSpecHashes[0]));
        minter.gatewayMint(attested.payload, attested.signature);
    }

    function testGatewayWrongSignerRejected() external {
        CircleGatewayHelper.Attested memory attested =
            helper.helpAttest(ARBITRUM_FORK_ID, _spec(ACCOUNT, address(0), 1e6, ""));

        vm.selectFork(ARBITRUM_FORK_ID);
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(attested.payload)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(0xBAD), digest);
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        vm.expectRevert(abi.encodeWithSignature("InvalidAttestationSigner()"));
        minter.gatewayMint(attested.payload, abi.encodePacked(r, s, v));
    }

    /// @dev the prank in help() is what makes a pinned spec mintable: from anyone else the minter rejects it
    function testGatewayPinnedCallerEnforcedByMinter() external {
        CircleGatewayHelper.Attested memory attested =
            helper.helpAttest(ARBITRUM_FORK_ID, _spec(ACCOUNT, CALLER, 1e6, ""));

        vm.selectFork(ARBITRUM_FORK_ID);
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        vm.expectRevert(
            abi.encodeWithSignature(
                "InvalidAttestationDestinationCallerAtIndex(uint32,address,address)", 0, CALLER, address(this)
            )
        );
        minter.gatewayMint(attested.payload, attested.signature);
    }

    /// @dev DEFAULT_VALIDITY_BLOCKS is inclusive: +1000 still mints, +1001 is expired
    function testGatewayExpiry() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        uint256 issued = block.number;
        vm.selectFork(L1_FORK_ID);
        CircleGatewayHelper.Attested memory ok =
            helper.helpAttest(ARBITRUM_FORK_ID, _spec(ACCOUNT, address(0), 1e6, ""));
        CircleGatewayHelper.Attested memory stale =
            helper.helpAttest(ARBITRUM_FORK_ID, _spec(ACCOUNT, address(0), 1e6, ""));

        vm.selectFork(ARBITRUM_FORK_ID);
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        vm.roll(issued + helper.DEFAULT_VALIDITY_BLOCKS());
        minter.gatewayMint(ok.payload, ok.signature);

        vm.roll(issued + helper.DEFAULT_VALIDITY_BLOCKS() + 1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "AttestationExpiredAtIndex(uint32,uint256,uint256)",
                0,
                issued + helper.DEFAULT_VALIDITY_BLOCKS(),
                block.number
            )
        );
        minter.gatewayMint(stale.payload, stale.signature);
    }

    /// @dev explicit maxBlockHeight overload
    function testGatewayAttestWithMaxBlockHeight() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        uint256 target = block.number + 5;
        vm.selectFork(L1_FORK_ID);
        CircleGatewayHelper.Attested memory attested =
            helper.helpAttest(ARBITRUM_FORK_ID, _spec(ACCOUNT, address(0), 1e6, ""), target);
        assertEq(uint256(bytes32(_slice(attested.payload, 4, 36))), target, "maxBlockHeight at offset 4");
    }

    /// @dev the minter rejects a set whose members disagree on destinationCaller
    function testGatewayMixedCallerSetRejectedByMinter() external {
        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](2);
        specs[0] = _spec(ACCOUNT, CALLER, 1e6, "");
        specs[1] = _spec(ACCOUNT, address(0xB0B), 1e6, "");
        vm.expectRevert(
            abi.encodeWithSignature(
                "InvalidAttestationDestinationCallerAtIndex(uint32,address,address)", 1, address(0xB0B), CALLER
            )
        );
        helper.helpSet(ARBITRUM_FORK_ID, specs);
    }

    /// @dev a reverting help() must not strand the caller on the destination fork
    function testGatewayRevertRestoresFork() external {
        CircleGatewayHelper.TransferSpec memory zero = _spec(ACCOUNT, address(0), 0, "");
        try helper.help(ARBITRUM_FORK_ID, zero) {
            fail();
        } catch (bytes memory reason) {
            assertEq(bytes4(reason), bytes4(keccak256("AttestationValueMustBePositiveAtIndex(uint32)")));
        }
        assertEq(vm.activeFork(), L1_FORK_ID, "back on the source fork after a revert");
    }

    //////////////////////////////////////////////////////////////
    //                  ENCODING (NO RPC NEEDED)                //
    //////////////////////////////////////////////////////////////

    function _fixedSpec() internal pure returns (CircleGatewayHelper.TransferSpec memory) {
        return CircleGatewayHelper.TransferSpec({
            version: 1,
            sourceDomain: 0,
            destinationDomain: 3,
            sourceContract: bytes32(uint256(uint160(0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE))),
            destinationContract: bytes32(uint256(uint160(0x2222222d7164433c4C09B0b0D809a9b52C04C205))),
            sourceToken: bytes32(uint256(uint160(L1_USDC))),
            destinationToken: bytes32(uint256(uint160(ARBITRUM_USDC))),
            sourceDepositor: bytes32(uint256(0xDE905)),
            destinationRecipient: bytes32(uint256(0xCAFE)),
            sourceSigner: bytes32(uint256(0xDE905)),
            destinationCaller: bytes32(0),
            value: 1000e6,
            salt: bytes32(uint256(0x5A17)),
            hookData: hex"c0ffee"
        });
    }

    /// @dev byte-for-byte against circlefin's libraries (vectors generated with TransferSpecLib/AttestationLib)
    function testGatewayEncodingMatchesCircleLibrary() external view {
        CircleGatewayHelper.TransferSpec memory s = _fixedSpec();
        assertEq(helper.encodeTransferSpec(s), VECTOR_SPEC, "TransferSpec bytes");
        assertEq(helper.encodeTransferSpec(s).length, 340 + 3, "340-byte header + hookData");
        assertEq(helper.encodeAttestation(123_456, s), VECTOR_ATTESTATION, "Attestation bytes");
        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](1);
        specs[0] = s;
        assertEq(helper.encodeAttestationSet(123_456, specs), VECTOR_SET, "AttestationSet bytes");
        assertEq(helper.transferSpecHash(s), keccak256(VECTOR_SPEC), "replay key");
    }

    function testGatewayBuildSpecSaltsAreUnique() external {
        CircleGatewayHelper.TransferSpec memory a = _spec(ACCOUNT, address(0), 1e6, "");
        CircleGatewayHelper.TransferSpec memory b = _spec(ACCOUNT, address(0), 1e6, "");
        assertTrue(a.salt != b.salt, "salts differ");
        assertTrue(helper.transferSpecHash(a) != helper.transferSpecHash(b), "hashes differ");
    }

    function _slice(bytes memory data, uint256 start, uint256 end) internal pure returns (bytes memory out) {
        out = new bytes(end - start);
        for (uint256 i; i < out.length; ++i) {
            out[i] = data[start + i];
        }
    }
}

/// @dev adapter stand-in whose receiveAndExecute can be made to revert with a custom error
contract RevertingGatewayAdapter {
    error AdapterBoom(uint256 code);

    function receiveAndExecute(bytes calldata, bytes calldata) external pure {
        revert AdapterBoom(42);
    }
}

/// @dev live-minter admin surface used only by the edge-case tests
interface IGatewayMinterAdmin {
    function denylister() external view returns (address);
    function denylist(address addr) external;
    function unDenylist(address addr) external;
    function pauser() external view returns (address);
    function pause() external;
    function unpause() external;
    function isAttestationSigner(address signer) external view returns (bool);
}

/// @title edge cases: revert paths restore state, the live minter's remaining checks, fork/persistence behaviour
contract CircleGatewayHelperEdgeCasesTest is CircleGatewayTestBase {
    uint32 constant DOMAIN_BASE = 6;
    address constant L1_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //////////////////////////////////////////////////////////////
    //              REVERT PATHS RESTORE FORK + STATE           //
    //////////////////////////////////////////////////////////////

    /// @dev helpDeposit on a token the wallet does not support: the wallet reverts, the prank is stopped and the
    ///      fork restored, and a subsequent valid deposit still works
    function testGatewayDepositRevertRestoresForkAndPrank() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        try helper.helpDeposit(L1_FORK_ID, L1_WETH, DEPOSITOR, 1 ether) {
            fail();
        } catch {}
        assertEq(vm.activeFork(), ARBITRUM_FORK_ID, "fork restored after a failed deposit");

        helper.helpDeposit(L1_FORK_ID, L1_USDC, DEPOSITOR, 7e6);
        assertEq(vm.activeFork(), ARBITRUM_FORK_ID, "fork restored after a successful deposit");
        vm.selectFork(L1_FORK_ID);
        assertEq(IGatewayWallet(helper.GATEWAY_WALLET()).availableBalance(L1_USDC, DEPOSITOR), 7e6);
    }

    /// @dev a reverting adapter: the exact custom error is re-raised and the fork restored
    function testGatewayAdapterRevertRethrowsAndRestoresFork() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        RevertingGatewayAdapter adapter = new RevertingGatewayAdapter();
        vm.selectFork(L1_FORK_ID);

        CircleGatewayHelper.TransferSpec memory spec = _spec(address(adapter), address(adapter), 1e6, "");
        vm.expectRevert(abi.encodeWithSelector(RevertingGatewayAdapter.AdapterBoom.selector, 42));
        helper.helpMintViaAdapter(ARBITRUM_FORK_ID, address(adapter), spec);
        assertEq(vm.activeFork(), L1_FORK_ID, "fork restored");

        /// the spec was never consumed: nothing minted, hash unused
        vm.selectFork(ARBITRUM_FORK_ID);
        assertFalse(IGatewayMinter(helper.GATEWAY_MINTER()).isTransferSpecHashUsed(helper.transferSpecHash(spec)));
    }

    /// @dev help() called while the DESTINATION fork is already active restores to it
    function testGatewayHelpFromDestinationForkActive() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        helper.help(ARBITRUM_FORK_ID, _spec(ACCOUNT, address(0), 2e6, ""));
        assertEq(vm.activeFork(), ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 2e6);
    }

    function testGatewayEmptySetReverts() external {
        CircleGatewayHelper.TransferSpec[] memory none = new CircleGatewayHelper.TransferSpec[](0);
        vm.expectRevert(bytes("CircleGatewayHelper: empty set"));
        helper.helpSet(ARBITRUM_FORK_ID, none);
        vm.expectRevert(bytes("CircleGatewayHelper: empty set"));
        helper.helpAttestSet(ARBITRUM_FORK_ID, none);
        assertEq(vm.activeFork(), L1_FORK_ID);
    }

    //////////////////////////////////////////////////////////////
    //            THE LIVE MINTER'S REMAINING CHECKS            //
    //////////////////////////////////////////////////////////////

    function testGatewayWrongDestinationDomainRejected() external {
        CircleGatewayHelper.TransferSpec memory spec =
            helper.buildSpec(DOMAIN_ETH, DOMAIN_BASE, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, address(0), 1e6, "");
        vm.expectRevert(
            abi.encodeWithSignature(
                "InvalidAttestationDestinationDomainAtIndex(uint32,uint32,uint32)", 0, DOMAIN_BASE, DOMAIN_ARBITRUM
            )
        );
        helper.help(ARBITRUM_FORK_ID, spec);
        assertEq(vm.activeFork(), L1_FORK_ID);
    }

    function testGatewayUnsupportedTokenRejected() external {
        address notUsdc = address(0xBAD70);
        CircleGatewayHelper.TransferSpec memory spec =
            helper.buildSpec(DOMAIN_ETH, DOMAIN_ARBITRUM, L1_USDC, notUsdc, DEPOSITOR, ACCOUNT, address(0), 1e6, "");
        vm.expectRevert(abi.encodeWithSignature("UnsupportedTokenAtIndex(uint32,address)", 0, notUsdc));
        helper.help(ARBITRUM_FORK_ID, spec);
    }

    /// @dev same-domain transfers must use the same token on both sides; equal tokens mint fine
    function testGatewaySameDomainTokenRule() external {
        CircleGatewayHelper.TransferSpec memory bad = helper.buildSpec(
            DOMAIN_ARBITRUM, DOMAIN_ARBITRUM, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, address(0), 1e6, ""
        );
        vm.expectRevert(
            abi.encodeWithSignature("InvalidAttestationTokenAtIndex(uint32,address,address)", 0, L1_USDC, ARBITRUM_USDC)
        );
        helper.help(ARBITRUM_FORK_ID, bad);

        CircleGatewayHelper.TransferSpec memory good = helper.buildSpec(
            DOMAIN_ARBITRUM, DOMAIN_ARBITRUM, ARBITRUM_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, address(0), 1e6, ""
        );
        helper.help(ARBITRUM_FORK_ID, good);
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1e6, "same-domain mint with equal tokens");
    }

    function testGatewayDenylistedRecipientRejected() external {
        IGatewayMinterAdmin admin = IGatewayMinterAdmin(helper.GATEWAY_MINTER());
        vm.selectFork(ARBITRUM_FORK_ID);
        vm.prank(admin.denylister());
        admin.denylist(ACCOUNT);
        vm.selectFork(L1_FORK_ID);

        CircleGatewayHelper.TransferSpec memory spec = _spec(ACCOUNT, address(0), 1e6, "");
        vm.expectRevert(abi.encodeWithSignature("AccountDenylisted(address)", ACCOUNT));
        helper.help(ARBITRUM_FORK_ID, spec);

        vm.selectFork(ARBITRUM_FORK_ID);
        vm.prank(admin.denylister());
        admin.unDenylist(ACCOUNT);
        vm.selectFork(L1_FORK_ID);
        helper.help(ARBITRUM_FORK_ID, spec);
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1e6, "mints once un-denylisted; same attestation");
    }

    function testGatewayPausedMinterRejected() external {
        IGatewayMinterAdmin admin = IGatewayMinterAdmin(helper.GATEWAY_MINTER());
        vm.selectFork(ARBITRUM_FORK_ID);
        vm.prank(admin.pauser());
        admin.pause();
        vm.selectFork(L1_FORK_ID);

        CircleGatewayHelper.TransferSpec memory spec = _spec(ACCOUNT, address(0), 1e6, "");
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        helper.help(ARBITRUM_FORK_ID, spec);

        vm.selectFork(ARBITRUM_FORK_ID);
        vm.prank(admin.pauser());
        admin.unpause();
        vm.selectFork(L1_FORK_ID);
        helper.help(ARBITRUM_FORK_ID, spec);
        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1e6);
    }

    /// @dev the documented footgun: the live minter mints through FiatToken's minter allowance; a string revert
    ///      from FiatToken is re-raised unchanged
    function testGatewayMinterAllowanceFootgun() external {
        CircleGatewayHelper.TransferSpec memory spec = _spec(ACCOUNT, address(0), 1e30, "");
        vm.expectRevert(bytes("FiatToken: mint amount exceeds minterAllowance"));
        helper.help(ARBITRUM_FORK_ID, spec);
        assertEq(vm.activeFork(), L1_FORK_ID);
    }

    /// @dev expired set via the explicit maxBlockHeight overload; the same error carries the member index
    function testGatewayAttestSetWithMaxBlockHeightExpired() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        uint256 stale = block.number - 1;
        vm.selectFork(L1_FORK_ID);
        CircleGatewayHelper.TransferSpec[] memory specs = new CircleGatewayHelper.TransferSpec[](2);
        specs[0] = _spec(ACCOUNT, address(0), 1e6, "");
        specs[1] = _spec(ACCOUNT, address(0), 1e6, "");
        CircleGatewayHelper.Attested memory attested = helper.helpAttestSet(ARBITRUM_FORK_ID, specs, stale);
        assertEq(bytes4(attested.payload), helper.ATTESTATION_SET_MAGIC());

        vm.selectFork(ARBITRUM_FORK_ID);
        IGatewayMinter minter = IGatewayMinter(helper.GATEWAY_MINTER());
        vm.expectRevert(
            abi.encodeWithSignature("AttestationExpiredAtIndex(uint32,uint256,uint256)", 0, stale, block.number)
        );
        minter.gatewayMint(attested.payload, attested.signature);
    }

    //////////////////////////////////////////////////////////////
    //          DOMAIN 0, SIGNERS, HOOKDATA, PERSISTENCE        //
    //////////////////////////////////////////////////////////////

    /// @dev Ethereum is Gateway domain 0: it works as a DESTINATION too (Arbitrum -> Ethereum)
    function testGatewayEthereumIsDomainZeroDestination() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        CircleGatewayHelper.TransferSpec memory spec = helper.buildSpec(
            DOMAIN_ARBITRUM, DOMAIN_ETH, ARBITRUM_USDC, L1_USDC, DEPOSITOR, ACCOUNT, address(0), 9e6, ""
        );
        CircleGatewayHelper.Attested memory attested = helper.help(L1_FORK_ID, spec);
        assertEq(vm.activeFork(), ARBITRUM_FORK_ID, "restored to the previously active (Arbitrum) fork");

        vm.selectFork(L1_FORK_ID);
        assertEq(IERC20(L1_USDC).balanceOf(ACCOUNT), 9e6, "minted on Ethereum");
        assertTrue(IGatewayMinter(helper.GATEWAY_MINTER()).isTransferSpecHashUsed(attested.transferSpecHashes[0]));
    }

    /// @dev two helpers with different keys each enroll their own signer; both mint on the same minter
    function testGatewayTwoHelpersDistinctSigners() external {
        CircleGatewayHelper other = new CircleGatewayHelper(0xBEEF);
        assertTrue(other.testSignerAddress() != helper.testSignerAddress());

        helper.help(ARBITRUM_FORK_ID, _spec(ACCOUNT, address(0), 1e6, ""));
        other.help(
            ARBITRUM_FORK_ID,
            other.buildSpec(
                DOMAIN_ETH, DOMAIN_ARBITRUM, L1_USDC, ARBITRUM_USDC, DEPOSITOR, ACCOUNT, address(0), 2e6, ""
            )
        );

        vm.selectFork(ARBITRUM_FORK_ID);
        IGatewayMinterAdmin admin = IGatewayMinterAdmin(helper.GATEWAY_MINTER());
        assertTrue(admin.isAttestationSigner(helper.testSignerAddress()));
        assertTrue(admin.isAttestationSigner(other.testSignerAddress()));
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 3e6);
    }

    /// @dev signAttestation recovers to the helper's signer (EIP-191 digest), independently of the minter
    function testGatewaySignatureRecoversToTestSigner() external view {
        bytes memory payload = helper.encodeAttestation(1, _fixedSpecLocal());
        bytes memory sig = helper.signAttestation(payload);
        assertEq(sig.length, 65);
        (bytes32 r, bytes32 s, uint8 v) = _split(sig);
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(payload)));
        assertEq(ecrecover(digest, v, r, s), helper.testSignerAddress(), "EIP-191 over keccak256(payload)");
        assertEq(helper.testSignerAddress(), vm.addr(1), "default key is 0x1");
    }

    /// @dev 4 KB of hookData round-trips through the wire format and the adapter
    function testGatewayLargeHookData() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        MockGatewayAdapter adapter = new MockGatewayAdapter(helper.GATEWAY_MINTER(), ARBITRUM_USDC, ACCOUNT);
        vm.selectFork(L1_FORK_ID);

        bytes memory big = new bytes(4096);
        for (uint256 i; i < big.length; ++i) {
            big[i] = bytes1(uint8(i));
        }
        bytes memory hookData = abi.encode(ACCOUNT, big);
        CircleGatewayHelper.TransferSpec memory spec = _spec(address(adapter), address(adapter), 1e6, hookData);
        assertEq(helper.encodeTransferSpec(spec).length, 340 + hookData.length);
        helper.helpMintViaAdapter(ARBITRUM_FORK_ID, address(adapter), spec);

        vm.selectFork(ARBITRUM_FORK_ID);
        assertEq(keccak256(adapter.lastHookData()), keccak256(hookData), "hookData intact");
        assertEq(IERC20(ARBITRUM_USDC).balanceOf(ACCOUNT), 1e6);
    }

    /// @dev the helper is persistent from construction: usable on a fork it was not deployed on, before any
    ///      help call, and salts stay unique across forks
    function testGatewayPersistentAcrossForksBeforeAnyHelp() external {
        vm.selectFork(ARBITRUM_FORK_ID);
        CircleGatewayHelper.TransferSpec memory a = _spec(ACCOUNT, address(0), 1e6, "");
        vm.selectFork(L1_FORK_ID);
        CircleGatewayHelper.TransferSpec memory b = _spec(ACCOUNT, address(0), 1e6, "");
        assertTrue(a.salt != b.salt, "nonce shared across forks");
        assertEq(helper.transferSpecHash(a), helper.transferSpecHash(a), "pure encoders usable on any fork");
    }

    //////////////////////////////////////////////////////////////
    //                         HELPERS                          //
    //////////////////////////////////////////////////////////////

    function _fixedSpecLocal() internal pure returns (CircleGatewayHelper.TransferSpec memory) {
        return CircleGatewayHelper.TransferSpec({
            version: 1,
            sourceDomain: 0,
            destinationDomain: 3,
            sourceContract: bytes32(uint256(uint160(0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE))),
            destinationContract: bytes32(uint256(uint160(0x2222222d7164433c4C09B0b0D809a9b52C04C205))),
            sourceToken: bytes32(uint256(uint160(L1_USDC))),
            destinationToken: bytes32(uint256(uint160(ARBITRUM_USDC))),
            sourceDepositor: bytes32(uint256(0xDE905)),
            destinationRecipient: bytes32(uint256(0xCAFE)),
            sourceSigner: bytes32(uint256(0xDE905)),
            destinationCaller: bytes32(0),
            value: 1,
            salt: bytes32(uint256(1)),
            hookData: ""
        });
    }

    function _split(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}
