const { ethers } = require("hardhat");

// CCIP Router addresses for each network
const CCIP_ROUTERS = {
  ethereum: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",  // Sepolia
  polygon:  "0x1035CabC275068e0F4b745A29CEDf38E13aF41b1",  // Amoy
  avalanche:"0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8",  // Fuji
  localhost:"0x0000000000000000000000000000000000000000"
};

// CCIP Chain selectors (must match what the contract uses)
const CHAIN_SELECTORS = {
  ethereum: "16015286601757825753", // Sepolia
  polygon:  "16281711391670634445", // Amoy
  avalanche:"14767482510784806043", // Fuji
  localhost:"0"
};

async function main() {
  const network = await ethers.provider.getNetwork();
  const chainId = Number(network.chainId);
  console.log("🔍 Detected chainId =", chainId);

  let chainName;
  if (chainId === 11155111)      chainName = "ethereum";   // Sepolia
  else if (chainId === 80002)    chainName = "polygon";    // Amoy
  else if (chainId === 43113)    chainName = "avalanche";  // Fuji
  else if (chainId === 31337)    chainName = "localhost";  // Hardhat
  else throw new Error(`❌ Unsupported network with chainId: ${chainId}`);

  console.log(`🚀 Deploying to ${chainName} network...`);

  const TickItOn = await ethers.getContractFactory("CrossChainNFTTicketing");

  const tickItOn = await TickItOn.deploy(
    CCIP_ROUTERS[chainName],                     // ✅ Only 2 args
    BigInt(CHAIN_SELECTORS[chainName])           // convert string -> uint64
  );

  await tickItOn.waitForDeployment();
  console.log("✅ Contract deployed at:", tickItOn.target);
  console.log("📦 Constructor params used:");
  console.log("- CCIP Router:", CCIP_ROUTERS[chainName]);
  console.log("- Chain Selector:", CHAIN_SELECTORS[chainName]);
}

main().catch((error) => {
  console.error("❌ Deployment failed:", error);
  process.exitCode = 1;
});
