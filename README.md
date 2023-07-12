<img align="right" width="150" height="150" top="100" src="./public/readme.png">

# pigeon • [![tests](https://github.com/exp-table/pigeon/actions/workflows/ci.yml/badge.svg?label=tests)](https://github.com/exp-table/pigeon/actions/workflows/ci.yml) ![license](https://img.shields.io/github/license/refcell/femplate?label=license) ![solidity](https://img.shields.io/badge/solidity-^0.8.17-lightgrey)

**Pigeon** is an open-source modular testing toolkit for cross-chain application development using Arbitray Message Bridges (AMBs).

- Simulates cross-chain transactions as close to mainnet.
- Helps run cross-chain unit tests on forked mainnet.
- Simulate the off-chain infrastructure of AMBs.

## Why Pigeon?
Arbitrary Message Bridges (AMB) like LayerZero, Hyperlane, Connext, Wormhole, etc., operate alongside multiple off-chain actors. Hence mocking their entire infrastructure during unit testing is tricky for cross-chain application developers. 

Thanks to Pigeon, which will simplify the life of cross-chain application developers by simulating the off-chain infrastructure of such AMBs, helping developers write unit testing across multiple forked networks seamlessly.

By doing near mainnet testing, developers can quickly check sender authentication & other security assumptions associated with cross-chain application development.

### Supported Bridges

| bridge | messaging | gas estimation |
| --------- | :----------: | :---------: |
| Hyperlane |      ✅      | ✅  |
| LayerZero |      ✅      | ✅  |
| Celer     |      ✅      |   |
| Axelar    |      ✅      |   |
| Stargate  |      ✅      |   |

## Getting Started

### Installation

To install with [**Foundry(git)**](https://github.com/gakonst/foundry):

```sh
$ forge install exp-table/pigeon
```
Add `pigeon/=lib/pigeon/` to `remappings.txt`

### Usage

Once installed, you can use the helper contracts of pigeon by importing them in your test files. A detailed documentation on all different helper function for multiple AMBs is under progress.


```solidity
/// @dev starts recording of logs
vm.recordLogs();

/// @dev can do some cross-chain messaging here
_someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));

/// @dev gets the recorded logs
m.Log[] memory logs = vm.getRecordedLogs();

/// @dev calls the helpers of pigeon
hyperlaneHelper.help(L1_HLMailbox, L2_HLMailbox, L2_FORK_ID, logs);
```

**Gas estimation** is the gas costs required in native tokens to pay for the message delivery, which is not properly integrated in the repository for all Arbitrary Message Bridges at this point.

**Warning** As of now, it only supports the message execution and is not sensible to gas limits (which is a function of the fee you pay to the protocols usually).

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
