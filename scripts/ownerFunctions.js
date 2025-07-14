const { ethers } = require("hardhat");

// #############################################
// ############# CONFIGURATION #################
// #############################################

// 1. UPDATE with the address of your deployed contract
const CONTRACT_ADDRESS = "YOUR_CONTRACT_ADDRESS_HERE";

// 2. CHOOSE which function to run
const ACTION = "withdraw"; // "withdraw" or "setChain"

// 3. (If ACTION is "setChain") CONFIGURE chain settings
const CHAIN_SELECTOR_TO_UPDATE = "16015286601757825753"; // e.g., Sepolia's selector
const IS_SUPPORTED = false; // Set to `true` to add/enable, `false` to remove/disable

// #############################################

async function main() {
    console.log("🚀 Initializing owner script...");
    const [owner] = await ethers.getSigners();
    const network = await ethers.provider.getNetwork();

    console.log(`📡 Connected to network: ${network.name}`);
    console.log(`👤 Using account (Owner): ${owner.address}`);

    if (CONTRACT_ADDRESS === "YOUR_CONTRACT_ADDRESS_HERE") {
        console.error("❌ Error: Please update the CONTRACT_ADDRESS in the script.");
        return;
    }

    const CrossChainNFTTicketing = await ethers.getContractFactory("CrossChainNFTTicketing");
    const contract = CrossChainNFTTicketing.attach(CONTRACT_ADDRESS);

    // Verify the connected account is the owner
    const contractOwner = await contract.owner();
    if (owner.address.toLowerCase() !== contractOwner.toLowerCase()) {
        console.error(`❌ Error: The connected account (${owner.address}) is not the contract owner (${contractOwner}).`);
        return;
    }
    
    console.log("✅ Verified that the connected account is the owner.");

    if (ACTION === "withdraw") {
        await withdrawContractFees(contract);
    } else if (ACTION === "setChain") {
        await setSupportedChain(contract);
    } else {
        console.error(`❌ Invalid ACTION: "${ACTION}". Choose "withdraw" or "setChain".`);
    }
}

async function withdrawContractFees(contract) {
    try {
        const balance = await ethers.provider.getBalance(contract.getAddress());
        console.log(`\n💰 Contract balance: ${ethers.formatEther(balance)} native currency.`);

        if (balance === 0n) {
            console.log("No fees to withdraw.");
            return;
        }

        console.log("⏳ Withdrawing fees...");
        const tx = await contract.withdrawFees();
        await tx.wait();
        
        console.log(`✅ Success! Fees withdrawn.`);
        console.log(`   - Transaction Hash: ${tx.hash}`);

    } catch (error) {
        console.error("\n❌ Fee withdrawal failed:", error.message);
    }
}

async function setSupportedChain(contract) {
    try {
        console.log(`\nSetting support for chain ${CHAIN_SELECTOR_TO_UPDATE} to ${IS_SUPPORTED}...`);
        
        const tx = await contract.setSupportedChain(CHAIN_SELECTOR_TO_UPDATE, IS_SUPPORTED);
        await tx.wait();
        
        console.log(`✅ Success! Chain support updated.`);
        console.log(`   - Transaction Hash: ${tx.hash}`);

    } catch (error) {
        console.error("\n❌ Setting supported chain failed:", error.message);
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Script failed:", error);
        process.exit(1);
    });