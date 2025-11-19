// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./FlashLoanReceiver.sol";

/**
 * @title FlashLoanProvider
 * @dev Standard flash loan provider contract following ERC-3156 pattern
 * Allows users to borrow tokens without collateral, as long as they repay in the same transaction
 */
contract FlashLoanProvider is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Flash loan fee in basis points (1 basis point = 0.01%)
    uint256 public constant FLASH_LOAN_FEE_BPS = 9; // 0.09% fee
    uint256 public constant BPS_DENOMINATOR = 10000;

    // Mapping to track supported tokens
    mapping(address => bool) public supportedTokens;

    // Events
    event FlashLoan(
        address indexed borrower,
        address indexed token,
        uint256 amount,
        uint256 fee
    );
    event TokenSupported(address indexed token, bool supported);
    event FeesWithdrawn(address indexed token, uint256 amount);

    /**
     * @dev Constructor
     * @param initialOwner The address that will own the contract
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @dev Enable or disable a token for flash loans
     * @param token The token address
     * @param supported Whether the token is supported
     */
    function setSupportedToken(
        address token,
        bool supported
    ) external onlyOwner {
        supportedTokens[token] = supported;
        emit TokenSupported(token, supported);
    }

    /**
     * @dev Execute a flash loan
     * @param token The address of the token to borrow
     * @param amount The amount of tokens to borrow
     * @param data Additional data to pass to the receiver callback
     */
    function flashLoan(
        address token,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant {
        require(
            supportedTokens[token],
            "FlashLoanProvider: token not supported"
        );
        require(amount > 0, "FlashLoanProvider: amount must be greater than 0");

        IERC20 tokenContract = IERC20(token);

        // Calculate fee
        uint256 fee = (amount * FLASH_LOAN_FEE_BPS) / BPS_DENOMINATOR;

        // Check contract has enough balance
        uint256 contractBalance = tokenContract.balanceOf(address(this));
        require(
            contractBalance >= amount,
            "FlashLoanProvider: insufficient liquidity"
        );

        // Record initial balance
        uint256 balanceBefore = tokenContract.balanceOf(address(this));

        // Transfer tokens to borrower
        tokenContract.safeTransfer(msg.sender, amount);

        // Call receiver callback
        bool success = IFlashLoanReceiver(msg.sender).onFlashLoan(
            token,
            amount,
            fee,
            data
        );
        require(success, "FlashLoanProvider: flash loan callback failed");

        // Verify repayment
        uint256 balanceAfter = tokenContract.balanceOf(address(this));
        require(
            balanceAfter >= balanceBefore + fee,
            "FlashLoanProvider: insufficient repayment"
        );

        emit FlashLoan(msg.sender, token, amount, fee);
    }

    /**
     * @dev Get the maximum flash loan amount for a token
     * @param token The token address
     * @return The maximum amount available for flash loan
     */
    function maxFlashLoan(address token) external view returns (uint256) {
        if (!supportedTokens[token]) {
            return 0;
        }
        return IERC20(token).balanceOf(address(this));
    }

    function flashFee(
        address _token,
        uint256 amount
    ) external pure returns (uint256) {
        _token; // Silence unused parameter warning
        return (amount * FLASH_LOAN_FEE_BPS) / BPS_DENOMINATOR;
    }

    /**
     * @dev Check if a token is supported for flash loans
     * @param token The token address
     * @return Whether the token is supported
     */
    function isSupportedToken(address token) external view returns (bool) {
        return supportedTokens[token];
    }

    /**
     * @dev Deposit tokens to the contract to enable flash loans
     * @param token The token address
     * @param amount The amount to deposit
     */
    function deposit(address token, uint256 amount) external {
        require(
            supportedTokens[token],
            "FlashLoanProvider: token not supported"
        );
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Withdraw accumulated fees
     * @param token The token address
     * @param amount The amount to withdraw
     */
    function withdrawFees(address token, uint256 amount) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(amount <= balance, "FlashLoanProvider: insufficient balance");

        tokenContract.safeTransfer(owner(), amount);
        emit FeesWithdrawn(token, amount);
    }

    /**
     * @dev Emergency withdraw all tokens (only owner)
     * @param token The token address
     */
    function emergencyWithdraw(address token) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        tokenContract.safeTransfer(owner(), balance);
        emit FeesWithdrawn(token, balance);
    }
}
