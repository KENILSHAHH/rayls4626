// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IInterestRateStrategy.sol";
import "../libraries/WadRayMath.sol";

/**
 * @title InterestRateStrategy
 * @notice Implements the calculation of the interest rates
 */
contract InterestRateStrategy is IInterestRateStrategy {
    using WadRayMath for uint256;

    uint256 public immutable OPTIMAL_UTILIZATION_RATE;
    uint256 public immutable BASE_VARIABLE_BORROW_RATE;
    uint256 public immutable VARIABLE_RATE_SLOPE_1;
    uint256 public immutable VARIABLE_RATE_SLOPE_2;

    constructor(
        uint256 optimalUtilizationRate,
        uint256 baseVariableBorrowRate,
        uint256 variableRateSlope1,
        uint256 variableRateSlope2
    ) {
        OPTIMAL_UTILIZATION_RATE = optimalUtilizationRate;
        BASE_VARIABLE_BORROW_RATE = baseVariableBorrowRate;
        VARIABLE_RATE_SLOPE_1 = variableRateSlope1;
        VARIABLE_RATE_SLOPE_2 = variableRateSlope2;
    }

    /**
     * @notice Calculates the interest rates depending on the reserve's state and configurations
     * @param utilizationRate The utilization rate expressed in ray
     * @return liquidityRate The liquidity rate in ray
     * @return variableBorrowRate The variable borrow rate in ray
     */
    function calculateInterestRates(
        uint256 utilizationRate
    ) external view override returns (uint256 liquidityRate, uint256 variableBorrowRate) {
        if (utilizationRate > OPTIMAL_UTILIZATION_RATE) {
            uint256 excessUtilizationRateRatio = (utilizationRate - OPTIMAL_UTILIZATION_RATE).rayDiv(
                (WadRayMath.RAY - OPTIMAL_UTILIZATION_RATE)
            );
            variableBorrowRate =
                BASE_VARIABLE_BORROW_RATE +
                VARIABLE_RATE_SLOPE_1 +
                VARIABLE_RATE_SLOPE_2.rayMul(excessUtilizationRateRatio);
        } else {
            variableBorrowRate =
                BASE_VARIABLE_BORROW_RATE +
                VARIABLE_RATE_SLOPE_1.rayMul(utilizationRate).rayDiv(OPTIMAL_UTILIZATION_RATE);
        }

        liquidityRate = variableBorrowRate.rayMul(utilizationRate);
    }
}

