// scripts/checkContractBalance.js
const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const deployed = require("../deployed.json");

  const balance = await ethers.provider.getBalance(deployed.fuji);
  console.log("🏦 Fuji contract balance:", ethers.formatEther(balance), "AVAX");
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
