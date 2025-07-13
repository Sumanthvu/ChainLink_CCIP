const { ethers } = require("hardhat");

async function main() {
  const Ticket = await ethers.getContractFactory("CrossChainNFTTicketing");
  const ticketSepolia = Ticket.attach(process.env.SEPOLIA_CONTRACT);

  const user = process.env.USER_ADDRESS;
  const tickets = await ticketSepolia.userTickets(user);
  console.log("User has the following ticket IDs:", tickets.map(t => t.toString()));

  for (const id of tickets) {
    const owner = await ticketSepolia.ownerOf(id);
    console.log(`NFT #${id} is owned by:`, owner);
  }
}
main().catch(console.error);
