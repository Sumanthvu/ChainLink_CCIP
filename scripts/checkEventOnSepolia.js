const { ethers } = require("hardhat");

const SEPOLIA_CONTRACT = "0xDF6772aBEbBD43c4410DcC5AB6DF133de2248A44"; // your deployed Sepolia address
const EVENT_ID = 1;

async function main() {
  const Ticket = await ethers.getContractFactory("CrossChainNFTTicketing");
  const ticket = await Ticket.attach(SEPOLIA_CONTRACT);

  try {
    const event = await ticket.events(EVENT_ID);
    if (event.exists) {
      console.log(`✅ Event ${EVENT_ID} found on Sepolia`);
      console.log(`Name: ${event.name}`);
      console.log(`Description: ${event.description}`);
      console.log(`Price: ${ethers.parseEther(event.ticketPrice)} ETH`);
      console.log(`Total Tickets: ${event.totalTickets.toString()}`);
      console.log(`Sold Tickets: ${event.soldTickets.toString()}`);
    } else {
      console.log(`❌ Event ${EVENT_ID} not found (exists=false)`);
    }
  } catch (err) {
    console.error("❌ Error fetching event:", err.reason || err.message || err);
  }
}

main();
