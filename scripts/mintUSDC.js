const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Minting USDC with the account:", deployer.address);
  console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());

  // Get USDC contract address and recipient from environment variables or command line arguments
  const usdcAddress = process.env.USDC_ADDRESS || process.argv[2] || "0x5f8EBb3Fb1AD9E4E1E59773187eAcD1F708A440b";
  const recipient = process.env.RECIPIENT || process.argv[3] || deployer.address;
  const amount = process.env.AMOUNT || process.argv[4] || "100000000000"; // 100,000 USDC (6 decimals)

  console.log("\nMinting parameters:");
  console.log("USDC contract address:", usdcAddress);
  console.log("Recipient address:", recipient);
  console.log("Amount:", amount, "USDC (6 decimals)");

  // Get the USDC contract
  const USDC = await hre.ethers.getContractFactory("USDC");
  const usdc = USDC.attach(usdcAddress);

  // Check current balance
  const balanceBefore = await usdc.balanceOf(recipient);
  console.log("\nRecipient balance before:", balanceBefore.toString());

  // Mint tokens
  console.log("\nMinting tokens...");
  const tx = await usdc.mint(recipient, amount);
  console.log("Transaction hash:", tx.hash);
  
  await tx.wait();
  console.log("✅ Transaction confirmed!");

  // Check new balance
  const balanceAfter = await usdc.balanceOf(recipient);
  console.log("\nRecipient balance after:", balanceAfter.toString());
  console.log("Tokens minted:", (balanceAfter - balanceBefore).toString());
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

