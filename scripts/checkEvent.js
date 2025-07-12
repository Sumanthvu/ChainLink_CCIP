const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const contractAddress = process.env.CONTRACT_ADDRESS;
  const eventId = 1; // 🔁 Change this to your desired event ID

  const TicketContract = await ethers.getContractAt("CrossChainNFTTicketing", contractAddress);

  try {
    const eventData = await TicketContract.events(eventId);

    console.log("🎟️ Event Found:");
    console.log("• Organizer:", eventData.organizer);
    
    if (eventData.price) {
      console.log("• Price:", ethers.formatEther(eventData.price), "ETH");
    } else {
      console.log("• Price: (null)");
    }

    console.log("• Max Tickets:", Number(eventData.maxTickets));
    console.log("• Tickets Sold:", Number(eventData.ticketsSold));
    console.log("• Is Active:", eventData.isActive ? "✅ Yes" : "❌ No");

  } catch (err) {
    console.error("❌ No such event or contract call failed:", err.message);
  }
}

main().catch((err) => {
  console.error("❌ Script Error:", err);
  process.exitCode = 1;
});
