// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IVariableDebtToken
 * @notice Interface for the variable debt token
 */
interface IVariableDebtToken is IERC20 {
    /**
     * @notice Returns the address of the underlying asset of this debtToken
     * @return The address of the underlying asset
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);

    /**
     * @notice Returns the address of the Pool
     * @return The Pool address
     */
    function POOL() external view returns (address);

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
    ) external returns (bool);

    /**
     * @notice Burns debt of `user`
     * @param user The address of the user getting his debt burned
     * @param amount The amount of debt tokens getting burned
     * @param index The variable debt index of the reserve
     */
    function burn(address user, uint256 amount, uint256 index) external;

    /**
     * @dev Returns the scaled balance of the user
     * @param user The address of the user
     * @return The scaled balance of the user
     */
    function scaledBalanceOf(address user) external view returns (uint256);

    /**
     * @dev Returns the scaled total supply
     * @return The scaled total supply
     */
    function scaledTotalSupply() external view returns (uint256);

    /**
     * @dev Returns the balance of the user based on a scaled balance
     * @param user The address of the user
     * @param index The variable debt index of the reserve
     * @return The balance of the user
     */
    function balanceOf(
        address user,
        uint256 index
    ) external view returns (uint256);
}
