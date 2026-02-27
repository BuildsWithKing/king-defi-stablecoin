// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 *     @title KingUSD - A decentralized stablecoin.
 *     @author Michealking(@BuildsWithKing)
 *     @dev This contract accepts wETH and wBTC as collateral, uses an algorithm for its minting & burning and its pegged to USD.
 *     @notice This is an ERC20 token contract governed by KUSDEngine.
 */
import {KingERC20Burnable, KingERC20} from "@buildswithking-security/tokens/ERC20/extensions/KingERC20Burnable.sol";
import {Kingable} from "@buildswithking-security/access/core/Kingable.sol";

contract KingUSD is KingERC20Burnable, Kingable {
    // =================================== Custom Errors ===============================
    /// @notice Thrown when the engineAddress who is the contract's king tries burning zero token.
    error KingUSD__AmountMustBeGreaterThanZero();

    /// @notice Thrown when the engineAddress tries burning an amount greater than it's balance. 
    error KingUSD__BalanceTooLow();

    /// @notice Thrown when the engineAddress tries minting tokens to the zero address. 
    error KingUSD__ZeroAddress();

    // =================================== Constructor ==================================
    /// @dev Sets the engineAddress, token's name, symbol, initial supply at deployment. Mints the initial supply to the king upon deployment.
    /// @param engineAddress The KUSD engine's address.
    constructor(address engineAddress) Kingable(engineAddress) KingERC20(engineAddress, "KingUSD", "KUSD", 0) {}

    /// @notice Burns token. i.e Removes certain amount of the token from existence. Callable only by the engineAddress.
    /// @param amount The amount of tokens to be burned.
    function burn(uint256 amount) public override onlyKing {
        // Read the caller's balance. 
        uint256 balance = balanceOf(msg.sender);

        // Revert if amount is less than or equal to zero.
        if (amount <= 0) {
            revert KingUSD__AmountMustBeGreaterThanZero();
        }
        // Revert if caller's balance is less than the amount. 
        if(balance < amount) {
            revert KingUSD__BalanceTooLow();
        }
        // Call kingERC20Burnable burn function. 
        super.burn(amount);
    }

    /// @notice Mints tokens to an address. Callable only by the engineAddress.
    /// @param to The receiver's address.
    /// @param amount The amount of tokens to be minted.
    function mint(address to, uint256 amount) external onlyKing returns (bool) {
        // Revert if the receiver is the zero address. 
        if(to == address(0)) {
            revert KingUSD__ZeroAddress();
        }
        // Revert if the amount is less than or equal to zero. 
        if(amount <= 0) {
            revert KingUSD__AmountMustBeGreaterThanZero();
        }
        _mint(to, amount);

        return true;
    } 
}
