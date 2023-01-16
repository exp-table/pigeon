import {
  chainConnectionConfigs,
  DomainIdToChainName,
  InterchainGasCalculator,
  MultiProvider,
  ChainName,
} from "@hyperlane-xyz/sdk";
import { ethers } from "ethers";

const origin = DomainIdToChainName[process.argv[2]] || "ethereum";
const destination = DomainIdToChainName[process.argv[3]] || "polygon";
const handleGas = process.argv[4] || 200000;

const encoder = ethers.utils.defaultAbiCoder;

const calculateGas = async () => {
  // Set up a MultiProvider with the default providers.
  const multiProvider = new MultiProvider({
    arbitrum: chainConnectionConfigs.arbitrum,
    avalanche: chainConnectionConfigs.avalanche,
    bsc: chainConnectionConfigs.bsc,
    celo: chainConnectionConfigs.celo,
    ethereum: chainConnectionConfigs.ethereum,
    optimism: chainConnectionConfigs.optimism,
    polygon: chainConnectionConfigs.polygon,
    moonbeam: chainConnectionConfigs.moonbeam,
  });

  // Create the calculator.
  const calculator = InterchainGasCalculator.fromEnvironment(
    "mainnet",
    multiProvider
  );

  // Calculate the AVAX payment to send from Avalanche to Polygon,
  // with the recipient's `handle` function consuming 200,000 gas.
  const payment = await calculator.estimatePaymentForHandleGas(
    origin as never,
    destination,
    ethers.BigNumber.from(handleGas)
  );

  process.stdout.write(encoder.encode(["uint256"], [payment]));
};

calculateGas();
