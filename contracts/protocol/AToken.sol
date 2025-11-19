// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IAToken.sol";
import "../interfaces/IPool.sol";

/**
 * @title AToken
 * @notice Implementation of the interest bearing token for the Aave protocol
 */
contract AToken is ERC20, IAToken, Ownable {
    using SafeERC20 for IERC20;

    address public immutable override UNDERLYING_ASSET_ADDRESS;
    address public immutable override POOL;

    /**
     * @dev Only pool can call functions marked by this modifier.
     */
    modifier onlyPool() {
        require(msg.sender == POOL, "AT_CALLER_MUST_BE_POOL");
        _;
    }

    /**
     * @dev The constructor of the AToken
     * @param pool The address of the Pool contract
     * @param underlyingAsset The address of the underlying asset
     * @param name The name of the aToken
     * @param symbol The symbol of the aToken
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
     * @notice Mints `amount` aTokens to `user`
     * @param user The address receiving the minted tokens
     * @param amount The amount of tokens getting minted
     */
    function mint(address user, uint256 amount) external override onlyPool {
        _mint(user, amount);
    }

    /**
     * @notice Burns aTokens from `user` and sends the equivalent amount of underlying to `receiverOfUnderlying`
     * @param user The owner of the aTokens, getting them burned
     * @param receiverOfUnderlying The address that will receive the underlying
     * @param amount The amount being burned
     */
    function burn(address user, address receiverOfUnderlying, uint256 amount) external override onlyPool {
        _burn(user, amount);
        IERC20(UNDERLYING_ASSET_ADDRESS).safeTransfer(receiverOfUnderlying, amount);
    }
}

