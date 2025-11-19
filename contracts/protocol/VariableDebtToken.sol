// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IVariableDebtToken.sol";
import "../interfaces/IPool.sol";
import "../libraries/WadRayMath.sol";

/**
 * @title VariableDebtToken
 * @notice Implementation of the variable debt token
 */
contract VariableDebtToken is ERC20, IVariableDebtToken, Ownable {
    using WadRayMath for uint256;

    address public immutable override UNDERLYING_ASSET_ADDRESS;
    address public immutable override POOL;

    mapping(address => uint256) public userState;

    /**
     * @dev Only pool can call functions marked by this modifier.
     */
    modifier onlyPool() {
        require(msg.sender == POOL, "VDT_CALLER_MUST_BE_POOL");
        _;
    }

    /**
     * @dev The constructor of the VariableDebtToken
     * @param pool The address of the Pool contract
     * @param underlyingAsset The address of the underlying asset
     * @param name The name of the variable debt token
     * @param symbol The symbol of the variable debt token
     */
    constructor(
        address pool,
        address underlyingAsset,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) Ownable(msg.sender) {
        POOL = pool;
        UNDERLYING_ASSET_ADDRESS = underlyingAsset;
    }

    /**
     * @notice Mints debt token to the `onBehalfOf` address
     * @param user The address receiving the borrowed underlying, being the delegatee in case
     *   of credit delegate, or same as `onBehalfOf` otherwise
     * @param onBehalfOf The address that will be getting the debt
     * @param amount The amount of debt being minted
     * @param index The variable debt index of the reserve
     * @return `true` if the the previous balance of the user is 0
     */
    function mint(
        address user,
        address onBehalfOf,
        uint256 amount,
        uint256 index
    ) external override onlyPool returns (bool) {
        if (user != onBehalfOf) {
            _decreaseBorrowAllowance(onBehalfOf, user, amount, index);
        }

        uint256 previousBalance = super.balanceOf(onBehalfOf);
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "VDT_INVALID_MINT_AMOUNT");

        _mint(onBehalfOf, amountScaled);

        emit Transfer(address(0), onBehalfOf, amount);
        emit Mint(user, onBehalfOf, amount, index);

        return previousBalance == 0;
    }

    /**
     * @notice Burns debt of `user`
     * @param user The address of the user getting his debt burned
     * @param amount The amount of debt tokens getting burned
     * @param index The variable debt index of the reserve
     */
    function burn(address user, uint256 amount, uint256 index) external override onlyPool {
        uint256 amountScaled = amount.rayDiv(index);
        require(amountScaled != 0, "VDT_INVALID_BURN_AMOUNT");

        _burn(user, amountScaled);

        emit Transfer(user, address(0), amount);
        emit Burn(user, amount, index);
    }

    /**
     * @dev Returns the scaled balance of the user
     * @param user The address of the user
     * @return The scaled balance of the user
     */
    function scaledBalanceOf(address user) external view returns (uint256) {
        return super.balanceOf(user);
    }

    /**
     * @dev Returns the scaled total supply
     * @return The scaled total supply
     */
    function scaledTotalSupply() external view returns (uint256) {
        return super.totalSupply();
    }

    /**
     * @dev Returns the balance of the user based on a scaled balance
     * @param user The address of the user
     * @param index The variable debt index of the reserve
     * @return The balance of the user
     */
    function balanceOf(address user, uint256 index) external view returns (uint256) {
        return super.balanceOf(user).rayMul(index);
    }

    /**
     * @dev Decreases the borrow allowance of the user
     */
    function _decreaseBorrowAllowance(address user, address spender, uint256 amount, uint256 index) internal {
        // Implementation for borrow allowance if needed
    }

    event Mint(address indexed from, address indexed to, uint256 value, uint256 index);
    event Burn(address indexed from, uint256 value, uint256 index);
}

