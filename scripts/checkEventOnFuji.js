const { ethers } = require("hardhat");

const FUJI_CONTRACT = "0x4aAac9e0bd0d8d24eC2AfFaDd9B9E6E0eE4CeF09"; // 🔁 Replace with actual deployed address on Fuji
const EVENT_ID = 1; // The event ID you created on Sepolia

async function main() {
  const Ticket = await ethers.getContractFactory("CrossChainNFTTicketing");
  const ticket = await Ticket.attach(FUJI_CONTRACT);

  try {
    const event = await ticket.events(EVENT_ID);
    if (event.exists) {
      console.log(`✅ Event ${EVENT_ID} found on Fuji`);
      console.log(`📌 Name: ${event.name}`);
      console.log(`🎟️ Price: ${ethers.parseEther(event.ticketPrice)} AVAX`);
      console.log(`🎯 Organizer: ${event.organizer}`);
    } else {
      console.log(`❌ Event ${EVENT_ID} not found (exists=false)`);
    }
  } catch (err) {
    console.error("❌ Failed to fetch event:", err.reason || err);
  }
}

main();
