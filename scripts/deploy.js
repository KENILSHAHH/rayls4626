const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // Get constructor parameters from environment variables or command line arguments
  const assetAddress = process.env.ASSET_ADDRESS || process.argv[2];
  const vaultName = process.env.VAULT_NAME || process.argv[3] || "ERC4626 Vault";
  const vaultSymbol = process.env.VAULT_SYMBOL || process.argv[4] || "VAULT";

  if (!assetAddress) {
    throw new Error("Asset address is required. Set ASSET_ADDRESS env var or pass as first argument");
  }

  console.log("\nDeployment parameters:");
  console.log("Asset address:", assetAddress);
  console.log("Vault name:", vaultName);
  console.log("Vault symbol:", vaultSymbol);

  // Get the asset contract to verify it exists
  const assetContract = await hre.ethers.getContractAt("ERC20", assetAddress);
  const assetName = await assetContract.name();
  const assetSymbol = await assetContract.symbol();
  console.log("\nAsset token:", assetName, "(", assetSymbol, ")");

  // Deploy the vault
  console.log("\nDeploying ERC4626Vault...");
  const ERC4626Vault = await hre.ethers.getContractFactory("ERC4626Vault");
  const vault = await ERC4626Vault.deploy(assetAddress, vaultName, vaultSymbol);

  await vault.waitForDeployment();
  const vaultAddress = await vault.getAddress();

  console.log("\n✅ ERC4626Vault deployed to:", vaultAddress);
  console.log("Explorer:", `https://devnet-explorer.rayls.com/address/${vaultAddress}`);

  // Verify deployment
  console.log("\nVerifying deployment...");
  const totalAssets = await vault.totalAssets();
  const totalSupply = await vault.totalSupply();
  console.log("Total assets:", totalAssets.toString());
  console.log("Total supply:", totalSupply.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

