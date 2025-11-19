// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IAToken.sol";
import "./interfaces/IVariableDebtToken.sol";
import "./libraries/DataTypes.sol";
import "./libraries/ReserveConfiguration.sol";
import "./libraries/WadRayMath.sol";

/**
 * @title LeveragedERC4626Vault
 * @notice ERC4626 vault that implements leveraged looping strategy using Aave-style lending
 * @dev Users deposit assets, vault supplies to lending pool and borrows against it for leverage
 */
contract LeveragedERC4626Vault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    IPool public immutable lendingPool;
    IERC20 public immutable collateralAsset; // USDC
    IERC20 public immutable borrowAsset; // USDT

    uint256 public constant MAX_LTV_BPS = 9000; // 90% max LTV
    uint256 public constant REBALANCE_LTV_BPS = 8000; // 80% LTV threshold for rebalancing
    uint256 public constant BPS_DENOMINATOR = 10000;

    uint256 private constant RAY = 1e27;

    bool public loopingEnabled = true;
    uint256 public maxLoopIterations = 5; // Maximum number of loops to prevent gas issues

    event LoopExecuted(
        uint256 collateralSupplied,
        uint256 borrowed,
        uint256 iterations
    );
    event Rebalanced(uint256 repaid, uint256 withdrawn);
    event LoopingToggled(bool enabled);

    /**
     * @param asset_ The underlying asset (collateral asset, e.g., USDC)
     * @param name_ Name of the vault token
     * @param symbol_ Symbol of the vault token
     * @param lendingPool_ Address of the lending pool
     * @param borrowAsset_ Address of the asset to borrow (e.g., USDT)
     */
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address lendingPool_,
        address borrowAsset_
    ) ERC4626(asset_) ERC20(name_, symbol_) Ownable(msg.sender) {
        lendingPool = IPool(lendingPool_);
        collateralAsset = asset_;
        borrowAsset = IERC20(borrowAsset_);

        // Approve lending pool to spend collateral and borrow assets
        IERC20(address(asset_)).forceApprove(lendingPool_, type(uint256).max);
        borrowAsset.forceApprove(lendingPool_, type(uint256).max);
    }

    /**
     * @notice Override deposit to automatically execute looping after deposit
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares
     * @return shares Amount of shares minted
     */
    function deposit(
        uint256 assets,
        address receiver
    ) public override nonReentrant returns (uint256 shares) {
        uint256 supplyBefore = totalSupply();

        // Use parent implementation which handles share calculation correctly
        shares = super.deposit(assets, receiver);

        // Execute looping after deposit is complete
        // Only loop if this is not the first deposit (supplyBefore > 0)
        if (loopingEnabled && assets > 0 && supplyBefore > 0) {
            _executeLooping();
        }

        return shares;
    }

    /**
     * @notice Override mint to automatically execute looping after mint
     * @param shares Amount of shares to mint
     * @param receiver Address to receive shares
     * @return assets Amount of assets deposited
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override nonReentrant returns (uint256 assets) {
        assets = super.mint(shares, receiver);

        if (loopingEnabled && assets > 0) {
            _executeLooping();
        }

        return assets;
    }

    /**
     * @notice Override withdraw to handle rebalancing if needed
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets
     * @param owner Address that owns the shares
     * @return shares Amount of shares burned
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 shares) {
        // Check and rebalance if LTV is too high
        _checkAndRebalance();

        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @notice Override redeem to handle rebalancing if needed
     * @param shares Amount of shares to redeem
     * @param receiver Address to receive assets
     * @param owner Address that owns the shares
     * @return assets Amount of assets withdrawn
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override nonReentrant returns (uint256 assets) {
        // Check and rebalance if LTV is too high
        _checkAndRebalance();

        return super.redeem(shares, receiver, owner);
    }

    /**
     * @notice Execute looping strategy: supply collateral, borrow, supply borrowed amount
     * @dev This function loops to maximize leverage up to MAX_LTV_BPS
     */
    function executeLooping() external {
        _executeLooping();
    }

    /**
     * @notice Rebalance position by repaying debt when LTV exceeds threshold
     */
    function rebalance() external {
        _rebalance();
    }

    /**
     * @notice Get current LTV (Loan-to-Value) ratio in basis points
     * @return Current LTV in basis points
     */
    function getCurrentLTV() public view returns (uint256) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            ,
            ,

        ) = lendingPool.getUserAccountData(address(this));

        if (totalCollateralBase == 0) {
            return 0;
        }

        return (totalDebtBase * BPS_DENOMINATOR) / totalCollateralBase;
    }

    /**
     * @notice Get current position details
     * @return collateralSupplied Total collateral supplied to lending pool
     * @return debtBorrowed Total debt borrowed
     * @return currentLTV Current LTV in basis points
     * @return healthFactor Current health factor
     */
    function getPositionDetails()
        external
        view
        returns (
            uint256 collateralSupplied,
            uint256 debtBorrowed,
            uint256 currentLTV,
            uint256 healthFactor
        )
    {
        (, , , , , uint256 hf) = lendingPool.getUserAccountData(address(this));

        // Get actual collateral supplied (aToken balance * liquidity index)
        DataTypes.ReserveData memory collateralReserve = lendingPool
            .getReserveData(address(collateralAsset));
        uint256 aTokenBalance = IAToken(collateralReserve.aTokenAddress)
            .balanceOf(address(this));
        uint256 collateralSuppliedFromCollateral = aTokenBalance.rayMul(
            uint256(collateralReserve.liquidityIndex)
        );

        // Get borrow asset collateral if any
        DataTypes.ReserveData memory borrowReserve = lendingPool.getReserveData(
            address(borrowAsset)
        );
        uint256 borrowATokenBalance = IAToken(borrowReserve.aTokenAddress)
            .balanceOf(address(this));
        uint256 collateralSuppliedFromBorrow = borrowATokenBalance.rayMul(
            uint256(borrowReserve.liquidityIndex)
        );

        collateralSupplied =
            collateralSuppliedFromCollateral +
            collateralSuppliedFromBorrow;

        // Get actual debt (variableDebtToken balance * borrow index)
        uint256 variableBorrowIndex = uint256(
            borrowReserve.variableBorrowIndex
        );
        uint256 debtTokenBalance = IVariableDebtToken(
            borrowReserve.variableDebtTokenAddress
        ).scaledBalanceOf(address(this));
        debtBorrowed = debtTokenBalance.rayMul(variableBorrowIndex);

        currentLTV = getCurrentLTV();
        healthFactor = hf;
    }

    /**
     * @notice Override totalAssets to account for leveraged position
     * @return Total assets including leveraged position value
     */
    function totalAssets() public view override returns (uint256) {
        // Get assets currently in the vault (not yet supplied to lending pool)
        uint256 assetsInVault = collateralAsset.balanceOf(address(this));
        
        // Get position in lending pool
        // Note: getUserAccountData will return zeros if no position exists
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            ,
            ,
            ,

        ) = lendingPool.getUserAccountData(address(this));

        // Net assets = assets in vault + (collateral in pool - debt)
        uint256 netPoolPosition = 0;
        if (totalCollateralBase >= totalDebtBase) {
            unchecked {
                netPoolPosition = totalCollateralBase - totalDebtBase;
            }
        }
        
        return assetsInVault + netPoolPosition;
    }

    /**
     * @notice Toggle looping functionality
     * @param enabled Whether to enable looping
     */
    function setLoopingEnabled(bool enabled) external onlyOwner {
        loopingEnabled = enabled;
        emit LoopingToggled(enabled);
    }

    /**
     * @notice Set maximum loop iterations
     * @param iterations Maximum number of loops
     */
    function setMaxLoopIterations(uint256 iterations) external onlyOwner {
        require(iterations > 0 && iterations <= 10, "INVALID_ITERATIONS");
        maxLoopIterations = iterations;
    }

    /**
     * @dev Internal function to execute looping strategy
     * Strategy: Supply USDC -> Borrow USDT -> Supply USDT -> Repeat
     */
    function _executeLooping() internal {
        // First, supply any available collateral asset to the pool
        uint256 availableCollateral = collateralAsset.balanceOf(address(this));
        if (availableCollateral > 0) {
            lendingPool.supply(
                address(collateralAsset),
                availableCollateral,
                address(this),
                0
            );
        }
        
        // Skip if no assets in vault and no position in pool
        if (totalAssets() == 0) {
            return;
        }
        
        uint256 currentLTV = getCurrentLTV();

        // Don't loop if already at max LTV
        if (currentLTV >= MAX_LTV_BPS) {
            return;
        }

        uint256 iterations = 0;
        uint256 totalBorrowed = 0;

        while (iterations < maxLoopIterations) {
            currentLTV = getCurrentLTV();

            // Stop if we've reached max LTV
            if (currentLTV >= MAX_LTV_BPS) {
                break;
            }

            // Calculate how much we can borrow (in borrow asset terms)
            (
                uint256 totalCollateralBase,
                uint256 totalDebtBase,
                ,
                ,
                ,

            ) = lendingPool.getUserAccountData(address(this));
            uint256 maxBorrowableValue = ((totalCollateralBase * MAX_LTV_BPS) /
                BPS_DENOMINATOR) - totalDebtBase;

            if (maxBorrowableValue == 0) {
                break;
            }

            // Check available liquidity in the lending pool for borrow asset
            // Note: In a real implementation, you'd need to check the pool's available liquidity
            // For now, we'll use a conservative approach
            uint256 availableLiquidity = IERC20(address(borrowAsset)).balanceOf(
                address(lendingPool)
            );

            // Borrow amount is limited by: max borrowable value, available liquidity, and current debt capacity
            uint256 borrowAmount = maxBorrowableValue;
            if (availableLiquidity < borrowAmount) {
                borrowAmount = availableLiquidity;
            }

            if (borrowAmount == 0) {
                break;
            }

            // Borrow USDT
            try
                lendingPool.borrow(
                    address(borrowAsset),
                    borrowAmount,
                    2,
                    0,
                    address(this)
                )
            {
                totalBorrowed += borrowAmount;

                // Supply the borrowed USDT as collateral (if USDT can be used as collateral)
                // Otherwise, swap or handle differently
                // For this implementation, we'll supply it back to increase our collateral
                uint256 borrowedBalance = borrowAsset.balanceOf(address(this));
                if (borrowedBalance > 0) {
                    // If borrow asset can be supplied as collateral, supply it
                    // Otherwise, you'd need a swap mechanism here
                    try
                        lendingPool.supply(
                            address(borrowAsset),
                            borrowedBalance,
                            address(this),
                            0
                        )
                    {
                        // Successfully supplied borrowed asset
                    } catch {
                        // If supplying borrow asset fails, we can't continue the loop
                        break;
                    }
                }
            } catch {
                // Borrow failed, stop looping
                break;
            }

            iterations++;
        }

        if (iterations > 0 || totalBorrowed > 0) {
            (uint256 totalCollateralBase, ) = _getPosition();
            emit LoopExecuted(totalCollateralBase, totalBorrowed, iterations);
        }
    }

    /**
     * @dev Check LTV and rebalance if needed
     */
    function _checkAndRebalance() internal {
        uint256 currentLTV = getCurrentLTV();

        if (currentLTV > REBALANCE_LTV_BPS) {
            _rebalance();
        }
    }

    /**
     * @dev Rebalance position by repaying debt to bring LTV below threshold
     */
    function _rebalance() internal {
        uint256 currentLTV = getCurrentLTV();

        if (currentLTV <= REBALANCE_LTV_BPS) {
            return; // Already balanced
        }

        (uint256 totalCollateralBase, uint256 totalDebtBase) = _getPosition();

        // Calculate target debt (80% of collateral)
        uint256 targetDebt = (totalCollateralBase * REBALANCE_LTV_BPS) /
            BPS_DENOMINATOR;
        uint256 debtToRepay = totalDebtBase - targetDebt;

        if (debtToRepay == 0) {
            return;
        }

        // Get borrow asset balance
        uint256 borrowAssetBalance = borrowAsset.balanceOf(address(this));

        // If we don't have enough, withdraw some collateral
        if (borrowAssetBalance < debtToRepay) {
            uint256 needed = debtToRepay - borrowAssetBalance;
            _withdrawCollateralForRepayment(needed);
        }

        // Repay debt
        uint256 actualRepay = borrowAsset.balanceOf(address(this));
        if (actualRepay > debtToRepay) {
            actualRepay = debtToRepay;
        }

        if (actualRepay > 0) {
            lendingPool.repay(
                address(borrowAsset),
                actualRepay,
                2,
                address(this)
            );
            emit Rebalanced(actualRepay, 0);
        }
    }

    /**
     * @dev Withdraw collateral to get borrow asset for repayment
     * Note: In a production system, you'd typically swap collateral to borrow asset
     * For this implementation, we withdraw collateral asset
     */
    function _withdrawCollateralForRepayment(uint256 needed) internal {
        // Withdraw from borrow asset collateral if available
        DataTypes.ReserveData memory borrowReserve = lendingPool.getReserveData(
            address(borrowAsset)
        );
        uint256 borrowATokenBalance = IAToken(borrowReserve.aTokenAddress)
            .balanceOf(address(this));

        if (borrowATokenBalance > 0) {
            uint256 liquidityIndex = uint256(borrowReserve.liquidityIndex);
            uint256 availableAmount = borrowATokenBalance.rayMul(
                liquidityIndex
            );

            uint256 withdrawAmount = needed;
            if (withdrawAmount > availableAmount) {
                withdrawAmount = availableAmount;
            }

            if (withdrawAmount > 0) {
                lendingPool.withdraw(
                    address(borrowAsset),
                    withdrawAmount,
                    address(this)
                );
            }
        }

        // If still not enough, withdraw from collateral asset
        uint256 stillNeeded = needed > borrowAsset.balanceOf(address(this))
            ? needed - borrowAsset.balanceOf(address(this))
            : 0;

        if (stillNeeded > 0) {
            DataTypes.ReserveData memory collateralReserve = lendingPool
                .getReserveData(address(collateralAsset));
            uint256 aTokenBalance = IAToken(collateralReserve.aTokenAddress)
                .balanceOf(address(this));

            if (aTokenBalance > 0) {
                uint256 liquidityIndex = uint256(
                    collateralReserve.liquidityIndex
                );
                uint256 availableAmount = aTokenBalance.rayMul(liquidityIndex);

                uint256 withdrawAmount = stillNeeded;
                if (withdrawAmount > availableAmount) {
                    withdrawAmount = availableAmount;
                }

                if (withdrawAmount > 0) {
                    lendingPool.withdraw(
                        address(collateralAsset),
                        withdrawAmount,
                        address(this)
                    );
                }
            }
        }
    }

    /**
     * @dev Get current position values
     */
    function _getPosition()
        internal
        view
        returns (uint256 totalCollateralBase, uint256 totalDebtBase)
    {
        (totalCollateralBase, totalDebtBase, , , , ) = lendingPool
            .getUserAccountData(address(this));
    }
}
