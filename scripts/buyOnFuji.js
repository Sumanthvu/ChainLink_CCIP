const { ethers } = require("hardhat");

// Configuration - Update these values
const CONTRACT_ADDRESS = "0x4aAac9e0bd0d8d24eC2AfFaDd9B9E6E0eE4CeF09"; // Your deployed contract on Fuji
const EVENT_ID = 1; // The event ID you want to purchase tickets for

async function main() {
  const [buyer] = await ethers.getSigners();
  const Ticket = await ethers.getContractFactory("CrossChainNFTTicketing");
  const ticket = await Ticket.attach(CONTRACT_ADDRESS);

  console.log("===============================");
  console.log("🎫 Cross-Chain Ticket Purchase");
  console.log("===============================");
  console.log(`Buyer: ${buyer.address}`);
  console.log(`Contract: ${CONTRACT_ADDRESS}`);
  console.log(`Event ID: ${EVENT_ID}`);
  console.log("-------------------------------");

  // 1. Check event exists
  const eventDetails = await ticket.events(EVENT_ID);
  if (!eventDetails.exists) {
    console.error("❌ Error: Event not found on Fuji");
    console.log("Possible reasons:");
    console.log("- Event hasn't been synced via CCIP yet");
    console.log("- Wrong event ID specified");
    console.log("- Contract address is incorrect");
    return;
  }
  
  console.log(`✅ Event found: "${eventDetails.name}"`);
  console.log(`   Description: ${eventDetails.description}`);
  console.log(`   Ticket Price: ${ethers.utils.formatEther(eventDetails.ticketPrice)} AVAX`);
  console.log(`   Tickets Sold: ${eventDetails.soldTickets.toString()}/${eventDetails.totalTickets.toString()}`);
  console.log(`   Active: ${eventDetails.isActive ? "Yes" : "No"}`);
  console.log(`   Origin Chain: ${eventDetails.originChainSelector}`);
  console.log(`   NFT Chain: ${eventDetails.nftChainSelector}`);
  
  // 2. Check event status
  if (!eventDetails.isActive) {
    console.error("❌ Error: Event is not active");
    console.log("The event organizer has deactivated ticket sales");
    return;
  }
  
  if (eventDetails.soldTickets >= eventDetails.totalTickets) {
    console.error("❌ Error: Event is sold out");
    return;
  }
  
  // 3. Check if buyer already has ticket
  const alreadyHasTicket = await ticket.hasTicketForEvent(EVENT_ID, buyer.address);
  if (alreadyHasTicket) {
    console.error("❌ Error: You already have a ticket for this event");
    return;
  }
  
  // 4. Check contract balance for CCIP fees
  const contractBalance = await ethers.provider.getBalance(ticket.address);
  const minRequiredBalance = ethers.utils.parseEther("0.05");
  console.log(`Contract balance: ${ethers.utils.formatEther(contractBalance)} AVAX`);
  
  if (contractBalance.lt(minRequiredBalance)) {
    console.log("⚠️ Funding contract for CCIP fees...");
    
    const fundAmount = ethers.utils.parseEther("0.1");
    const fundTx = await buyer.sendTransaction({
      to: ticket.address,
      value: fundAmount,
      gasLimit: 100000
    });
    
    await fundTx.wait();
    console.log(`💰 Sent ${ethers.utils.formatEther(fundAmount)} AVAX to contract`);
    
    const newContractBalance = await ethers.provider.getBalance(ticket.address);
    console.log(`New contract balance: ${ethers.utils.formatEther(newContractBalance)} AVAX`);
  } else {
    console.log("✅ Contract has sufficient funds for CCIP operations");
  }
  
  // 5. Attempt ticket purchase
  console.log("-------------------------------");
  console.log("Purchasing ticket...");
  
  try {
    const ticketPrice = eventDetails.ticketPrice;
    const tx = await ticket.buyTicket(EVENT_ID, "General", {
      value: ticketPrice,
      gasLimit: 1_500_000 // Increased gas limit for CCIP operations
    });
    
    console.log(`⏳ Transaction sent: ${tx.hash}`);
    const receipt = await tx.wait();
    console.log("✅ Transaction confirmed");
    console.log(`   Block: ${receipt.blockNumber}`);
    console.log(`   Gas used: ${receipt.gasUsed.toString()}`);
    
    // Verify purchase
    const hasTicketNow = await ticket.hasTicketForEvent(EVENT_ID, buyer.address);
    if (hasTicketNow) {
      console.log("🎉 Success! You now have a ticket for this event");
      
      // Get ticket ID
      const userEvents = await ticket.getUserTickets(buyer.address);
      const eventIndex = userEvents.indexOf(EVENT_ID);
      if (eventIndex !== -1) {
        console.log("🔍 Finding your NFT ticket...");
        
        // For simplicity, we'll just show the last minted ticket
        const totalTickets = await ticket.getTotalTickets();
        console.log(`   Your ticket ID: #${totalTickets}`);
      }
    } else {
      console.log("⚠️ Purchase completed but ticket not detected");
      console.log("This might be due to cross-chain minting delays");
    }
  } catch (error) {
    console.error("❌ Purchase failed!");
    console.error("Error:", error.reason || error.message);
    
    // Common error scenarios
    if (error.message.includes("insufficient funds")) {
      console.log("Solution: Fund your wallet with more AVAX");
    } else if (error.message.includes("Event is not active")) {
      console.log("Solution: Event was deactivated during transaction");
    } else if (error.message.includes("Already has ticket")) {
      console.log("Solution: Refresh your ticket status");
    } else if (error.message.includes("Event sold out")) {
      console.log("Solution: Tickets sold out during transaction");
    } else {
      console.log("Check contract status and try again with increased gas");
    }
  }
}

main().catch((error) => {
  console.error("⚠️ Script error:", error);
  process.exitCode = 1;
});