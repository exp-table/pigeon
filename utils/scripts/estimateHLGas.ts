import {
  InterchainGasCalculator,
  MultiProvider,
  ChainName,
  chainMetadata,
} from "@hyperlane-xyz/sdk";
import { ethers } from "ethers";

// Usage: node estimateHLGas.js <origin> <destination> <handleGas>
const origin = process.argv[2] || "ethereum";
const destination = process.argv[3] || "polygon";
const handleGas = process.argv[4] || 200000;

const encoder = ethers.utils.defaultAbiCoder;

const calculateGas = async () => {
  // Set up a MultiProvider with the default providers.
  const multiProvider = new MultiProvider({
    arbitrum: chainMetadata.arbitrum,
    avalanche: chainMetadata.avalanche,
    bsc: chainMetadata.bsc,
    celo: chainMetadata.celo,
    ethereum: chainMetadata.ethereum,
    optimism: chainMetadata.optimism,
    polygon: chainMetadata.polygon,
    moonbeam: chainMetadata.moonbeam,
    gnosis: chainMetadata.gnosis,
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
