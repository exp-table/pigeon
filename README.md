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

To enable gas estimation, from the [utils/scripts directory](./utils/scripts), run the following command:
```
npm install
npm run compile
```

## Usage

It is made to be as simple as instantiating the helper in your test file, and simple calling `help` with the appropriate parameters.
We have provided examples in the test files.

In short, it looks like this (for Hyperlane):

```js
vm.recordLogs();
_someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));
Vm.Log[] memory logs = vm.getRecordedLogs();
hyperlaneHelper.help(0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70, L2_FORK_ID, logs);
```

To display gas estimation, be sure to run the `npm install` and `npm run compile` commands from the [utils/scripts directory](./utils/scripts) before running your tests. Then run tests with the `--ffi` flag.

## Protocols support

| Protocols      | Is supported  |
| -------------  |:-------------:|
| Hyperlane      | ✅            |   
| LayerZero      | ✅            |
| Stargate       | ✅            |

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
