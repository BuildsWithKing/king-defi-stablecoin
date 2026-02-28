// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {KingUSD} from "src/token/KingUSD.sol";
import {KingClaimMistakenETH} from "@buildswithking-security/access/guards/KingClaimMistakenETH.sol";
/**
 * @title KUSDEngine - The engine contract controlling KUSD minting and burning.
 * @author Michealking (@BuildsWithKing)
 * @dev This contract accepts wETH and wBTC as collateral, uses an algorithm for its minting & burning and its pegged to USD.
 *
 * @notice This is an KingUSD governing contract.
 * This stablecoin has the properties:
 * - Dollar Pegged
 * - Algorithmically Stable
 * - Exogenous Collateral
 *
 * This is similar to DAI if DAI had no governance, no fees, and was only backed by wETH and wBTC.
 * KUSD system always remains "overcollaterized". At no point, should the value of all collateral be less than or equal the dollar backed value of KUSD.
 *
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */

contract KUSDEngine is KingClaimMistakenETH {
    // =============================== Custom Errors ============================================
    /// @notice Thrown when token addresses length is not equal to the pricefeed addresses length.
    error KUSDEngine__ArrayLengthMismatch();

    /// @notice Thrown when the zero address or kusd token address is used as the collateral address.
    error KUSDEngine__InvalidAddress();

    /// @notice Thrown when a caller inputs the zero address as the token collateral address.
    error KUSDEngine__ZeroAddress();

    /// @notice Thrown when a caller inputs zero or less as the amount collateral.
    error KUSDEngine__AmountMustBeGreaterThanZero();

    // =============================== State Variables ==========================================
    /// @notice Maps token address to price feed addresses.
    mapping(address token => address priceFeed) private s_priceFeeds;

    /// @notice Records KingUSD token address.
    KingUSD public immutable i_kUSD;

    // =============================== Events ===================================================
    // =============================== Modifiers ================================================
    /// @notice Validates amount and reverts if amount is equal to zero.
    /// @dev Ensures amount is greater than zero.
    /// @param amount The amount to be validated.
    modifier validateAmount(uint256 amount) {
        // Revert if amount is equal to zero.
        if (amount == 0) {
            revert KUSDEngine__AmountMustBeGreaterThanZero();
        }
        _;
    }

    // =============================== Constructor ==============================================
    constructor(
        address[] memory collateralAddresses,
        address[] memory priceFeedAddresses,
        address payable kusdAddress
    ) {
        // Read the collateral addresses and pricefeeds addresses length.
        uint256 collateralAddressesLength = collateralAddresses.length;
        uint256 priceFeedAddressesLength = priceFeedAddresses.length;

        // Revert if the collateral addresses length is not equal to the length of the pricefeeds address.
        if (collateralAddressesLength != priceFeedAddressesLength) {
            revert KUSDEngine__ArrayLengthMismatch();
        }

        // Loop through collateral addresses and assign pricefeeds address to each collateral address.
        for (uint256 i = 0; i < collateralAddressesLength;) {
            if (collateralAddresses[i] == address(0) || collateralAddresses[i] == kusdAddress) {
                revert KUSDEngine__InvalidAddress();
            }
            s_priceFeeds[collateralAddresses[i]] = priceFeedAddresses[i];
            unchecked {
                ++i;
            }
        }
        i_kUSD = KingUSD(kusdAddress);
    }
    // =============================== External Write Functions =================================

    function depositCollateralAndMintKUSD() external {}

    /**
     * @notice Deposits Collateral to the contract.
     * @param tokenCollateralAddress The address of the token to deposit as collateral.
     * @param amountCollateral The amount of collateral to deposit.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        validateAmount(amountCollateral)
    {}

    function redeemCollateralForKUSD() external {}

    function redeemCollateral() external {}

    function mintKUSD() external {}

    function burnKUSD() external {}

    function liquidate() external {}

    // =============================== External Read Functions ==================================
    function getHealthFactor() external view {}
    // =============================== Public Read Functions ====================================
}
