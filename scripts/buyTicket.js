const { ethers } = require("hardhat");

const CONTRACT_ADDRESS = "0x28EAc0D17DEBEaCD003BB1d67E205db8b20133b8"; // Replace with deployed Fuji contract
const EVENT_ID = 1; // Replace with event ID from Sepolia
const TICKET_PRICE = ethers.parseEther("0.01"); // Must match Sepolia ticket price

async function main() {
  const [buyer] = await ethers.getSigners();
  const contract = await ethers.getContractAt("CrossChainNFTTicketing", CONTRACT_ADDRESS, buyer);

  console.log(`Trying to buy ticket for Event ID ${EVENT_ID} on Fuji from ${buyer.address}`);

  try {
    const tx = await contract.buyTicket(EVENT_ID, {
      value: TICKET_PRICE,
      gasLimit: 600000,
    });

    console.log("Transaction sent. Waiting for confirmation...");
    const receipt = await tx.wait();
    console.log("Ticket bought! Tx hash:", receipt.hash);

  } catch (error) {
    if (error.transactionHash) {
      console.log("Transaction reverted. Hash:", error.transactionHash);
    }

    if (error.message) {
      console.error("Revert reason:", error.message);
    }

    if (error.error && error.error.message) {
      console.error("Detailed revert reason:", error.error.message);
    }

    if (error.data && error.data.message) {
      console.error("Low-level revert reason:", error.data.message);
    }

    if (error.data && error.data.data) {
      const iface = new ethers.Interface([
        "function Error(string reason)"
      ]);
      try {
        const decoded = iface.parseError(error.data.data);
        console.error("Decoded revert reason:", decoded.args[0]);
      } catch (decodeErr) {
        console.error("Raw error data (cannot decode):", error.data.data);
      }
    }
  }
}

main().catch((err) => {
  console.error("Script crashed:", err);
});