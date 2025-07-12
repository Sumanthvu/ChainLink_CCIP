// scripts/deploy.js
const { ethers } = require("hardhat");

// CCIP, VRF, PriceFeed, LINK, KeyHash maps
const CCIP_ROUTERS = {
  ethereum: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
  polygon:  "0x1035CabC275068e0F4b745A29CEDf38E13aF41b1",
  avalanche:"0x554472a2720E5E7D5D3C817529aBA05EEd5F82D8",
  localhost:"0x0000000000000000000000000000000000000000"
};

const VRF_COORDINATORS = {
  ethereum: "0x8103B0A8A00be2DDC778e6e7eaa21791Cd364625",
  polygon:  "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed",
  avalanche:"0x2eD832Ba664535e5886b75D64C46EB9a228C2610",
  localhost:"0x0000000000000000000000000000000000000000"
};

const LINK_TOKENS = {
  ethereum: "0x779877A7B0D9E8603169DdbD7836e478b4624789",
  polygon:  "0x0Fd9e8d3aF1aaee056EB9e802c3A762a667b1904",
  avalanche:"0x0b9d5D9136855f6FEc3c0993feE6E9CE8a297846",
  localhost:"0x0000000000000000000000000000000000000000"
};

const VRF_KEY_HASHES = {
  ethereum: "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c",
  polygon:  "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f",
  avalanche:"0x354d2f95da55398f44b7cff77da56283d9c6c829a4bdf1bbcaf2ad6a4d081f61",
  localhost:"0x0000000000000000000000000000000000000000"
};

// Chain selectors as strings to avoid Number overflow
const CHAIN_SELECTORS = {
  ethereum: "16015286601757825753",
  polygon:  "12532609583862916517", 
  avalanche:"14767482510784806043",
  localhost:"0"
};

async function main() {
  const network = await ethers.provider.getNetwork();
  const chainId = Number(network.chainId);
  console.log("🔍 Detected chainId =", chainId);

  let chainName;
  if (chainId === 11155111)      chainName = "ethereum";  // Sepolia
  else if (chainId === 80002)    chainName = "polygon";   // Amoy
  else if (chainId === 43113)    chainName = "avalanche"; // Fuji
  else if (chainId === 31337)    chainName = "localhost"; // Hardhat
  else throw new Error(`Unsupported network with chainId: ${chainId}`);

  console.log(`Deploying to ${chainName} network…`);

  const TickItOn = await ethers.getContractFactory("TickItOn");
  
  // ✅ FIXED: Pass exactly 6 parameters matching the constructor
  const tickItOn = await TickItOn.deploy(
    CCIP_ROUTERS[chainName],        // address _ccipRouter
    VRF_COORDINATORS[chainName],    // address _vrfCoordinator  
    LINK_TOKENS[chainName],         // address _linkToken
    0,                              // uint64 _vrfSubscriptionId
    VRF_KEY_HASHES[chainName],      // bytes32 _vrfKeyHash
    BigInt(CHAIN_SELECTORS[chainName]) // uint64 _chainSelector
  );

  await tickItOn.waitForDeployment();
  console.log("✅ TickItOn deployed to:", tickItOn.target);
  
  // Optional: Verify the deployment
  console.log("🔧 Constructor parameters used:");
  console.log("- CCIP Router:", CCIP_ROUTERS[chainName]);
  console.log("- VRF Coordinator:", VRF_COORDINATORS[chainName]);
  console.log("- LINK Token:", LINK_TOKENS[chainName]);
  console.log("- VRF Subscription ID: 0");
  console.log("- VRF Key Hash:", VRF_KEY_HASHES[chainName]);
  console.log("- Chain Selector:", CHAIN_SELECTORS[chainName]);
}

main().catch((error) => {
  console.error("❌ Deployment failed:", error);
  process.exitCode = 1;
});