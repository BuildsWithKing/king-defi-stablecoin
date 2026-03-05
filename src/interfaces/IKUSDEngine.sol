// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IKUSDEngine - Interface for the KUSDEngine contract.
 * @author Michealking (@BuildsWithKing)
 * @dev Interface exposing all external and public functions of KUSDEngine.
 * @custom:securitycontact buildswithking@gmail.com
 */
interface IKUSDEngine {
    // =============================== Custom Errors ============================================
    /// @notice Thrown when token addresses length is not equal to the pricefeed addresses length.
    error KUSDEngine__ArrayLengthMismatch();

    /// @notice Thrown when the zero address or kusd token address is used as the collateral address.
    error KUSDEngine__InvalidAddress();

    /// @notice Thrown when a caller inputs zero or less as the amount collateral.
    error KUSDEngine__AmountMustBeGreaterThanZero();

    /**
     * @notice Thrown when a caller tries depositing to a non-existing collateral address.
     * @param collateral The collateral's address.
     */
    error KUSDEngine__InvalidCollateral(address collateral);

    /// @notice Thrown when a caller's mint fails.
    error KUSDEngine__MintFailed();

    /// @notice Thrown when a caller inputs an amount greater than their collateral balance.
    error KUSDEngine__AmountGreaterThanBalance(uint256 collateralBalance);

    /**
     * @notice Thrown when an oracle returns a non-positive price.
     * @param collateral The collateral's address.
     */
    error KUSDEngine__InvalidOraclePrice(address collateral);

    /**
     * @notice Thrown when token/feed decimals are too large to safely scale by powers of ten.
     * @param collateral The collateral's address.
     */
    error KUSDEngine__UnsupportedDecimals(address collateral);

    /**
     * @notice Thrown when a user health factor is less than 1e18.
     *     @param userHealthFactor The user's health factor.
     */
    error KUSDEngine__HealthFactorIsBelowMinimum(uint256 userHealthFactor);

    /**
     * @notice Thrown when a user health factor is greater than 1e18.
     * @param userHealthFactor The user's health factor.
     */
    error KUSDEngine__HealthFactorAboveMinimum(uint256 userHealthFactor);

    /**
     * @notice Thrown when a user health factor does not improve during liquidation.
     * @param userCurrentHealthFactor The user's current health factor.
     */
    error KUSDEngine__UserHealthFactorNotImproved(uint256 userCurrentHealthFactor);

    // =============================== Events ===================================================
    /**
     * @notice Emitted once a user deposits collateral.
     * @param user The user's address.
     * @param collateral The address of the collateral deposited.
     * @param amount The amount of collateral deposited.
     */
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 amount);

    /**
     * @notice Emitted once a user redeems collateral.
     * @param redemmedFrom The user's address.
     * @param redemmedTo The redemer's address.
     * @param collateral The address of the collateral redeemed.
     * @param amount The amount of collateral redeemed.
     */
    event CollateralRedeemed(
        address indexed redemmedFrom, address redemmedTo, address indexed collateral, uint256 amount
    );

    // =============================== External Write Functions =================================
    /**
     * @notice Deposits collateral to the contract and mints KUSD to the caller.
     * @param collateralAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to deposit.
     * @param amountOfKUSDToMint The amount of KUSD to mint to the caller.
     */
    function depositCollateralAndMintKUSD(
        address collateralAddress,
        uint256 collateralAmount,
        uint256 amountOfKUSDToMint
    ) external;

    /**
     * @notice Burns KUSD and redeems caller's collateral.
     * @param collateralAddress The address of the collateral to redeem.
     * @param collateralAmount The amount of collateral to redeem.
     * @param amountOfKUSD The amount of KUSD to burn.
     */
    function redeemCollateralForKUSD(address collateralAddress, uint256 collateralAmount, uint256 amountOfKUSD)
        external;

    /**
     * @notice Liquidates an undercollateralised user's position.
     *   Ensures the user's health factor is below the MIN_HEALTH_FACTOR(1e18).
     *   Caller Pays debt owed by the user to improve the user's health factor and earn bonuses. 
     * @notice This function assumes users keep collateral value at about 2x their minted KUSD debt (200% collateralization).
     *   This function only works if the system is always overcollateralized. 
     * @notice Known limitation: if the protocol falls to 100% collateralization or below,
     *   liquidations may no longer be sufficiently incentivized.
     * @dev Example: a sudden collateral price drop can make positions undercollateralized before liquidators can act.
     * @param collateralAddress The address of the collateral to liquidate.
     * @param user The address of the user with health factor < 1e18.
     * @param debtToCover The amount of KUSD caller wants to burn to improve the user's health factor.
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover) external;

    /**
     * @notice Deposits Collateral to the contract.
     * @dev Uses `nonReentrant` from KingClaimMistakenETH contract.
     * @param collateralAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to deposit.
     */
    function depositCollateral(address collateralAddress, uint256 collateralAmount) external;

    /**
     * @notice Mints KUSD to the caller. Ensures caller has enough collateral deposited.
     * check caller's health factor and ensure its greater than or equal to 1.
     * @param amount The amount of KUSD to mint.
     */
    function mintKUSD(uint256 amount) external;

    /**
     * @notice Redeems caller's collateral.
     * @param collateralAddress The address of the collateral to redeem.
     * @param collateralAmount The amount of collateral to redeem.
     */
    function redeemCollateral(address collateralAddress, uint256 collateralAmount) external;

    /**
     * @notice Burns KUSD. i.e Removes certain amount of the KUSD from existence.
     * @param amount The amount of KUSD to be burned.
     */
    function burnKUSD(uint256 amount) external;

    // =============================== External Read Functions ==================================
    /**
     * @notice Returns the user's health factor.
     * @param user The user's address.
     */
    function getHealthFactor(address user) external view returns (uint256 healthFactor);

    // =============================== Public Read Functions ====================================
    /**
     * @notice Returns the user's collateral value.
     * @param user The user's address.
     * @return totalCollateralValueInUSD The user's total collateral value in USD.
     */
    function getAccountCollateralValue(address user) external view returns (uint256 totalCollateralValueInUSD);

    /**
     * @notice Returns USD value scaled to 1e18 precision.
     * @dev Uses chainlink aggregatorV3Interface to fetch the current price of the collateral token.
     * Scales oracle price to 1e18 using `priceFeed.decimals()` and then normalizes by collateral token decimals.
     * @param collateralAddress The token collateral address.
     * @param amount The amount of token.
     * @return The USD value of the amount of token.
     */
    function getCollateralUSDValue(address collateralAddress, uint256 amount) external view returns (uint256);
}
