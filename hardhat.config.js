require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.24",
  networks: {
    rayls: {
      url: "https://devnet-rpc.rayls.com",
      chainId: 123123,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: {
      rayls: "no-api-key-needed",
    },
    customChains: [
      {
        network: "rayls",
        chainId: 123123,
        urls: {
          apiURL: "https://devnet-explorer.rayls.com/api",
          browserURL: "https://devnet-explorer.rayls.com",
        },
      },
    ],
  },
};

