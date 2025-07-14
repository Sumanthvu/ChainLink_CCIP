const { ethers } = require("hardhat");

// CCIP Router addresses for each network (corrected)
const CCIP_ROUTERS = {
    sepolia: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
    amoy: "0x1035CabC275068e0F4b745A29CEDf38E13aF41b1", 
    fuji: "0xF694E193200268f9a4868e4Aa017A0118C9a8177", // Updated to match your ENV
    localhost: "0x0000000000000000000000000000000000000000"
};

// CCIP Chain selectors (must match what the contract uses)
const CHAIN_SELECTORS = {
    sepolia: "16015286601757825753",
    amoy: "16281711391670634445", 
    fuji: "14767482510784806043",
    localhost: "0"
};

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("🔐 Deploying with account:", deployer.address);
    
    const balance = await ethers.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");

    const network = await ethers.provider.getNetwork();
    const chainId = Number(network.chainId);
    console.log("🔍 Detected chainId =", chainId);

    let chainName;
    if (chainId === 11155111) chainName = "sepolia";
    else if (chainId === 80002) chainName = "amoy"; 
    else if (chainId === 43113) chainName = "fuji";
    else if (chainId === 31337) chainName = "localhost";
    else throw new Error(`❌ Unsupported network with chainId: ${chainId}`);

    console.log(`🚀 Deploying to ${chainName} network...`);
    
    const ccipRouter = CCIP_ROUTERS[chainName];
    const chainSelector = CHAIN_SELECTORS[chainName];
    
    console.log("📦 Constructor params:");
    console.log("- CCIP Router:", ccipRouter);
    console.log("- Chain Selector:", chainSelector);

    // Verify router address is not zero
    if (ccipRouter === "0x0000000000000000000000000000000000000000" && chainName !== "localhost") {
        throw new Error(`❌ Invalid CCIP Router address for ${chainName}`);
    }

    const CrossChainNFTTicketing = await ethers.getContractFactory("CrossChainNFTTicketing");
    
    console.log("📝 Deploying contract...");
    const contract = await CrossChainNFTTicketing.deploy(
        ccipRouter,
        BigInt(chainSelector)
    );

    console.log("⏳ Waiting for deployment...");
    await contract.waitForDeployment();

    const contractAddress = await contract.getAddress();
    console.log("✅ Contract deployed at:", contractAddress);
    
    // Verify deployment by calling a view function
    try {
        const currentChainSelector = await contract.getCurrentChainSelector();
        console.log("🔗 Verified chain selector:", currentChainSelector.toString());
        
        const owner = await contract.owner();
        console.log("👤 Contract owner:", owner);
        
        const name = await contract.name();
        const symbol = await contract.symbol();
        console.log("🎫 NFT Token:", name, "(" + symbol + ")");
        
    } catch (error) {
        console.log("⚠️  Could not verify deployment:", error.message);
    }

    // Save deployment info
    console.log("\n📋 Deployment Summary:");
    console.log("=".repeat(50));
    console.log(`Network: ${chainName}`);
    console.log(`Chain ID: ${chainId}`);
    console.log(`Contract: ${contractAddress}`);
    console.log(`CCIP Router: ${ccipRouter}`);
    console.log(`Chain Selector: ${chainSelector}`);
    console.log(`Deployer: ${deployer.address}`);
    console.log("=".repeat(50));

    // Instructions for next steps
    console.log("\n🔄 Next Steps:");
    console.log("1. Update your .env file with:");
    console.log(`   ${chainName.toUpperCase()}_CONTRACT="${contractAddress}"`);
    console.log("2. Deploy to other networks for cross-chain functionality");
    console.log("3. Fund the contract with native tokens for CCIP fees");
    console.log("4. Test event creation and ticket purchasing");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("❌ Deployment failed:", error);
        process.exit(1);
    });