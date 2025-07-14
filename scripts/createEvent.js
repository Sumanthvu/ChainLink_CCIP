const { ethers } = require("hardhat");

// #############################################
// ############# CONFIGURATION #################
// #############################################

// Pre-filled with your Sepolia contract address
const CONTRACT_ADDRESS = "0x4c753011BD5e86b26bdC1c6621FB87B0d9F979b4"; 

// 1. UPDATE with the details of the event you want to create
const EVENT_DETAILS = {
    name: "Cross-Chain Dev Meetup",
    description: "A virtual event for Web3 builders.",
    ticketPrice: ethers.parseEther("0.01"), // Price in Sepolia ETH
    totalTickets: 100
};

// 2. (Optional) Manually set the CCIP fee if estimation fails.
const MANUAL_CCIP_FEE = ethers.parseEther("0.1"); // Example: 0.1 Sepolia ETH

// #############################################

async function main() {
    console.log("🚀 Initializing script to create an event on Sepolia...");
    const [deployer] = await ethers.getSigners();
    const network = await ethers.provider.getNetwork();

    if (network.name !== "sepolia") {
        console.error("❌ This script is configured for Sepolia. Please run with '--network sepolia'");
        return;
    }

    console.log(`📡 Connected to network: ${network.name} (Chain ID: ${network.chainId})`);
    console.log(`👤 Using account: ${deployer.address}`);

    const CrossChainNFTTicketing = await ethers.getContractFactory("CrossChainNFTTicketing");
    const contract = CrossChainNFTTicketing.attach(CONTRACT_ADDRESS);

    console.log(`\n📝 Creating Event:`);
    console.log(`   - Name: ${EVENT_DETAILS.name}`);
    console.log(`   - Price: ${ethers.formatEther(EVENT_DETAILS.ticketPrice)} ETH`);
    console.log(`   - Total Tickets: ${EVENT_DETAILS.totalTickets}`);

    try {
        console.log("\nEstimating CCIP fees for syncing the event...");
        const estimatedFee = await contract.estimateEventCreationFees(
            EVENT_DETAILS.name,
            EVENT_DETAILS.description,
            EVENT_DETAILS.ticketPrice,
            EVENT_DETAILS.totalTickets
        );
        console.log(`✅ Estimated CCIP Fee: ${ethers.formatEther(estimatedFee)} ETH`);
        
        const txValue = estimatedFee > 0 ? estimatedFee : MANUAL_CCIP_FEE;
        
        console.log(`\n⏳ Sending transaction to create event... (Funding with ${ethers.formatEther(txValue)} ETH for fees)`);

        const tx = await contract.createEvent(
            EVENT_DETAILS.name,
            EVENT_DETAILS.description,
            EVENT_DETAILS.ticketPrice,
            EVENT_DETAILS.totalTickets,
            { value: txValue }
        );

        console.log(`Transaction sent! Waiting for confirmation...`);
        const receipt = await tx.wait();

        const eventId = receipt.logs.find(log => contract.interface.parseLog(log)?.name === "EventCreated")?.args[0];

        console.log(`\n✅ Success!`);
        console.log(`   - Transaction Hash: ${tx.hash}`);
        console.log(`   - Event Created with ID: ${eventId.toString()}`);
        console.log(`   - This event is now being synced to Fuji.`);
        console.log(`   - It may take several minutes for the event to appear on the Fuji contract.`);

    } catch (error) {
        console.error("\n❌ An error occurred:", error.message);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Script failed:", error);
        process.exit(1);
    }); 