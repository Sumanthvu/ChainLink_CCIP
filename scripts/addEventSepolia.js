// scripts/addEventSepolia.js
const { ethers } = require("hardhat");

async function main() {
  const deployed = require("../deployed.json");
  const CONTRACT = await ethers.getContractAt("CrossChainNFTTicketing", deployed.sepolia);
  
  await CONTRACT.addEvent(
    "Chainlink Summit",
    "Demo event bridged to Fuji",
    ethers.parseEther("0.001"),
    100,
    BigInt("14767482510784806043") // Fuji chain selector
  );
  console.log("✅ Event created on Sepolia → usable by Fuji buyers");
}

main().catch(e => { console.error(e); process.exit(1); });
