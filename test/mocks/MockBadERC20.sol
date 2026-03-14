// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title BadTokenTest - Bad token test contract.
/// @author Michealking (@BuildsWithKing).
/**
 *  @dev  ERC20 bad token test contract. Deploy first and credit users.
 */

import {KingERC20} from "@buildswithking-security/tokens/ERC20/KingERC20.sol";

contract MockBadERC20 is KingERC20 {
    // =============================== Constructor ==============================================
    /// @notice Deploys the mock token with a name, symbol and initial supply.
    /// @param name_ The token's name.
    /// @param symbol_ The token's symbol.
    /// @param initialSupply_ The token's initial supply minted to the deployer.
    constructor(string memory name_, string memory symbol_, uint256 initialSupply_)
        KingERC20(msg.sender, name_, symbol_, initialSupply_)
    {}

    // ======================================= External Write Functions =======================================
    /// @notice Transfers token from the caller to a user.
    /// @return False if the transfer fails.
    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }

    /// @notice Mints tokens to any address freely. For testing only.
    /// @dev No access control — any address can call this in tests.
    /// @param to The receiver's address.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) external returns (bool) {
        return false;
    }
}
