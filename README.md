<img align="right" width="150" height="150" top="100" src="./public/readme.png">

# pigeon • [![tests](https://github.com/exp-table/pigeon/actions/workflows/ci.yml/badge.svg?label=tests)](https://github.com/exp-table/pigeon/actions/workflows/ci.yml) ![license](https://img.shields.io/github/license/refcell/femplate?label=license) ![solidity](https://img.shields.io/badge/solidity-^0.8.17-lightgrey)

A **Simple**, **Easy** tool to test cross-chain protocols.

## What is Pigeon?

Pigeon is a set of helper contracts, one per cross-chain protocol, that is designed to help you simulate as closely as possible how the cross-chain transaction would go.

## Usage

It is made to be as simple as instantiating the helper in your test file, and simple calling `help` with the appropriate parameters.
We have provided examples in the test files.

In short, it looks like this (for Hyperlane) :

```js
vm.recordLogs();
_someCrossChainFunctionInYourContract(L2_DOMAIN, TypeCasts.addressToBytes32(address(target)));
Vm.Log[] memory logs = vm.getRecordedLogs();
hyperlaneHelper.help(0x35231d4c2D8B8ADcB5617A638A0c4548684c7C70, L2_FORK_ID, logs);
```

**Deployment & Verification**

Inside the [`utils/`](./utils/) directory are a few preconfigured scripts that can be used to deploy and verify contracts.

Scripts take inputs from the cli, using silent mode to hide any sensitive information.

_NOTE: These scripts are required to be \_executable_ meaning they must be made executable by running `chmod +x ./utils/*`.\_

_NOTE: these scripts will prompt you for the contract name and deployed addresses (when verifying). Also, they use the `-i` flag on `forge` to ask for your private key for deployment. This uses silent mode which keeps your private key from being printed to the console (and visible in logs)._

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
