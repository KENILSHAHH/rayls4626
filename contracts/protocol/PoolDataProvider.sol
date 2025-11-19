// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPool.sol";
import "../interfaces/IAToken.sol";
import "../interfaces/IVariableDebtToken.sol";
import "../libraries/DataTypes.sol";
import "../libraries/ReserveConfiguration.sol";
import "../libraries/WadRayMath.sol";

/**
 * @title PoolDataProvider
 * @notice Provides methods to access pool data
 */
contract PoolDataProvider {
    IPool public immutable POOL;

    constructor(address pool) {
        POOL = IPool(pool);
    }

    /**
     * @notice Returns the reserve data
     * @param asset The address of the underlying asset of the reserve
     * @return totalATokenSupply The total supply of aTokens
     * @return totalVariableDebt The total variable debt
     * @return liquidityRate The liquidity rate
     * @return variableBorrowRate The variable borrow rate
     * @return liquidityIndex The liquidity index
     * @return variableBorrowIndex The variable borrow index
     * @return lastUpdateTimestamp The last update timestamp
     */
    function getReserveData(address asset)
        external
        view
        returns (
            uint256 totalATokenSupply,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        )
    {
        DataTypes.ReserveData memory reserve = POOL.getReserveData(asset);

        totalATokenSupply = IAToken(reserve.aTokenAddress).totalSupply();
        totalVariableDebt = WadRayMath.rayMul(
            IVariableDebtToken(reserve.variableDebtTokenAddress).scaledTotalSupply(),
            reserve.variableBorrowIndex
        );
        liquidityRate = reserve.currentLiquidityRate;
        variableBorrowRate = reserve.currentVariableBorrowRate;
        liquidityIndex = reserve.liquidityIndex;
        variableBorrowIndex = reserve.variableBorrowIndex;
        lastUpdateTimestamp = reserve.lastUpdateTimestamp;
    }

    /**
     * @notice Returns the user reserve data
     * @param asset The address of the underlying asset of the reserve
     * @param user The address of the user
     * @return currentATokenBalance The current aToken balance
     * @return currentVariableDebt The current variable debt
     * @return principalVariableDebt The principal variable debt
     * @return liquidityRate The liquidity rate
     * @return variableBorrowRate The variable borrow rate
     */
    function getUserReserveData(address asset, address user)
        external
        view
        returns (
            uint256 currentATokenBalance,
            uint256 currentVariableDebt,
            uint256 principalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate
        )
    {
        DataTypes.ReserveData memory reserve = POOL.getReserveData(asset);

        currentATokenBalance = IAToken(reserve.aTokenAddress).balanceOf(user);
        currentVariableDebt = IVariableDebtToken(reserve.variableDebtTokenAddress).balanceOf(
            user,
            reserve.variableBorrowIndex
        );
        principalVariableDebt = WadRayMath.rayMul(
            IVariableDebtToken(reserve.variableDebtTokenAddress).scaledBalanceOf(user),
            reserve.variableBorrowIndex
        );
        liquidityRate = reserve.currentLiquidityRate;
        variableBorrowRate = reserve.currentVariableBorrowRate;
    }
}

