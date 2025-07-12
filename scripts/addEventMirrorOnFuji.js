// scripts/addEventMirrorOnFuji.js
const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const deployed = require("../deployed.json");
  const contract = await ethers.getContractAt(
    "CrossChainNFTTicketing",
    deployed.fuji
  );

  const tx = await contract.addEvent(
    "Chainlink Summit (Mirror)",
    "Mirror event to trigger cross-chain buy",
    ethers.parseEther("0.001"),
    100,
    BigInt("16015286601757825753") // ✅ Sepolia chain selector
  );
  await tx.wait();

  console.log("✅ Mirror event created on Fuji → will trigger CCIP to Sepolia");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
