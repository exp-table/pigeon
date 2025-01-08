<img align="right" width="150" height="150" top="100" src="./public/readme.png">

# pigeon • [![tests](https://github.com/exp-table/pigeon/actions/workflows/ci.yml/badge.svg?label=tests)](https://github.com/exp-table/pigeon/actions/workflows/ci.yml) ![license](https://img.shields.io/github/license/refcell/femplate?label=license) ![solidity](https://img.shields.io/badge/solidity-%5E0.8.21-lightgrey)

**Pigeon** is an open-source modular testing toolkit for cross-chain application development using Arbitrary Message Bridges (AMBs) or RFQ-based bridges.

- Simulates cross-chain transactions as close to mainnet.
- Helps run cross-chain unit tests on forked mainnet.
- Simulate the off-chain infrastructure of AMBs.

The library is designed to work with the Foundry testing framework and can be used to streamline the testing process for applications that rely on cross-chain communication.

## Why Pigeon?
Arbitrary Message Bridges (AMB) like LayerZero, Axelar, Hyperlane, Celer IM, Wormhole, etc. and RFQ-based bridges like Across. operate alongside multiple off-chain actors. Hence mocking their entire infrastructure during unit testing is tricky for cross-chain application developers. 

Thanks to Pigeon, which will simplify the life of cross-chain application developers by simulating the off-chain infrastructure of such AMBs, helping developers write unit testing across multiple forked networks seamlessly.

By doing near mainnet testing, developers can quickly check sender authentication & other security assumptions associated with cross-chain application development.

### Supported Bridges

| Bridge | Messaging | Gas Estimation |
| --------- | :----------: | :---------: |
| Hyperlane |      ✅      | ✅  |
| LayerZero |      ✅      | ✅  |
| LayerZero V2 |      ✅      | ✅  |
| Celer     |      ✅      |   |
| Axelar    |      ✅      |   |
| Wormhole    |      ✅      |   |
| Stargate  |      ✅      |   |
| Across    |      ✅      |   |
## Getting Started

### Installation

To install with [**Foundry(git)**](https://github.com/foundry-rs/foundry):

```sh
$ forge install exp-table/pigeon
```
Add `pigeon/=lib/pigeon/` to foundry remappings

### Usage

Once installed, you can use the helper contracts of Pigeon by importing them into your test files.

It is made to be as simple as instantiating the helper in your test file and simply calling `help` with the appropriate parameters.
We have provided examples in the test files.

Without gas estimation (Hyperlane):

```solidity
vm.recordLogs();
_someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));
Vm.Log[] memory logs = vm.getRecordedLogs();
hyperlaneHelper.help(L1_HLMailbox, L2_HLMailbox, L2_FORK_ID, logs);
```

With gas estimation (Hyperlane):

```solidity
vm.recordLogs();
_someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));
Vm.Log[] memory logs = vm.getRecordedLogs();
hyperlaneHelper.helpWithEstimates(L1_Mailbox, L2_HLMailbox, L2_FORK_ID, logs);
```

To display estimations, run the `npm install` and `npm run compile` commands from the [utils/scripts directory](./utils/scripts) before running your tests. Then run tests with the `--ffi` flag and `ENABLE_ESTIMATES` env variable set to `true.`

**Gas estimation** is the gas costs required in native tokens to pay for the message delivery.

**Warning** As of now, it only supports the message execution and is not sensible to gas limits (a function of the fee you usually pay to the protocols).

## Local Development
Welcoming all open-source contributors to maintain & continue integrating more cross-chain messaging bridges to Pigeon. To do so,

**Step 1:** Clone the repository
```sh
$ git clone https://github.com/exp-table/pigeon
```

**Step 2:** Add Environment variables. Create a new file `.env` in the root directory and add the following lines.

```sh
ETH_MAINNET_RPC_URL=
POLYGON_MAINNET_RPC_URL=
ARBITRUM_MAINNET_RPC_URL=


# optional (true/false)
ENABLE_ESTIMATES=
```

**note**: Publicly available RPCs can also be used, but for better performance archive node urls are suggested.

**Step 3:** Install required node_modules (only if you wish to explore gas estimation)

```sh
$  npm install 
$  npm run compile
```

**Step 4:** Create a PR to the `main` branch. Clearly specify your changes in the PR description with a suitable title. Please make sure to double-check if the tests are passing.

If you have any further questions or need assistance, please don't hesitate to reach out by opening an issue on the GitHub repository.

### Notable Mentions

- [femplate](https://github.com/refcell/femplate)
- [foundry](https://github.com/foundry-rs/foundry)
- [solady](https://github.com/Vectorized/solady)
- [forge-std](https://github.com/brockelmore/forge-std)
- [forge-template](https://github.com/foundry-rs/forge-template)
- [foundry-toolchain](https://github.com/foundry-rs/foundry-toolchain)

### Disclaimer

_These smart contracts are being provided as is. No guarantee, representation or warranty is being made, express or implied, as to the safety or correctness of the user interface or the smart contracts. They have not been audited and as such there can be no assurance they will work as intended, and users may experience delays, failures, errors, omissions, loss of transmitted information or loss of funds. The creators are not liable for any of the foregoing. Users should proceed with caution and use at their own risk._

See [LICENSE](./LICENSE) for more details.
