require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

// Validate environment variables
const requiredEnvVars = ["PRIVATE_KEY"];
const missingEnvVars = requiredEnvVars.filter(varName => !process.env[varName]);

if (missingEnvVars.length > 0) {
    throw new Error(`❌ Missing required environment variables: ${missingEnvVars.join(", ")}`);
}

// Validate private key format
if (!process.env.PRIVATE_KEY.startsWith("0x")) {
    // Add 0x prefix if not present
    process.env.PRIVATE_KEY = "0x" + process.env.PRIVATE_KEY;
}

module.exports = {
    solidity: {
        version: "0.8.20",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true,
        },
    },
    networks: {
        hardhat: {
            chainId: 31337,
        },
        sepolia: {
            url: process.env.SEPOLIA_RPC_URL || "https://eth-sepolia.g.alchemy.com/v2/aKaqFFYutBuSau90H43WY",
            accounts: [process.env.PRIVATE_KEY],
            chainId: 11155111,
            gasPrice: 20000000000, // 20 gwei
            gas: 2100000,
        },
        fuji: {
            url: process.env.FUJI_RPC_URL || "https://api.avax-test.network/ext/bc/C/rpc",
            accounts: [process.env.PRIVATE_KEY],
            chainId: 43113,
            gasPrice: 25000000000, // 25 gwei (Fuji typically needs higher gas)
            gas: 2100000,
        },
        amoy: {
            url: process.env.ALCHEMY_AMOY_URL || "https://polygon-amoy.g.alchemy.com/v2/vwKMqSDjsUfxEVnRksrxk9Pr9FgmgB3K",
            accounts: [process.env.PRIVATE_KEY],
            chainId: 80002,
            gasPrice: 30000000000, // 30 gwei
            gas: 2100000,
        },
    },
    etherscan: {
        apiKey: {
            sepolia: process.env.ETHERSCAN_API_KEY,
            polygonAmoy: process.env.POLYGONSCAN_API_KEY,
            avalancheFujiTestnet: "any-string", // Fuji doesn't require API key
        },
        customChains: [
            {
                network: "polygonAmoy",
                chainId: 80002,
                urls: {
                    apiURL: "https://api-amoy.polygonscan.com/api",
                    browserURL: "https://amoy.polygonscan.com"
                }
            },
            {
                network: "avalancheFujiTestnet",
                chainId: 43113,
                urls: {
                    apiURL: "https://api.routescan.io/v2/network/testnet/evm/43113/etherscan",
                    browserURL: "https://testnet.snowtrace.io"
                }
            }
        ]
    },
    gasReporter: {
        enabled: process.env.REPORT_GAS !== undefined,
        currency: "USD",
    },
    mocha: {
        timeout: 60000, // 60 seconds for cross-chain tests
    },
};