// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FlashLoanReceiver
 * @dev Interface for contracts that can receive flash loans
 */
interface IFlashLoanReceiver {
    /**
     * @dev Called by the flash loan provider after lending tokens
     * @param token The address of the token being borrowed
     * @param amount The amount of tokens borrowed
     * @param fee The fee to be paid for the flash loan
     * @param data Additional data passed to the flash loan function
     * @return success Whether the operation was successful
     */
    function onFlashLoan(
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bool success);
}
