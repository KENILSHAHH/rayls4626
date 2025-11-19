// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPoolAddressesProvider.sol";
import "../interfaces/IPool.sol";

/**
 * @title PoolAddressesProvider
 * @notice Main registry of addresses part of or connected to the protocol
 */
contract PoolAddressesProvider is IPoolAddressesProvider, Ownable {
    address private _pool;

    /**
     * @dev Constructor
     * @param owner The owner address of the contract
     */
    constructor(address owner) Ownable(owner) {}

    /**
     * @notice Returns the address of the Pool proxy.
     * @return The Pool proxy address
     */
    function getPool() external view override returns (address) {
        return _pool;
    }

    /**
     * @notice Updates the implementation of the Pool, or creates the proxy if it doesn't exist.
     * @param newPoolImpl The new Pool implementation
     */
    function setPoolImpl(address newPoolImpl) external override onlyOwner {
        _pool = newPoolImpl;
        emit PoolUpdated(newPoolImpl);
    }

    event PoolUpdated(address indexed newAddress);
}

