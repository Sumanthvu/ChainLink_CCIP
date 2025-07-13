const { ethers } = require("hardhat");
const { sepolia } = require("./config");

async function main() {
  const [deployer] = await ethers.getSigners();
const Ticket = await ethers.getContractFactory("CrossChainNFTTicketing");
const ticket = await Ticket.attach("0xDF6772aBEbBD43c4410DcC5AB6DF133de2248A44"); // ✅ Use your actual Sepolia contract address


  console.log("Sepolia ticket deployed to:", await ticket.getAddress());

  await deployer.sendTransaction({
    to: await ticket.getAddress(),
    value: ethers.parseEther("0.1"),
  });
  console.log("Funded with 0.1 ETH for CCIP fees");

  const tx = await ticket.addEvent(
    "Sepolia Concert",
    "A live show",
    ethers.parseEther("0.01"),
    100,
    BigInt(sepolia.selector),
    { value: ethers.parseEther("0.05") }
  );
  const receipt = await tx.wait();

  let found = false;
  for (const log of receipt.logs) {
    try {
      const parsed = ticket.interface.parseLog(log);
      if (parsed.name === "EventListed") {
        console.log("🎉 Event listed with ID:", parsed.args.eventId.toString());
        found = true;
        break;
      }
    } catch {}
  }

  if (!found) console.warn("⚠️ EventListed event not found in logs!");
}

main().catch(console.error);
