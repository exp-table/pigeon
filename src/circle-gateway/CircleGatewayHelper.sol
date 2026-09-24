// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

/// library imports
import "forge-std/Test.sol";
import {IGatewayMinter} from "./interfaces/IGatewayMinter.sol";
import {IGatewayWallet} from "./interfaces/IGatewayWallet.sol";
import {IGatewayAttestationReceiver} from "./interfaces/IGatewayAttestationReceiver.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/// @title Circle Gateway Helper
/// @notice helps simulate Circle Gateway (unified USDC balance) mints on a destination fork
/// @dev Gateway differs structurally from CCTP: there is NO on-chain source message to relay. The user
///      deposits into GatewayWallet, signs a BurnIntent off-chain, and Circle's API returns an
///      EIP-191-signed Attestation (or AttestationSet) that anyone submits to GatewayMinter.gatewayMint on
///      the destination; the source-side burn happens afterwards. So this helper cannot derive anything
///      from logs: the caller describes the transfer as a TransferSpec, and the helper (1) enrolls a test
///      attestation signer on the destination minter via its owner, (2) encodes the exact Circle wire
///      format, (3) signs it the way Circle's service does (personal_sign over keccak256(payload), no
///      EIP-712 domain), and (4) either mints directly or hands the payload to an adapter.
/// @dev Wire formats (circlefin/evm-gateway-contracts v1.0.0; `testGatewayMintDirect` proves the mainnet
///      minter accepts this encoding by checking `isTransferSpecHashUsed` on the hand-computed hash):
///      TransferSpec  = magic 0xca85def7 | version u32 | sourceDomain u32 | destinationDomain u32 |
///                      sourceContract b32 | destinationContract b32 | sourceToken b32 | destinationToken b32 |
///                      sourceDepositor b32 | destinationRecipient b32 | sourceSigner b32 | destinationCaller b32 |
///                      value u256 | salt b32 | hookDataLength u32 | hookData
///      Attestation   = magic 0xff6fb334 | maxBlockHeight u256 | transferSpecLength u32 | TransferSpec
///      AttestationSet= magic 0x1e12db71 | numAttestations u32 | Attestation...
///      The minter's replay key is keccak256(TransferSpec bytes) (`isTransferSpecHashUsed`).
/// @dev Everything the minter checks runs for real (signer, expiry, domain, contract, caller, token, replay,
///      denylist, pause, same-domain token equality). What is NOT modeled and cannot be: the off-chain
///      Gateway balance check, the BurnIntent signature, Circle's fee netting and the source-side burn.
///      `helpDeposit` is optional realism and is not linked to `help*`.
/// @dev The helper makes itself persistent in the constructor (it is called from, and mutates, several
///      forks); a reverting destination call restores the previously selected fork before re-raising.
contract CircleGatewayHelper is Test {
    /// @dev Gateway proxies (same addresses on all Gateway chains)
    address public constant GATEWAY_WALLET = 0x77777777Dcc4d5A8B6E418Fd04D8997ef11000eE;
    address public constant GATEWAY_MINTER = 0x2222222d7164433c4C09B0b0D809a9b52C04C205;

    bytes4 public constant TRANSFER_SPEC_MAGIC = 0xca85def7; // bytes4(keccak256("circle.gateway.TransferSpec"))
    bytes4 public constant ATTESTATION_MAGIC = 0xff6fb334; // bytes4(keccak256("circle.gateway.Attestation"))
    bytes4 public constant ATTESTATION_SET_MAGIC = 0x1e12db71; // bytes4(keccak256("circle.gateway.AttestationSet"))
    uint32 public constant TRANSFER_SPEC_VERSION = 1;

    /// @dev attestations stay valid through (inclusive) this many blocks after the destination fork's current
    ///      block; use the `maxBlockHeight` overloads of `helpAttest*` for anything else
    uint256 public constant DEFAULT_VALIDITY_BLOCKS = 1000;

    /// @dev private key used to sign attestations in tests
    uint256 public immutable TEST_SIGNER_PK;

    /// @dev address derived from TEST_SIGNER_PK
    address public immutable testSignerAddress;

    /// @dev makes every generated salt unique across a test run (shared across forks: the helper is persistent)
    uint256 private _saltNonce;

    /// @notice mirrors circlefin's TransferSpec struct (address fields are left-padded to bytes32)
    struct TransferSpec {
        uint32 version;
        uint32 sourceDomain;
        uint32 destinationDomain;
        bytes32 sourceContract;
        bytes32 destinationContract;
        bytes32 sourceToken;
        bytes32 destinationToken;
        bytes32 sourceDepositor;
        bytes32 destinationRecipient;
        bytes32 sourceSigner;
        bytes32 destinationCaller;
        uint256 value;
        bytes32 salt;
        bytes hookData;
    }

    /// @notice what a help call produced, so tests can replay / inspect it
    struct Attested {
        bytes payload;
        bytes signature;
        bytes32[] transferSpecHashes;
    }

    //////////////////////////////////////////////////////////////
    //                      CONSTRUCTOR                         //
    //////////////////////////////////////////////////////////////

    /// @notice creates a helper with a test attestation signer key
    /// @param signerPK the private key used to sign attestations (use 0 for default key 0x1)
    constructor(uint256 signerPK) {
        uint256 pk = signerPK == 0 ? 1 : signerPK;
        TEST_SIGNER_PK = pk;
        testSignerAddress = vm.addr(pk);
        /// the helper is called from and mutates several forks; keep code + _saltNonce visible on all of them
        vm.makePersistent(address(this));
    }

    //////////////////////////////////////////////////////////////
    //                  EXTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @notice attests and mints one TransferSpec on the destination fork through GatewayMinter.gatewayMint
    /// @dev the mint is sent from `spec.destinationCaller` when it is non-zero (the minter enforces it), else
    ///      from this helper; funds land at `spec.destinationRecipient`. Restores the previously selected fork,
    ///      also when the mint reverts (the revert is re-raised unchanged). NOTE: the live minter mints through
    ///      FiatToken's minter allowance, so a value above `USDC.minterAllowance(GATEWAY_MINTER)` (tens of
    ///      millions) reverts with FiatToken's "mint amount exceeds minterAllowance".
    /// @param dstForkId the destination chain fork id (its minter must have `spec.destinationDomain`)
    /// @param spec the transfer to mint
    /// @return result the signed payload and the spec hash the minter marked used
    function help(uint256 dstForkId, TransferSpec memory spec) external returns (Attested memory result) {
        result = _mint(dstForkId, _one(spec), false, address(0));
    }

    /// @notice attests and mints an AttestationSet (several TransferSpecs minted atomically in one call)
    /// @dev always emits the set wire format, even for one member; all members are minted by one gatewayMint
    ///      and the minter itself rejects a set whose members disagree on destinationCaller
    function helpSet(uint256 dstForkId, TransferSpec[] memory specs) external returns (Attested memory result) {
        result = _mint(dstForkId, specs, true, address(0));
    }

    /// @notice attests one TransferSpec and hands it to `adapter.receiveAndExecute(payload, signature)`
    /// @dev models the Superform path: the adapter is expected to be the spec's destinationRecipient and
    ///      destinationCaller (not enforced here; build the spec accordingly), calls gatewayMint itself, and
    ///      acts on `spec.hookData`. No prank: the adapter is the caller of gatewayMint.
    function helpMintViaAdapter(uint256 dstForkId, address adapter, TransferSpec memory spec)
        external
        returns (Attested memory result)
    {
        result = _mint(dstForkId, _one(spec), false, adapter);
    }

    /// @notice attests an AttestationSet and hands it to `adapter.receiveAndExecute(payload, signature)`
    function helpMintViaAdapterSet(uint256 dstForkId, address adapter, TransferSpec[] memory specs)
        external
        returns (Attested memory result)
    {
        result = _mint(dstForkId, specs, true, adapter);
    }

    /// @notice attests one TransferSpec without minting, for tests that drive the destination call themselves
    /// @dev enrolls the test signer on the destination minter and reads block.number there for maxBlockHeight
    function helpAttest(uint256 dstForkId, TransferSpec memory spec) external returns (Attested memory result) {
        result = _attestOnFork(dstForkId, _one(spec), false, 0);
    }

    /// @notice `helpAttest` with an explicit `maxBlockHeight` (destination-chain block height, inclusive)
    function helpAttest(uint256 dstForkId, TransferSpec memory spec, uint256 maxBlockHeight)
        external
        returns (Attested memory result)
    {
        result = _attestOnFork(dstForkId, _one(spec), false, maxBlockHeight);
    }

    /// @notice attests an AttestationSet without minting
    function helpAttestSet(uint256 dstForkId, TransferSpec[] memory specs) external returns (Attested memory result) {
        result = _attestOnFork(dstForkId, specs, true, 0);
    }

    /// @notice `helpAttestSet` with an explicit `maxBlockHeight` shared by all members
    function helpAttestSet(uint256 dstForkId, TransferSpec[] memory specs, uint256 maxBlockHeight)
        external
        returns (Attested memory result)
    {
        result = _attestOnFork(dstForkId, specs, true, maxBlockHeight);
    }

    /// @notice funds `depositor` with `amount` of `token` on the source fork and deposits it into GatewayWallet
    /// @dev optional source-side realism: the destination mint does not depend on it (Circle's service would
    ///      verify the balance off-chain), but tests that assert on `availableBalance` can use it. The wallet's
    ///      own guards apply (token must be Gateway-supported, depositor not denylisted, not paused).
    function helpDeposit(uint256 srcForkId, address token, address depositor, uint256 amount) external {
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(srcForkId);
        deal(token, depositor, amount);
        vm.startPrank(depositor);
        require(IERC20(token).approve(GATEWAY_WALLET, amount), "CircleGatewayHelper: approve failed");
        try IGatewayWallet(GATEWAY_WALLET).deposit(token, amount) {}
        catch (bytes memory reason) {
            vm.stopPrank();
            vm.selectFork(prevForkId);
            _rethrow(reason);
        }
        vm.stopPrank();
        vm.selectFork(prevForkId);
    }

    /// @notice convenience builder: fills version, the canonical Gateway contracts and a unique salt
    /// @param srcDomain Gateway domain of the source chain (Ethereum 0, Avalanche 1, OP 2, Arbitrum 3, Base 6,
    ///        Polygon 7, Unichain 10, Sonic 13, World Chain 14 — read from `minter.domain()` on-chain)
    /// @param dstDomain Gateway domain of the destination chain (must equal the destination minter's `domain()`)
    /// @param srcToken the token on the source chain (must equal dstToken when srcDomain == dstDomain)
    /// @param dstToken the token to mint on the destination chain
    /// @param depositor the source depositor (also used as sourceSigner)
    /// @param recipient who receives the minted funds
    /// @param destinationCaller who may submit the attestation (address(0) = anyone)
    /// @param value amount to mint
    /// @param hookData arbitrary bytes for on-chain composition (ignored by the minter)
    function buildSpec(
        uint32 srcDomain,
        uint32 dstDomain,
        address srcToken,
        address dstToken,
        address depositor,
        address recipient,
        address destinationCaller,
        uint256 value,
        bytes memory hookData
    ) external returns (TransferSpec memory spec) {
        spec = TransferSpec({
            version: TRANSFER_SPEC_VERSION,
            sourceDomain: srcDomain,
            destinationDomain: dstDomain,
            sourceContract: bytes32(uint256(uint160(GATEWAY_WALLET))),
            destinationContract: bytes32(uint256(uint160(GATEWAY_MINTER))),
            sourceToken: bytes32(uint256(uint160(srcToken))),
            destinationToken: bytes32(uint256(uint160(dstToken))),
            sourceDepositor: bytes32(uint256(uint160(depositor))),
            destinationRecipient: bytes32(uint256(uint160(recipient))),
            sourceSigner: bytes32(uint256(uint160(depositor))),
            destinationCaller: bytes32(uint256(uint160(destinationCaller))),
            value: value,
            salt: keccak256(abi.encode("pigeon.circle-gateway", address(this), ++_saltNonce)),
            hookData: hookData
        });
    }

    //////////////////////////////////////////////////////////////
    //                  ENCODING (PURE / VIEW)                  //
    //////////////////////////////////////////////////////////////

    /// @notice encodes a TransferSpec exactly as circlefin's TransferSpecLib does
    function encodeTransferSpec(TransferSpec memory spec) public pure returns (bytes memory) {
        require(spec.hookData.length <= type(uint32).max, "CircleGatewayHelper: hookData too large");
        /// two halves: a single 16-argument encodePacked overflows the stack (Circle's lib splits the same way)
        bytes memory head = abi.encodePacked(
            TRANSFER_SPEC_MAGIC,
            spec.version,
            spec.sourceDomain,
            spec.destinationDomain,
            spec.sourceContract,
            spec.destinationContract,
            spec.sourceToken,
            spec.destinationToken
        );
        bytes memory tail = abi.encodePacked(
            spec.sourceDepositor,
            spec.destinationRecipient,
            spec.sourceSigner,
            spec.destinationCaller,
            spec.value,
            spec.salt,
            uint32(spec.hookData.length),
            spec.hookData
        );
        return bytes.concat(head, tail);
    }

    /// @notice the minter's replay key for a spec (== AttestationUsed.transferSpecHash)
    function transferSpecHash(TransferSpec memory spec) public pure returns (bytes32) {
        return keccak256(encodeTransferSpec(spec));
    }

    /// @notice encodes a single Attestation
    function encodeAttestation(uint256 maxBlockHeight, TransferSpec memory spec) public pure returns (bytes memory) {
        bytes memory encodedSpec = encodeTransferSpec(spec);
        return abi.encodePacked(ATTESTATION_MAGIC, maxBlockHeight, uint32(encodedSpec.length), encodedSpec);
    }

    /// @notice encodes an AttestationSet (all members share `maxBlockHeight`)
    function encodeAttestationSet(uint256 maxBlockHeight, TransferSpec[] memory specs)
        public
        pure
        returns (bytes memory payload)
    {
        payload = abi.encodePacked(ATTESTATION_SET_MAGIC, uint32(specs.length));
        for (uint256 i; i < specs.length; ++i) {
            payload = bytes.concat(payload, encodeAttestation(maxBlockHeight, specs[i]));
        }
    }

    /// @notice signs a payload the way Circle's attestation service does: EIP-191 personal_sign over
    ///         keccak256(payload) (NOT EIP-712 — that is the burn-intent path on GatewayWallet)
    function signAttestation(bytes memory payload) public view returns (bytes memory signature) {
        bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(payload)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_SIGNER_PK, digest);
        signature = abi.encodePacked(r, s, v);
    }

    //////////////////////////////////////////////////////////////
    //                  INTERNAL FUNCTIONS                      //
    //////////////////////////////////////////////////////////////

    /// @dev attests on the destination fork, then mints directly (adapter == 0) or via the adapter; a reverting
    ///      destination call restores the previous fork and re-raises the same revert data
    function _mint(uint256 dstForkId, TransferSpec[] memory specs, bool asSet, address adapter)
        internal
        returns (Attested memory result)
    {
        _validate(specs, asSet); // before any fork switch, so a bad input never strands the caller
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(dstForkId);
        _setupTestSigner();
        result = _attest(specs, asSet, block.number + DEFAULT_VALIDITY_BLOCKS);

        if (adapter != address(0)) {
            try IGatewayAttestationReceiver(adapter).receiveAndExecute(result.payload, result.signature) {}
            catch (bytes memory reason) {
                vm.selectFork(prevForkId);
                _rethrow(reason);
            }
        } else {
            /// the minter enforces msg.sender == destinationCaller when it is set
            address caller = address(uint160(uint256(specs[0].destinationCaller)));
            if (caller != address(0)) vm.prank(caller);
            try IGatewayMinter(GATEWAY_MINTER).gatewayMint(result.payload, result.signature) {}
            catch (bytes memory reason) {
                vm.selectFork(prevForkId);
                _rethrow(reason);
            }
        }

        vm.selectFork(prevForkId);
    }

    /// @dev attest-only entry: enrolls the signer on the destination fork and reads its block.number
    function _attestOnFork(uint256 dstForkId, TransferSpec[] memory specs, bool asSet, uint256 maxBlockHeight)
        internal
        returns (Attested memory result)
    {
        _validate(specs, asSet);
        uint256 prevForkId = vm.activeFork();
        vm.selectFork(dstForkId);
        _setupTestSigner();
        if (maxBlockHeight == 0) maxBlockHeight = block.number + DEFAULT_VALIDITY_BLOCKS;
        result = _attest(specs, asSet, maxBlockHeight);
        vm.selectFork(prevForkId);
    }

    /// @dev encodes (single Attestation or AttestationSet, as requested) and signs
    function _attest(TransferSpec[] memory specs, bool asSet, uint256 maxBlockHeight)
        internal
        view
        returns (Attested memory result)
    {
        _validate(specs, asSet);
        result.payload =
            asSet ? encodeAttestationSet(maxBlockHeight, specs) : encodeAttestation(maxBlockHeight, specs[0]);
        result.signature = signAttestation(result.payload);
        result.transferSpecHashes = new bytes32[](specs.length);
        for (uint256 i; i < specs.length; ++i) {
            result.transferSpecHashes[i] = transferSpecHash(specs[i]);
        }
    }

    /// @dev enrolls the test signer on the destination minter (owner-only; production signers stay enabled,
    ///      each attestation needs just one valid signer)
    function _setupTestSigner() internal {
        IGatewayMinter minter = IGatewayMinter(GATEWAY_MINTER);
        if (!minter.isAttestationSigner(testSignerAddress)) {
            vm.prank(minter.owner());
            minter.addAttestationSigner(testSignerAddress);
        }
    }

    /// @dev input checks shared by every entrypoint; runs before any fork switch
    function _validate(TransferSpec[] memory specs, bool asSet) internal pure {
        require(specs.length != 0, "CircleGatewayHelper: empty set");
        require(asSet || specs.length == 1, "CircleGatewayHelper: single attestation takes one spec");
    }

    function _one(TransferSpec memory spec) internal pure returns (TransferSpec[] memory specs) {
        specs = new TransferSpec[](1);
        specs[0] = spec;
    }

    /// @dev re-raises revert data unchanged
    function _rethrow(bytes memory reason) internal pure {
        assembly {
            revert(add(reason, 32), mload(reason))
        }
    }
}
