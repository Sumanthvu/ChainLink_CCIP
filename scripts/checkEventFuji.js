// scripts/checkEventFuji.js
const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const deployed = require("../deployed.json");
  const contract = await ethers.getContractAt(
    "CrossChainNFTTicketing",
    deployed.fuji
  );
  const eventId = 1; // Change if needed

  try {
    const data = await contract.events(eventId);
    console.log("🎟️ Fuji Event Found for ID", eventId);
    console.log("• Organizer:", data.organizer);
    console.log("• Price:", data.ticketPrice ? ethers.formatEther(data.ticketPrice) : "(null)");
    console.log("• Max Tickets:", data.totalTickets ? data.totalTickets.toString() : "(null)");
    console.log("• Tickets Sold:", data.soldTickets ? data.soldTickets.toString() : "(null)");
    console.log("• Active?", data.isActive ? "✅ Yes" : "❌ No");
  } catch (e) {
    console.error("❌ No event on Fuji with ID", eventId, "| Error:", e.message);
  }
}

main().catch(e => {
  console.error("Script failed:", e);
  process.exit(1);
});
