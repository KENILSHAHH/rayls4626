// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPool.sol";
import "../interfaces/IAToken.sol";
import "../interfaces/IVariableDebtToken.sol";
import "../interfaces/IInterestRateStrategy.sol";
import "../libraries/DataTypes.sol";
import "../libraries/ReserveConfiguration.sol";
import "../libraries/WadRayMath.sol";

/**
 * @title Pool
 * @notice Main entry point for lending and borrowing operations
 */
contract Pool is IPool, Ownable {
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    IPoolAddressesProvider public immutable ADDRESSES_PROVIDER;
    uint256 public constant MAX_NUMBER_RESERVES = 128;
    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18;

    mapping(address => DataTypes.ReserveData) internal _reserves;
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;
    mapping(uint256 => address) internal _reservesList;
    uint256 internal _reservesCount;

    modifier onlyPoolAdmin() {
        require(owner() == msg.sender, "CALLER_NOT_POOL_ADMIN");
        _;
    }

    constructor(address addressesProvider) Ownable(msg.sender) {
        ADDRESSES_PROVIDER = IPoolAddressesProvider(addressesProvider);
    }

    /**
     * @notice Initializes a reserve
     * @param asset The address of the underlying asset of the reserve
     * @param aTokenAddress The address of the aToken that will be assigned to the reserve
     * @param variableDebtTokenAddress The address of the VariableDebtToken that will be assigned to the reserve
     * @param interestRateStrategyAddress The address of the interest rate strategy contract
     * @param reserveConfiguration The configuration of the reserve
     */
    function initReserve(
        address asset,
        address aTokenAddress,
        address variableDebtTokenAddress,
        address interestRateStrategyAddress,
        DataTypes.ReserveConfigurationMap memory reserveConfiguration
    ) external onlyPoolAdmin {
        require(!_reserves[asset].configuration.getActive(), "RESERVE_ALREADY_INITIALIZED");
        require(aTokenAddress != address(0), "INVALID_ATOKEN_ADDRESS");
        require(variableDebtTokenAddress != address(0), "INVALID_DEBT_TOKEN_ADDRESS");
        require(interestRateStrategyAddress != address(0), "INVALID_INTEREST_RATE_STRATEGY_ADDRESS");
        require(_reservesCount < MAX_NUMBER_RESERVES, "NO_MORE_RESERVES_ALLOWED");

        _reserves[asset].configuration = reserveConfiguration;
        _reserves[asset].aTokenAddress = aTokenAddress;
        _reserves[asset].variableDebtTokenAddress = variableDebtTokenAddress;
        _reserves[asset].interestRateStrategyAddress = interestRateStrategyAddress;
        _reserves[asset].id = uint16(_reservesCount);
        _reserves[asset].liquidityIndex = uint128(WadRayMath.RAY);
        _reserves[asset].variableBorrowIndex = uint128(WadRayMath.RAY);
        _reserves[asset].lastUpdateTimestamp = uint40(block.timestamp);

        _reservesList[_reservesCount] = asset;
        _reservesCount++;

        _reserves[asset].configuration.setActive(true);
    }

    /**
     * @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external override {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.configuration.getActive(), "RESERVE_NOT_ACTIVE");
        require(!reserve.configuration.getFrozen(), "RESERVE_FROZEN");

        _updateInterestRates(asset);

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        uint256 liquidityIndex = uint256(reserve.liquidityIndex);
        uint256 amountToMint = amount.rayDiv(liquidityIndex);
        IAToken(reserve.aTokenAddress).mint(onBehalfOf, amountToMint);

        emit Supply(asset, msg.sender, onBehalfOf, amount, referralCode);
    }

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     * @param to The address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external override returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.configuration.getActive(), "RESERVE_NOT_ACTIVE");

        _updateInterestRates(asset);

        uint256 liquidityIndex = uint256(reserve.liquidityIndex);
        uint256 userBalance = IAToken(reserve.aTokenAddress).balanceOf(msg.sender);
        uint256 amountToWithdraw = amount;

        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance.rayMul(liquidityIndex);
        }

        require(amountToWithdraw > 0, "INVALID_AMOUNT");
        require(userBalance >= amountToWithdraw.rayDiv(liquidityIndex), "INSUFFICIENT_BALANCE");

        uint256 amountToBurn = amountToWithdraw.rayDiv(liquidityIndex);
        IAToken(reserve.aTokenAddress).burn(msg.sender, to, amountToBurn);

        IERC20(asset).safeTransfer(to, amountToWithdraw);

        emit Withdraw(asset, msg.sender, to, amountToWithdraw);

        return amountToWithdraw;
    }

    /**
     * @notice Allows users to borrow a specific `amount` of the reserve underlying asset
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param interestRateMode The interest rate mode at which the user wants to borrow: 1 for Stable, 2 for Variable
     * @param referralCode The code used to register the integrator originating the operation, for potential rewards.
     * @param onBehalfOf The address of the user who will receive the debt
     */
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external override {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.configuration.getActive(), "RESERVE_NOT_ACTIVE");
        require(!reserve.configuration.getFrozen(), "RESERVE_FROZEN");
        require(reserve.configuration.getBorrowingEnabled(), "BORROWING_NOT_ENABLED");
        require(interestRateMode == uint256(DataTypes.InterestRateMode.VARIABLE), "INVALID_INTEREST_RATE_MODE_SELECTED");

        _updateInterestRates(asset);

        uint256 availableLiquidity = IERC20(asset).balanceOf(address(this));
        require(availableLiquidity >= amount, "NOT_ENOUGH_AVAILABLE_USER_BALANCE");

        // Check health factor
        (,,,,, uint256 healthFactor) = getUserAccountData(onBehalfOf);
        require(healthFactor > HEALTH_FACTOR_LIQUIDATION_THRESHOLD, "HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD");

        uint256 currentVariableBorrowIndex = uint256(reserve.variableBorrowIndex);
        IVariableDebtToken(reserve.variableDebtTokenAddress).mint(
            msg.sender,
            onBehalfOf,
            amount,
            currentVariableBorrowIndex
        );

        IERC20(asset).safeTransfer(msg.sender, amount);

        emit Borrow(asset, msg.sender, onBehalfOf, amount, interestRateMode, referralCode);
    }

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param amount The amount to repay
     * @param rateMode The interest rate mode at of the debt the user wants to repay: 1 for Stable, 2 for Variable
     * @param onBehalfOf The address of the user who will get his debt reduced/removed
     * @return The final amount repaid
     */
    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external override returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        require(reserve.configuration.getActive(), "RESERVE_NOT_ACTIVE");
        require(rateMode == uint256(DataTypes.InterestRateMode.VARIABLE), "INVALID_INTEREST_RATE_MODE_SELECTED");

        _updateInterestRates(asset);

        uint256 variableBorrowIndex = uint256(reserve.variableBorrowIndex);
        uint256 userVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).balanceOf(
            onBehalfOf,
            variableBorrowIndex
        );

        uint256 amountToRepay = amount;
        if (amount == type(uint256).max) {
            amountToRepay = userVariableDebt;
        }

        require(amountToRepay > 0, "INVALID_AMOUNT");
        require(userVariableDebt >= amountToRepay, "INSUFFICIENT_DEBT");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amountToRepay);

        IVariableDebtToken(reserve.variableDebtTokenAddress).burn(onBehalfOf, amountToRepay, variableBorrowIndex);

        emit Repay(asset, msg.sender, onBehalfOf, amountToRepay);

        return amountToRepay;
    }

    /**
     * @notice Returns the user account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralBase The total collateral of the user
     * @return totalDebtBase The total debt of the user
     * @return availableBorrowsBase The borrowing power left of the user
     * @return currentLiquidationThreshold The liquidation threshold of the user
     * @return ltv The loan to value of The user
     * @return healthFactor The current health factor of the user
     */
    function getUserAccountData(
        address user
    )
        public
        view
        override
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        (totalCollateralBase, totalDebtBase, ltv, currentLiquidationThreshold) = _calculateUserAccountData(user);

        if (totalCollateralBase > 0) {
            availableBorrowsBase = totalCollateralBase.rayMul(ltv) - totalDebtBase;
        }

        if (totalDebtBase > 0) {
            healthFactor = totalCollateralBase.rayMul(currentLiquidationThreshold).rayDiv(totalDebtBase);
        } else {
            healthFactor = type(uint256).max;
        }
    }

    /**
     * @dev Internal function to calculate user account data
     */
    function _calculateUserAccountData(
        address user
    ) internal view returns (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 ltv, uint256 currentLiquidationThreshold) {
        uint256 reservesLength = _reservesCount;
        uint256 weightedLtv;
        uint256 weightedLiquidationThreshold;

        for (uint256 i = 0; i < reservesLength; i++) {
            address reserveAddress = _reservesList[i];
            DataTypes.ReserveData storage reserve = _reserves[reserveAddress];

            uint256 userBalance = IAToken(reserve.aTokenAddress).balanceOf(user);
            if (userBalance > 0) {
                uint256 liquidityIndex = uint256(reserve.liquidityIndex);
                uint256 collateralValue = userBalance.rayMul(liquidityIndex);
                totalCollateralBase += collateralValue;
                weightedLtv += collateralValue.rayMul(reserve.configuration.getLtv());
                weightedLiquidationThreshold += collateralValue.rayMul(
                    reserve.configuration.getLiquidationThreshold()
                );
            }

            uint256 variableBorrowIndex = uint256(reserve.variableBorrowIndex);
            uint256 userDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).balanceOf(
                user,
                variableBorrowIndex
            );
            if (userDebt > 0) {
                totalDebtBase += userDebt;
            }
        }

        if (totalCollateralBase > 0) {
            ltv = weightedLtv.rayDiv(totalCollateralBase);
            currentLiquidationThreshold = weightedLiquidationThreshold.rayDiv(totalCollateralBase);
        }
    }

    /**
     * @notice Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     */
    function getConfiguration(
        address asset
    ) external view override returns (DataTypes.ReserveConfigurationMap memory) {
        return _reserves[asset].configuration;
    }

    /**
     * @notice Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     */
    function getReserveData(address asset) external view override returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }

    /**
     * @notice Updates the liquidity and variable borrow indexes
     * @param asset The address of the underlying asset of the reserve
     */
    function _updateInterestRates(address asset) internal {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        uint256 availableLiquidity = IERC20(asset).balanceOf(address(this));
        uint256 variableBorrowIndex = uint256(reserve.variableBorrowIndex);
        uint256 totalVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).scaledTotalSupply().rayMul(
            variableBorrowIndex
        );

        uint256 utilizationRate = 0;
        if (availableLiquidity + totalVariableDebt > 0) {
            utilizationRate = totalVariableDebt.rayDiv(availableLiquidity + totalVariableDebt);
        }

        (uint256 newLiquidityRate, uint256 newVariableBorrowRate) = IInterestRateStrategy(
            reserve.interestRateStrategyAddress
        ).calculateInterestRates(utilizationRate);

        reserve.currentLiquidityRate = uint128(newLiquidityRate);
        reserve.currentVariableBorrowRate = uint128(newVariableBorrowRate);
        
        uint40 lastUpdateTimestamp = reserve.lastUpdateTimestamp;
        uint256 timeDelta = block.timestamp - lastUpdateTimestamp;
        reserve.lastUpdateTimestamp = uint40(block.timestamp);

        // Update indexes
        uint256 liquidityIndex = uint256(reserve.liquidityIndex);
        if (timeDelta > 0) {
            liquidityIndex = liquidityIndex.rayMul(
                WadRayMath.RAY + (newLiquidityRate * timeDelta) / 365 days
            );
            variableBorrowIndex = variableBorrowIndex.rayMul(
                WadRayMath.RAY + (newVariableBorrowRate * timeDelta) / 365 days
            );
        }
        reserve.liquidityIndex = uint128(liquidityIndex);
        reserve.variableBorrowIndex = uint128(variableBorrowIndex);
    }

    event Supply(address indexed reserve, address user, address onBehalfOf, uint256 amount, uint16 indexed referral);
    event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRateMode,
        uint16 indexed referral
    );
    event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount);
}

