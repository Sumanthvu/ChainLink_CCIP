// scripts/addEvent.js
const { ethers } = require("hardhat");
const deployed = require("../deployed.json");
const CHAIN_SELECTORS = {
  sepolia: "16015286601757825753",
  fuji:   "14767482510784806043",
  amoy:   "16281711391670634445"
};

async function main() {
  const contract = await ethers.getContractAt(
    "CrossChainNFTTicketing",
    deployed.sepolia
  );

  const tx = await contract.addEvent(
    "Chainlink Summit",
    "Cross-chain ticket demo",
    ethers.parseEther("0.001"),
    100,
    BigInt(CHAIN_SELECTORS.fuji)
  );

  await tx.wait();
  console.log("✅ Event created on Sepolia");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
