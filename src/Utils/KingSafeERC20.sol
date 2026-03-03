// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title KingSafeERC20
/// @author Michealking (@BuildsWithKing)
/// @custom:securitycontact buildswithking@gmail.com

/**
 * @notice Library for safe ERC20 token transfers.
 *
 * @dev    Wraps ERC20 transfer and transferFrom calls with low-level call checks
 *         to handle tokens that do not return a boolean value on transfer.
 *         Use this library to prevent silent token transfer failures.
 */
import {IERC20} from "@buildswithking-security/tokens/ERC20/interfaces/IERC20.sol";

library KingSafeERC20 {
    // ============================== Custom Errors =================================
    /// @notice Thrown when a token transfer fails.
    /// @param token The token's contract address.
    /// @param amount The amount of token to be transferred.
    error KingSafeERC20__TokenTransferFailed(IERC20 token, uint256 amount);

    // ============================== Internal Functions =================================
    /// @notice Ensures safe token transfer to prevent token loss.
    /// @param token The token's contract address.
    /// @param to The receiver's address.
    /// @param amount The amount of token to be transferred.
    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        // Revert if token `transfer` fails.
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transfer.selector, to, amount));
        if (!success || data.length != 0 && !abi.decode(data, (bool))) {
            revert KingSafeERC20__TokenTransferFailed(token, amount);
        }
    }

    /// @notice Ensures safe token transfer from owner to receiver.
    /// @param token The token's contract address.
    /// @param from The owner's address.
    /// @param to The receiver's address.
    /// @param amount The amount of token to be transferred.
    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        // Revert if token `transferFrom` fails.
        (bool success, bytes memory data) =
            address(token).call(abi.encodeWithSelector(token.transferFrom.selector, from, to, amount));
        if (!success || data.length != 0 && !abi.decode(data, (bool))) {
            revert KingSafeERC20__TokenTransferFailed(token, amount);
        }
    }
}
