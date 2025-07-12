// scripts/checkMinted.js
const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const deployed = require("../deployed.json");
  const contract = await ethers.getContractAt(
    "CrossChainNFTTicketing",
    deployed.sepolia
  );

  const [buyer] = await ethers.getSigners(); // Use the first signer

  const totalTickets = await contract.getTotalTickets();
  console.log("🎟️ Total tickets minted on Sepolia:", totalTickets.toString());

  const balance = await contract.balanceOf(buyer.address);
  console.log(`👤 Buyer (${buyer.address}) NFT balance:`, balance.toString());

  if (balance.gt(0)) {
    const tokens = [];
    for (let i = 0; i < balance; i++) {
      const tokenId = await contract.tokenOfOwnerByIndex(buyer.address, i);
      tokens.push(tokenId.toString());
    }
    console.log("📄 Token IDs owned by buyer:", tokens);
  }

  const hasTicket = await contract.hasTicketForEvent(1, buyer.address);
  console.log("✅ Buyer has ticket for event 1:", hasTicket);
}

main().catch(err => {
  console.error("❌ Script failed:", err);
  process.exit(1);
});
