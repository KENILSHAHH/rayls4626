// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IInterestRateStrategy
 * @notice Interface for the calculation of the interest rates
 */
interface IInterestRateStrategy {
    /**
     * @notice Returns the variable borrow rate
     * @param utilizationRate The utilization rate expressed in ray
     * @return liquidityRate The liquidity rate, expressed in ray
     * @return variableBorrowRate The variable borrow rate, expressed in ray
     */
    function calculateInterestRates(
        uint256 utilizationRate
    ) external view returns (uint256 liquidityRate, uint256 variableBorrowRate);
}
