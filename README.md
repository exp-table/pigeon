<img align="right" width="150" height="150" top="100" src="./public/readme.png">

# pigeon • [![tests](https://github.com/exp-table/pigeon/actions/workflows/ci.yml/badge.svg?label=tests)](https://github.com/exp-table/pigeon/actions/workflows/ci.yml) ![license](https://img.shields.io/github/license/refcell/femplate?label=license) ![solidity](https://img.shields.io/badge/solidity-^0.8.17-lightgrey)

A **Simple**, **Easy** tool to test cross-chain protocols.

## What is Pigeon?

Pigeon is a set of helper contracts, one per cross-chain protocol, that is designed to help you simulate as closely as possible how the cross-chain transaction would go.

## Installation

To install with [**Foundry**](https://github.com/gakonst/foundry):

```sh
forge install exp-table/pigeon
```

Set environment variables:

```sh
ETH_MAINNET_RPC_URL=
POLYGON_MAINNET_RPC_URL=

# Optional
ENABLE_ESTIMATES=
```

To enable gas estimation, from the [utils/scripts directory](./utils/scripts), run the following command:

```
npm install
npm run compile
```

## Usage

It is made to be as simple as instantiating the helper in your test file, and simple calling `help` with the appropriate parameters.
We have provided examples in the test files.

Without gas estimation (Hyperlane):

```js
vm.recordLogs();
_someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));
Vm.Log[] memory logs = vm.getRecordedLogs();
hyperlaneHelper.help(L1_HLMailbox, L2_HLMailbox, L2_FORK_ID, logs);
```

With gas estimation (Hyperlane):

```js
vm.recordLogs();
_someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));
Vm.Log[] memory logs = vm.getRecordedLogs();
hyperlaneHelper.helpWithEstimates(L1_Mailbox, L2_HLMailbox, L2_FORK_ID, logs);
```

To display estimations, be sure to run the `npm install` and `npm run compile` commands from the [utils/scripts directory](./utils/scripts) before running your tests. Then run tests with the `--ffi` flag and `ENABLE_ESTIMATES` env variable set to `true`.

**Gas estimation** is the gas costs required in native tokens to pay for the message delivery.

## Protocols support

| Protocols | Is supported |
| --------- | :----------: |
| Hyperlane |      ✅      |
| LayerZero |      ✅      |
| Celer     |      ✅      |
| Axelar    |      ✅      |
| Stargate  |      ✅      |

**Warning**

As of now, it only supports the message execution and is not sensible to gas limits (which is a function of the fee you pay to the protocols usually).

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
