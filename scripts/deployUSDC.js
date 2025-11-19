const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying USDC with the account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // Get constructor parameters from environment variables or use defaults
  const initialOwner = process.env.INITIAL_OWNER || deployer.address;
  const initialSupply = process.env.INITIAL_SUPPLY || "1000000000000"; // 1,000,000 USDC (6 decimals)

  console.log("\nDeployment parameters:");
  console.log("Initial owner:", initialOwner);
  console.log("Initial supply:", initialSupply, "USDC (6 decimals)");

  // Deploy USDC
  console.log("\nDeploying USDC...");
  const USDC = await hre.ethers.getContractFactory("USDC");
  const usdc = await USDC.deploy(initialOwner, initialSupply);

  await usdc.waitForDeployment();
  const usdcAddress = await usdc.getAddress();

  console.log("\n✅ USDC deployed to:", usdcAddress);
  console.log("Explorer:", `https://devnet-explorer.rayls.com/address/${usdcAddress}`);

  // Verify deployment
  console.log("\nVerifying deployment...");
  const name = await usdc.name();
  const symbol = await usdc.symbol();
  const decimals = await usdc.decimals();
  const totalSupply = await usdc.totalSupply();
  const ownerBalance = await usdc.balanceOf(initialOwner);

  console.log("Name:", name);
  console.log("Symbol:", symbol);
  console.log("Decimals:", decimals.toString());
  console.log("Total supply:", totalSupply.toString());
  console.log("Owner balance:", ownerBalance.toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

