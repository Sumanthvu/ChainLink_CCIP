// scripts/buyTicket.js
const { ethers } = require("hardhat");
const deployed = require("../deployed.json");
const CHAIN_SELECTORS = {
  sepolia: "16015286601757825753",
  fuji:    "14767482510784806043",
  amoy:    "16281711391670634445"
};

async function main() {
  const [buyer] = await ethers.getSigners();
  const contract = await ethers.getContractAt(
    "CrossChainNFTTicketing",
    deployed.fuji,
    buyer
  );

  const tx = await contract.buyTicket(
    1,
    "VIP",
    { value: ethers.parseEther("0.001") }
  );
  await tx.wait();

  console.log("🎫 Ticket purchased on Fuji — CCIP message sent to Sepolia!");
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
