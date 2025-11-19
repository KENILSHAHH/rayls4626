// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./FlashLoanReceiver.sol";
import "./FlashLoanProvider.sol";

/**
 * @title ExampleFlashLoanReceiver
 * @dev Example contract demonstrating how to use the FlashLoanProvider
 * This contract implements the IFlashLoanReceiver interface
 */
contract ExampleFlashLoanReceiver is IFlashLoanReceiver {
    using SafeERC20 for IERC20;

    FlashLoanProvider public immutable flashLoanProvider;

    constructor(address _flashLoanProvider) {
        flashLoanProvider = FlashLoanProvider(_flashLoanProvider);
    }

    /**
     * @dev Execute a flash loan
     * @param token The token to borrow
     * @param amount The amount to borrow
     * @param data Additional data (can be used to pass custom logic)
     */
    function executeFlashLoan(
        address token,
        uint256 amount,
        bytes calldata data
    ) external {
        flashLoanProvider.flashLoan(token, amount, data);
    }

    /**
     * @dev Callback function called by FlashLoanProvider after lending tokens
     * @param token The token address
     * @param amount The amount borrowed
     * @param fee The fee to be paid
     * @param data Additional data passed to flashLoan
     * @return success Whether the operation was successful
     */
    function onFlashLoan(
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bool success) {
        data; // Silence unused parameter warning
        // Verify the caller is the flash loan provider
        require(
            msg.sender == address(flashLoanProvider),
            "ExampleFlashLoanReceiver: invalid caller"
        );

        // Your custom logic here
        // For example: arbitrage, liquidation, collateral swap, etc.
        // The contract must have enough tokens to repay amount + fee

        // Calculate total repayment
        uint256 repaymentAmount = amount + fee;

        // Transfer repayment (including fee) back to the provider
        IERC20(token).safeTransfer(address(flashLoanProvider), repaymentAmount);

        return true;
    }

    /**
     * @dev Withdraw any tokens that may have been left in this contract
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdrawToken(address token, uint256 amount) external {
        IERC20(token).safeTransfer(msg.sender, amount);
    }
}
