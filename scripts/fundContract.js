// scripts/fundContract.js
const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const deployed = require("../deployed.json");
  const contractAddress = deployed.fuji;
  if (!contractAddress) {
    console.error("🚨 Missing deployed.fuji address!");
    process.exit(1);
  }

  const [funder] = await ethers.getSigners();
  console.log("⛽ Funding contract on Fuji:", contractAddress);

  const tx = await funder.sendTransaction({
    to: contractAddress,
    value: ethers.parseEther("0.01") // you can adjust the amount
  });
  await tx.wait();

  console.log("✅ Funded 💰", "0.01 AVAX");
}

main().catch(err => {
  console.error("❌ Error funding contract:", err);
  process.exit(1);
});
