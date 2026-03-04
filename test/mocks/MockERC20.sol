// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title MockERC20.
/// @author Michealking (@BuildsWithKing).
/// @custom:securitycontact buildswithking@gmail.com
/**
 * @notice Mock ERC20 token for testing purposes only.
 * @dev Exposes unrestricted mint and burn functions to allow tests to freely
 *      set up any scenario without access control restrictions.
 *
 * @notice THIS CONTRACT IS FOR TESTING ONLY. NEVER DEPLOY TO PRODUCTION.
 */
import {KingERC20} from "@buildswithking-security/tokens/ERC20/KingERC20.sol";

contract MockERC20 is KingERC20 {
    // =============================== Constructor ==============================================
    /// @notice Deploys the mock token with a name, symbol and initial supply.
    /// @param name_ The token's name.
    /// @param symbol_ The token's symbol.
    /// @param initialSupply_ The token's initial supply minted to the deployer.
    constructor(string memory name_, string memory symbol_, uint256 initialSupply_)
        KingERC20(msg.sender, name_, symbol_, initialSupply_)
    {}

    // =============================== External Write Functions =================================
    /// @notice Mints tokens to any address freely. For testing only.
    /// @dev No access control — any address can call this in tests.
    /// @param to The receiver's address.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burns tokens from any address freely. For testing only.
    /// @dev No access control — any address can call this in tests.
    /// @param from The address to burn from.
    /// @param amount The amount of tokens to burn.
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
