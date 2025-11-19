const hre = require("hardhat");

async function main() {
  console.log("=".repeat(80));
  console.log("Testing LeveragedERC4626Vault on Rayls Network");
  console.log("=".repeat(80));

  const signers = await hre.ethers.getSigners();
  const deployer = signers[0];
  const user = signers[1] || deployer; // Use deployer as user if second signer doesn't exist
  
  console.log("\n📋 Accounts:");
  console.log("  Deployer:", deployer.address);
  console.log("  User:", user.address);
  console.log("  Deployer balance:", hre.ethers.formatEther(await hre.ethers.provider.getBalance(deployer.address)), "ETH");
  
  if (user.address === deployer.address) {
    console.log("  ⚠️  Using deployer as user (only one signer available)");
  }

  // Step 1: Deploy USDC and USDT
  console.log("\n" + "=".repeat(80));
  console.log("Step 1: Deploying USDC and USDT tokens");
  console.log("=".repeat(80));

  const USDC = await hre.ethers.getContractFactory("USDC");
  const usdc = await USDC.deploy(deployer.address, hre.ethers.parseUnits("1000000", 6)); // 1M USDC
  await usdc.waitForDeployment();
  const usdcAddress = await usdc.getAddress();
  console.log("✅ USDC deployed to:", usdcAddress);

  const USDT = await hre.ethers.getContractFactory("USDT");
  const usdt = await USDT.deploy(deployer.address, hre.ethers.parseUnits("1000000", 6)); // 1M USDT
  await usdt.waitForDeployment();
  const usdtAddress = await usdt.getAddress();
  console.log("✅ USDT deployed to:", usdtAddress);

  // Step 2: Deploy PoolAddressesProvider
  console.log("\n" + "=".repeat(80));
  console.log("Step 2: Deploying PoolAddressesProvider");
  console.log("=".repeat(80));

  const PoolAddressesProvider = await hre.ethers.getContractFactory("PoolAddressesProvider");
  const addressesProvider = await PoolAddressesProvider.deploy(deployer.address);
  await addressesProvider.waitForDeployment();
  const addressesProviderAddress = await addressesProvider.getAddress();
  console.log("✅ PoolAddressesProvider deployed to:", addressesProviderAddress);

  // Step 3: Deploy InterestRateStrategy
  console.log("\n" + "=".repeat(80));
  console.log("Step 3: Deploying InterestRateStrategy");
  console.log("=".repeat(80));

  const InterestRateStrategy = await hre.ethers.getContractFactory("InterestRateStrategy");
  // Parameters: optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2
  // Using Ray format (1e27)
  const optimalUtilizationRate = hre.ethers.parseUnits("0.8", 27); // 80%
  const baseVariableBorrowRate = hre.ethers.parseUnits("0.01", 27); // 1%
  const variableRateSlope1 = hre.ethers.parseUnits("0.04", 27); // 4%
  const variableRateSlope2 = hre.ethers.parseUnits("0.75", 27); // 75%

  const interestRateStrategy = await InterestRateStrategy.deploy(
    optimalUtilizationRate,
    baseVariableBorrowRate,
    variableRateSlope1,
    variableRateSlope2
  );
  await interestRateStrategy.waitForDeployment();
  const interestRateStrategyAddress = await interestRateStrategy.getAddress();
  console.log("✅ InterestRateStrategy deployed to:", interestRateStrategyAddress);

  // Step 4: Deploy Pool
  console.log("\n" + "=".repeat(80));
  console.log("Step 4: Deploying Pool");
  console.log("=".repeat(80));

  const Pool = await hre.ethers.getContractFactory("Pool");
  const pool = await Pool.deploy(addressesProviderAddress);
  await pool.waitForDeployment();
  const poolAddress = await pool.getAddress();
  console.log("✅ Pool deployed to:", poolAddress);

  // Set pool in addresses provider
  await addressesProvider.setPoolImpl(poolAddress);
  console.log("✅ Pool set in AddressesProvider");

  // Step 5: Deploy AToken and VariableDebtToken for USDC
  console.log("\n" + "=".repeat(80));
  console.log("Step 5: Deploying AToken and VariableDebtToken for USDC");
  console.log("=".repeat(80));

  const AToken = await hre.ethers.getContractFactory("AToken");
  const aTokenUSDC = await AToken.deploy(
    poolAddress,
    usdcAddress,
    "Aave USDC",
    "aUSDC"
  );
  await aTokenUSDC.waitForDeployment();
  const aTokenUSDCAddress = await aTokenUSDC.getAddress();
  console.log("✅ aTokenUSDC deployed to:", aTokenUSDCAddress);

  const VariableDebtToken = await hre.ethers.getContractFactory("VariableDebtToken");
  const variableDebtTokenUSDC = await VariableDebtToken.deploy(
    poolAddress,
    usdcAddress,
    "Variable Debt USDC",
    "variableDebtUSDC"
  );
  await variableDebtTokenUSDC.waitForDeployment();
  const variableDebtTokenUSDCAddress = await variableDebtTokenUSDC.getAddress();
  console.log("✅ variableDebtTokenUSDC deployed to:", variableDebtTokenUSDCAddress);

  // Step 6: Deploy AToken and VariableDebtToken for USDT
  console.log("\n" + "=".repeat(80));
  console.log("Step 6: Deploying AToken and VariableDebtToken for USDT");
  console.log("=".repeat(80));

  const aTokenUSDT = await AToken.deploy(
    poolAddress,
    usdtAddress,
    "Aave USDT",
    "aUSDT"
  );
  await aTokenUSDT.waitForDeployment();
  const aTokenUSDTAddress = await aTokenUSDT.getAddress();
  console.log("✅ aTokenUSDT deployed to:", aTokenUSDTAddress);

  const variableDebtTokenUSDT = await VariableDebtToken.deploy(
    poolAddress,
    usdtAddress,
    "Variable Debt USDT",
    "variableDebtUSDT"
  );
  await variableDebtTokenUSDT.waitForDeployment();
  const variableDebtTokenUSDTAddress = await variableDebtTokenUSDT.getAddress();
  console.log("✅ variableDebtTokenUSDT deployed to:", variableDebtTokenUSDTAddress);

  // Step 7: Initialize reserves in Pool
  console.log("\n" + "=".repeat(80));
  console.log("Step 7: Initializing reserves in Pool");
  console.log("=".repeat(80));

  // Helper function to build reserve configuration
  function buildReserveConfig(ltv, liquidationThreshold, liquidationBonus, decimals, reserveFactor) {
    let data = 0n;
    
    // LTV (bits 0-15): 8500 = 0x2134
    data = data | BigInt(ltv);
    
    // Liquidation threshold (bits 16-31): 9000 = 0x2328
    data = data | (BigInt(liquidationThreshold) << 16n);
    
    // Liquidation bonus (bits 32-47): 500 = 0x01F4
    data = data | (BigInt(liquidationBonus) << 32n);
    
    // Decimals (bits 48-55): 6
    data = data | (BigInt(decimals) << 48n);
    
    // Active flag (bit 56): 1
    data = data | (1n << 56n);
    
    // Borrowing enabled (bit 58): 1
    data = data | (1n << 58n);
    
    // Reserve factor (bits 64-79): 1000 = 0x03E8
    data = data | (BigInt(reserveFactor) << 64n);
    
    return { data: "0x" + data.toString(16).padStart(64, '0') };
  }

  // Create reserve configuration for USDC
  // LTV: 85% (8500), Liquidation threshold: 90% (9000), Liquidation bonus: 5% (500)
  // Reserve factor: 10% (1000), Decimals: 6
  const reserveConfigUSDC = buildReserveConfig(8500, 9000, 500, 6, 1000);

  await pool.initReserve(
    usdcAddress,
    aTokenUSDCAddress,
    variableDebtTokenUSDCAddress,
    interestRateStrategyAddress,
    reserveConfigUSDC
  );
  console.log("✅ USDC reserve initialized");

  // Create reserve configuration for USDT (same as USDC)
  const reserveConfigUSDT = buildReserveConfig(8500, 9000, 500, 6, 1000);

  await pool.initReserve(
    usdtAddress,
    aTokenUSDTAddress,
    variableDebtTokenUSDTAddress,
    interestRateStrategyAddress,
    reserveConfigUSDT
  );
  console.log("✅ USDT reserve initialized");

  // Step 8: Seed the pool with liquidity
  console.log("\n" + "=".repeat(80));
  console.log("Step 8: Seeding Pool with liquidity");
  console.log("=".repeat(80));

  const seedAmountUSDC = hre.ethers.parseUnits("500000", 6); // 500k USDC
  const seedAmountUSDT = hre.ethers.parseUnits("500000", 6); // 500k USDT

  // Approve with max amount
  const approveTx1 = await usdc.approve(poolAddress, hre.ethers.MaxUint256);
  await approveTx1.wait();
  console.log("✅ Approved USDC for pool");
  
  try {
    const supplyTx1 = await pool.supply(usdcAddress, seedAmountUSDC, deployer.address, 0);
    await supplyTx1.wait();
    console.log("✅ Supplied", hre.ethers.formatUnits(seedAmountUSDC, 6), "USDC to pool");
  } catch (error) {
    console.log("❌ Error supplying USDC:", error.message);
    // Try to get more details
    try {
      const reserveData = await pool.getReserveData(usdcAddress);
      console.log("  Reserve active:", reserveData.configuration.data.toString());
    } catch (e) {
      console.log("  Could not fetch reserve data");
    }
    throw error;
  }

  const approveTx2 = await usdt.approve(poolAddress, hre.ethers.MaxUint256);
  await approveTx2.wait();
  console.log("✅ Approved USDT for pool");
  
  try {
    const supplyTx2 = await pool.supply(usdtAddress, seedAmountUSDT, deployer.address, 0);
    await supplyTx2.wait();
    console.log("✅ Supplied", hre.ethers.formatUnits(seedAmountUSDT, 6), "USDT to pool");
  } catch (error) {
    console.log("❌ Error supplying USDT:", error.message);
    throw error;
  }

  // Step 9: Deploy LeveragedERC4626Vault
  console.log("\n" + "=".repeat(80));
  console.log("Step 9: Deploying LeveragedERC4626Vault");
  console.log("=".repeat(80));

  const LeveragedERC4626Vault = await hre.ethers.getContractFactory("LeveragedERC4626Vault");
  const vault = await LeveragedERC4626Vault.deploy(
    usdcAddress,
    "Leveraged USDC Vault",
    "lvUSDC",
    poolAddress,
    usdtAddress
  );
  await vault.waitForDeployment();
  const vaultAddress = await vault.getAddress();
  console.log("✅ LeveragedERC4626Vault deployed to:", vaultAddress);

  // Step 10: Test deposit and looping
  console.log("\n" + "=".repeat(80));
  console.log("Step 10: Testing Deposit and Looping");
  console.log("=".repeat(80));

  // Give user some USDC
  const userDepositAmount = hre.ethers.parseUnits("10000", 6); // 10k USDC
  await usdc.mint(user.address, userDepositAmount);
  console.log("✅ Minted", hre.ethers.formatUnits(userDepositAmount, 6), "USDC to user");

  // Check initial position
  console.log("\n📊 Initial Position:");
  const initialLTV = await vault.getCurrentLTV();
  const [initialCollateral, initialDebt, initialLTV2, initialHF] = await vault.getPositionDetails();
  console.log("  LTV:", initialLTV.toString(), "bps (", (Number(initialLTV) / 100).toFixed(2), "%)");
  console.log("  Collateral:", hre.ethers.formatUnits(initialCollateral, 6), "USDC");
  console.log("  Debt:", hre.ethers.formatUnits(initialDebt, 6), "USDT");
  console.log("  Health Factor:", hre.ethers.formatEther(initialHF));

  // User approves and deposits
  console.log("\n💰 User depositing...");
  await usdc.connect(user).approve(vaultAddress, userDepositAmount);
  const depositTx = await vault.connect(user).deposit(userDepositAmount, user.address);
  console.log("  Deposit transaction sent, waiting for confirmation...");
  const receipt = await depositTx.wait();
  console.log("  ✅ Deposit confirmed in block:", receipt.blockNumber);

  // Check position after deposit
  console.log("\n📊 Position After Deposit:");
  const afterDepositLTV = await vault.getCurrentLTV();
  const [afterDepositCollateral, afterDepositDebt, afterDepositLTV2, afterDepositHF] = await vault.getPositionDetails();
  console.log("  LTV:", afterDepositLTV.toString(), "bps (", (Number(afterDepositLTV) / 100).toFixed(2), "%)");
  console.log("  Collateral:", hre.ethers.formatUnits(afterDepositCollateral, 6));
  console.log("  Debt:", hre.ethers.formatUnits(afterDepositDebt, 6));
  console.log("  Health Factor:", hre.ethers.formatEther(afterDepositHF));

  // Check vault shares
  const userShares = await vault.balanceOf(user.address);
  const totalShares = await vault.totalSupply();
  const totalAssets = await vault.totalAssets();
  console.log("\n📈 Vault State:");
  console.log("  User shares:", hre.ethers.formatEther(userShares));
  console.log("  Total shares:", hre.ethers.formatEther(totalShares));
  console.log("  Total assets:", hre.ethers.formatUnits(totalAssets, 6));

  // Manually trigger looping to see it in action
  console.log("\n🔄 Manually triggering looping...");
  try {
    const loopTx = await vault.connect(user).executeLooping();
    const loopReceipt = await loopTx.wait();
    console.log("  ✅ Looping transaction confirmed in block:", loopReceipt.blockNumber);
    
    // Check for LoopExecuted event
    const loopEvent = loopReceipt.logs.find(log => {
      try {
        const parsed = vault.interface.parseLog(log);
        return parsed && parsed.name === "LoopExecuted";
      } catch {
        return false;
      }
    });
    
    if (loopEvent) {
      const parsed = vault.interface.parseLog(loopEvent);
      console.log("  📊 LoopExecuted Event:");
      console.log("    Collateral Supplied:", hre.ethers.formatUnits(parsed.args.collateralSupplied, 6));
      console.log("    Borrowed:", hre.ethers.formatUnits(parsed.args.borrowed, 6));
      console.log("    Iterations:", parsed.args.iterations.toString());
    }
  } catch (error) {
    console.log("  ⚠️  Looping failed (might already be at max LTV):", error.message);
  }

  // Final position check
  console.log("\n📊 Final Position:");
  const finalLTV = await vault.getCurrentLTV();
  const [finalCollateral, finalDebt, finalLTV2, finalHF] = await vault.getPositionDetails();
  console.log("  LTV:", finalLTV.toString(), "bps (", (Number(finalLTV) / 100).toFixed(2), "%)");
  console.log("  Collateral:", hre.ethers.formatUnits(finalCollateral, 6));
  console.log("  Debt:", hre.ethers.formatUnits(finalDebt, 6));
  console.log("  Health Factor:", hre.ethers.formatEther(finalHF));

  // Test rebalance
  console.log("\n" + "=".repeat(80));
  console.log("Step 11: Testing Rebalance");
  console.log("=".repeat(80));
  
  if (Number(finalLTV) > 8000) {
    console.log("  LTV is above 80%, triggering rebalance...");
    try {
      const rebalanceTx = await vault.connect(user).rebalance();
      const rebalanceReceipt = await rebalanceTx.wait();
      console.log("  ✅ Rebalance transaction confirmed in block:", rebalanceReceipt.blockNumber);
      
      const rebalanceEvent = rebalanceReceipt.logs.find(log => {
        try {
          const parsed = vault.interface.parseLog(log);
          return parsed && parsed.name === "Rebalanced";
        } catch {
          return false;
        }
      });
      
      if (rebalanceEvent) {
        const parsed = vault.interface.parseLog(rebalanceEvent);
        console.log("  📊 Rebalanced Event:");
        console.log("    Repaid:", hre.ethers.formatUnits(parsed.args.repaid, 6));
      }
    } catch (error) {
      console.log("  ⚠️  Rebalance failed:", error.message);
    }
  } else {
    console.log("  LTV is below 80%, no rebalance needed");
  }

  // Final summary
  console.log("\n" + "=".repeat(80));
  console.log("📋 Deployment Summary");
  console.log("=".repeat(80));
  console.log("USDC:", usdcAddress);
  console.log("USDT:", usdtAddress);
  console.log("PoolAddressesProvider:", addressesProviderAddress);
  console.log("Pool:", poolAddress);
  console.log("InterestRateStrategy:", interestRateStrategyAddress);
  console.log("aTokenUSDC:", aTokenUSDCAddress);
  console.log("variableDebtTokenUSDC:", variableDebtTokenUSDCAddress);
  console.log("aTokenUSDT:", aTokenUSDTAddress);
  console.log("variableDebtTokenUSDT:", variableDebtTokenUSDTAddress);
  console.log("LeveragedERC4626Vault:", vaultAddress);
  console.log("\n✅ Test completed successfully!");
  console.log("=".repeat(80));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Error:", error);
    process.exit(1);
  });

