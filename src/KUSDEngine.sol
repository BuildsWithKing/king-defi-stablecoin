// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IKUSDEngine} from "src/interfaces/IKUSDEngine.sol";
import {KingUSD} from "src/token/KingUSD.sol";
import {IERC20} from "@buildswithking-security/tokens/ERC20/interfaces/IERC20.sol";
import {IERC20Metadata} from "@buildswithking-security/tokens/ERC20/interfaces/IERC20Metadata.sol";
import {KingSafeERC20} from "src/Utils/KingSafeERC20.sol";
import {OracleLib, AggregatorV3Interface} from "src/libraries/OracleLib.sol";
import {KingClaimMistakenETH} from "@buildswithking-security/access/guards/KingClaimMistakenETH.sol";

/**
 * @title KUSDEngine - The engine contract controlling KUSD minting and burning.
 * @author Michealking (@BuildsWithKing)
 * @dev This contract accepts WETH and WBTC as collateral, uses an algorithm for its minting & burning and it is pegged to USD.
 *
 * @notice This is the KingUSD governing contract.
 * This stablecoin has the properties:
 * - Dollar Pegged
 * - Algorithmically Stable
 * - Exogenous Collateral
 *
 * This is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 * KUSD system always remains "overcollateralized". At no point, should the value of all collateral be less than or equal the dollar backed value of KUSD.
 *
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract KUSDEngine is IKUSDEngine, KingClaimMistakenETH {
    // ============================== Types =====================================================
    using KingSafeERC20 for IERC20;
    using OracleLib for AggregatorV3Interface;

    // =============================== State Variables ==========================================
    /**
     * @dev Fixed-point scale used for internal USD/accounting math (18 decimals).
     * Example: 1 USD is represented as 1e18.
     */
    uint256 private constant PRECISION = 1e18;

    /// @dev Decimal base used for powers-of-ten scaling (10 ** decimals).
    uint256 private constant DECIMAL_BASE = 10;

    /// @dev Number of decimals used for normalized USD pricing math.
    uint8 private constant USD_PRECISION_DECIMALS = 18;

    /// @dev Largest exponent where 10 ** exponent still fits in uint256.
    uint8 private constant MAX_SAFE_DECIMALS = 77;

    /**
     * @notice Liquidation threshold percentage.
     * @dev 50 means 50%. A position must keep health factor >= 1.
     * This means users must be 200% overcollateralized.
     * Health factor uses: (collateralUsd * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION) / debtKUSD
     */
    uint256 private constant LIQUIDATION_THRESHOLD = 50;

    /**
     * @notice Precision denominator for liquidation threshold math.
     * Used in calculating users health factor ensuring users are always overcollateralized,
     * and should be liquidated if user health factor is < 1.
     */
    uint256 private constant LIQUIDATION_PRECISION = 100;

    /// @notice The minimum health factor a user must have.
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    /// @notice The bonus amount earned by liquidators when a debt owed by the user is cleared.
    uint256 private constant LIQUIDATION_BONUS = 15;

    /// @notice Maps collateral address to price feed addresses.
    mapping(address collateral => address priceFeed) private s_priceFeeds;

    /// @notice Maps users address to the collateral's address and the amount of collateral deposited.
    mapping(address user => mapping(address collateral => uint256 amount)) private s_collateralDeposited;

    /// @notice Maps users address to amount of kUSD minted.
    mapping(address user => uint256 kUSD) private s_kusdMinted;

    /// @notice Records collateral tokens addresses.
    address[] private s_collateralTokens;

    /// @notice Records KingUSD token address.
    KingUSD private immutable I_K_USD;

    // =============================== Modifiers ================================================
    /**
     * @notice Validates amount and revert if amount is equal to zero.
     * @dev Ensures amount is greater than zero.
     * @param amount The amount to be validated.
     */
    modifier validateAmount(uint256 amount) {
        _validateAmount(amount);
        _;
    }

    /**
     * @notice Validates address and revert if the address's pricefeed is the zero address.
     * @dev Ensures each address has an existing pricefeed and reverts if pricefeed is the zero address.
     * @param collateralAddress The address to be validated.
     */
    modifier onlyAllowedCollateral(address collateralAddress) {
        _onlyAllowedCollateral(collateralAddress);
        _;
    }

    /**
     * @notice Internal function to validate amount
     * @dev Reverts if amount is equal to zero
     * @param amount The amount to validate
     */
    function _validateAmount(uint256 amount) internal pure {
        // Revert if amount is equal to zero.
        if (amount == 0) {
            revert KUSDEngine__AmountMustBeGreaterThanZero();
        }
    }

    /**
     * @notice Internal function to validate collateral address
     * @dev Reverts if the collateral address doesn't have a price feed
     * @param collateralAddress The collateral address to validate
     */
    function _onlyAllowedCollateral(address collateralAddress) internal view {
        if (s_priceFeeds[collateralAddress] == address(0)) {
            revert KUSDEngine__InvalidCollateral(collateralAddress);
        }
    }

    // =============================== Constructor ==============================================
    /**
     * @notice Assigns collateral addresses, priceFeed addresses and kUSD address at deployment.
     * @param collateralAddresses Collateral addresses to be added.
     * @param priceFeedAddresses PriceFeed address for each collateral, fetched from chainlink docs "https://data.chain.link/feeds".
     * @param kusdAddress KUSD contract address.
     */
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

        // Revert if kUSD address is not a contract address.
        if (kusdAddress.code.length == 0) {
            revert KUSDEngine__InvalidAddress();
        }

        // Loop through collateral addresses and assign pricefeeds address to each collateral address.
        for (uint256 i = 0; i < collateralAddressesLength;) {
            address collateral = collateralAddresses[i];
            address priceFeed = priceFeedAddresses[i];

            s_priceFeeds[collateral] = priceFeed;
            s_collateralTokens.push(collateral);

            unchecked {
                ++i;
            }
        }

        I_K_USD = KingUSD(kusdAddress);
    }

    // =============================== External Write Functions =================================
    /**
     * @notice Deposits collateral to the contract and mints KUSD to the caller.
     * @param collateralAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to deposit.
     * @param amountOfKusdToMint The amount of KUSD to mint to the caller.
     */
    function depositCollateralAndMintKusd(
        address collateralAddress,
        uint256 collateralAmount,
        uint256 amountOfKusdToMint
    ) external {
        // Call the depositCollateral and mintKUSD public function.
        depositCollateral(collateralAddress, collateralAmount);
        mintKusd(amountOfKusdToMint);
    }

    /**
     * @notice Burns KUSD and redeems caller's collateral.
     * @param collateralAddress The address of the collateral to redeem.
     * @param collateralAmount The amount of collateral to redeem.
     * @param amountOfKusd The amount of KUSD to burn.
     */
    function redeemCollateralForKusd(address collateralAddress, uint256 collateralAmount, uint256 amountOfKusd)
        external
    {
        burnKusd(amountOfKusd);
        redeemCollateral(collateralAddress, collateralAmount);
    }

    /**
     * @notice Liquidates an undercollateralised user's position.
     *   Ensures the user's health factor is below the MIN_HEALTH_FACTOR(1e18).
     *   Caller Pays debt owed by the user to improve the user's health factor and earn bonuses.
     * @notice This function assumes users keep collateral value at about 2x their minted KUSD debt (200% collateralization).
     *   This function only works if the system is always overcollateralized.
     * @notice Known limitation: if the protocol falls to 100% collateralization or below,
     *   liquidations may no longer be sufficiently incentivized.
     * @dev Example: a sudden collateral price drop can make positions undercollateralized before liquidators can act.
     * Note: Users CAN liquidate themselves if underwater, but this is gas-inefficient.
     *         Use redeemCollateralForKUSD() instead for normal exists.
     * @param collateralAddress The address of the collateral to liquidate.
     * @param user The address of the user with health factor < 1e18.
     * @param debtToCover The amount of KUSD caller wants to burn to improve the user's health factor.
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover)
        external
        nonReentrant
        validateAmount(debtToCover)
    {
        // Read the user's current health factor.
        uint256 userInitialHealthFactor = _healthFactor(user);
        if (userInitialHealthFactor >= MIN_HEALTH_FACTOR) {
            revert KUSDEngine__HealthFactorAboveMinimum(user, userInitialHealthFactor);
        }
        // Read the user's collateral amount from USD.
        uint256 userCollateralAmount = getCollateralAmountFromUsd(collateralAddress, debtToCover);
        // Calculate the caller's bonus for liquidating a user and add it to the total collateral to be redeemed.
        uint256 bonusCollateral = (userCollateralAmount * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = userCollateralAmount + bonusCollateral;

        // Redeem collateral to the caller and burn kusd.
        _redeemCollateral(user, collateralAddress, totalCollateralToRedeem);
        _burnKusd(user, msg.sender, debtToCover);

        // Read user's current health factor and  revert if less than or equal to user's Previous HF.
        uint256 userCurrentHealthFactor = _healthFactor(user);
        if (userCurrentHealthFactor <= userInitialHealthFactor) {
            revert KUSDEngine__UserHealthFactorNotImproved();
        }
        _revertIfUserHealthFactorIsBelowMinimum(msg.sender);
    }

    // =============================== Public Write Functions =================================
    /**
     * @notice Deposits Collateral to the contract.
     * @dev Uses `nonReentrant` from KingClaimMistakenETH contract.
     * @param collateralAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to deposit.
     */
    function depositCollateral(address collateralAddress, uint256 collateralAmount)
        public
        nonReentrant
        validateAmount(collateralAmount)
        onlyAllowedCollateral(collateralAddress)
    {
        // Add collateral amount to caller's collateral deposited.
        s_collateralDeposited[msg.sender][collateralAddress] += collateralAmount;

        // Emit the event CollateralDeposited.
        emit CollateralDeposited(msg.sender, collateralAddress, collateralAmount);

        // Safely transfer the collateral from the caller to this contract.
        IERC20(collateralAddress).safeTransferFrom(msg.sender, address(this), collateralAmount);
    }

    /**
     * @notice Mints KUSD to the caller. Ensures caller has enough collateral deposited.
     * check caller's health factor and ensure its greater than or equal to 1.
     * @param amount The amount of KUSD to mint.
     */
    function mintKusd(uint256 amount) public nonReentrant validateAmount(amount) {
        // Add amount to the number of tokens minted by the caller.
        s_kusdMinted[msg.sender] += amount;

        // Call the internal function and check the caller's health factor.
        _revertIfUserHealthFactorIsBelowMinimum(msg.sender);

        // Mint KUSD to the caller.
        bool success = I_K_USD.mint(msg.sender, amount);
        if (!success) {
            revert KUSDEngine__MintFailed();
        }
    }

    /**
     * @notice Redeems caller's collateral.
     * @param collateralAddress The address of the collateral to redeem.
     * @param collateralAmount The amount of collateral to redeem.
     */
    function redeemCollateral(address collateralAddress, uint256 collateralAmount)
        public
        nonReentrant
        onlyAllowedCollateral(collateralAddress)
        validateAmount(collateralAmount)
    {
        _redeemCollateral(msg.sender, collateralAddress, collateralAmount);

        // Revert if caller's health factor is less than the minimum health factor.
        _revertIfUserHealthFactorIsBelowMinimum(msg.sender);
    }

    /**
     * @notice Burns KUSD. i.e Removes certain amount of the KUSD from existence.
     * @param amount The amount of KUSD to be burned.
     */
    function burnKusd(uint256 amount) public nonReentrant validateAmount(amount) {
        _burnKusd(msg.sender, msg.sender, amount);
    }

    // =============================== Private Write Functions =================================
    /**
     * @notice Redeems a user's collateral.
     * @param user The user's address.
     * @param collateralAddress The address of the collateral to redeem.
     * @param collateralAmount The amount of collateral to redeem.
     */
    function _redeemCollateral(address user, address collateralAddress, uint256 collateralAmount)
        private
        onlyAllowedCollateral(collateralAddress)
        validateAmount(collateralAmount)
    {
        uint256 collateralBalance = s_collateralDeposited[user][collateralAddress];
        // Revert if amount is greater than the user's balance.
        if (collateralAmount > collateralBalance) {
            revert KUSDEngine__AmountGreaterThanBalance(collateralBalance);
        }
        s_collateralDeposited[user][collateralAddress] = collateralBalance - collateralAmount;
        emit CollateralRedeemed(user, msg.sender, collateralAddress, collateralAmount);

        // Safely transfer the collateral amount from this contract to caller.
        IERC20(collateralAddress).safeTransfer(msg.sender, collateralAmount);
    }

    /**
     * @notice Burns KUSD. i.e Removes certain amount of the KUSD from existence.
     * @param onBehalfOf The debtor's address.
     * @param from The caller's address.
     * @param amount The amount of KUSD to be burned.
     */
    function _burnKusd(address onBehalfOf, address from, uint256 amount) private validateAmount(amount) {
        // Read debtor's KUSD balance.
        uint256 kUsdBalance = s_kusdMinted[onBehalfOf];

        // Revert if amount is greater than the debtor's balance.
        if (amount > kUsdBalance) {
            revert KUSDEngine__AmountGreaterThanBalance(kUsdBalance);
        }

        // Deduct amount from debtor's KUSD balance.
        s_kusdMinted[onBehalfOf] = kUsdBalance - amount;

        // Safely transfer KUSD from the caller to this contract.
        IERC20(I_K_USD).safeTransferFrom(from, address(this), amount);

        I_K_USD.burn(amount);
    }

    // =============================== External Read Functions ==================================
    /**
     * @notice Returns the user's health factor.
     * @param user The user's address.
     * @return healthFactor The user's health factor.
     */
    function getHealthFactor(address user) external view returns (uint256 healthFactor) {
        return _healthFactor(user);
    }

    /**
     * @notice Returns health factor.
     * @dev Health factor < 1e18 means liquidatable.
     * Formula: HF = (collateralValueInUsd * 50 / 100) * 1e18 / totalKusdMinted
     * @param totalKusdMinted The total kusd minted by an account.
     * @param collateralValueInUsd The account's collateral value in usd.
     * @return The health factor, scaled by 1e18.
     */
    function calculateHealthFactor(uint256 totalKusdMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalKusdMinted, collateralValueInUsd);
    }

    /**
     * @notice Returns the amount of token minted by the user.
     * @param user The user's address.
     * @return balance The amount of KUSD minted by the user.
     */
    function getKusdBalanceOf(address user) public view returns (uint256 balance) {
        balance = s_kusdMinted[user];
    }

    /**
     * @notice Returns the minimum health factor.
     * @return The minimum health factor.
     */
    function getMinimumHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    /**
     * @notice Returns collateral token addresses.
     * @return addresses of collateral tokens.
     */
    function getCollateralAddresses() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    /**
     * @notice Returns liquidation threshold.
     * @return The liquidation threshold.
     */
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    /**
     * @notice Returns user's collateral balance.
     * @param user The user's address.
     * @param collateral The collateral's address.
     * @return balance The user's collateral balance.
     */
    function getCollateralBalanceOf(address user, address collateral) external view returns (uint256 balance) {
        return s_collateralDeposited[user][collateral];
    }

    /**
     * @notice Returns the collateral's priceFeed address.
     * @param collateral The collateral address.
     * @return priceFeed The pricefeed's address.
     */
    function getCollateralPriceFeedAddress(address collateral) external view returns (address priceFeed) {
        return s_priceFeeds[collateral];
    }

    /**
     * @notice Returns liquidation bonus. claimable by liquidators.
     * @return The liquidation bonus.
     */
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    /**
     * @notice Returns Kusd contract address.
     * @return Kusd contract address.
     */
    function getKusd() external view returns (address) {
        return address(I_K_USD);
    }

    // =============================== Public Read Functions ====================================
    /**
     * @notice Returns the collateral token amount equivalent to a USD amount.
     * @param collateralAddress The collateral token address.
     * @param usdAmountInWei The USD amount scaled to 1e18 (e.g. 1 USD = 1e18).
     * @return collateralAmount The collateral amount in the token's base units.
     */
    function getCollateralAmountFromUsd(address collateralAddress, uint256 usdAmountInWei)
        public
        view
        onlyAllowedCollateral(collateralAddress)
        returns (uint256 collateralAmount)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralAddress]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        // Call the internal _revertIfPriceIsLessThanOrEqualZero function.
        _revertIfPriceIsLessThanOrEqualZero(collateralAddress, price);

        // Read the price feed's decimals.
        uint8 feedDecimals = priceFeed.decimals();

        // Call the internal _checkPriceFeedsAndCollateralDecimals function.
        (uint256 normalizedPrice, uint8 collateralDecimals) =
            _checkPriceFeedsAndCollateralDecimals(price, feedDecimals, collateralAddress);

        // Token scale factor: one whole token in base units (e.g. for 18 decimals, 1 token = 1e18 = 10**18).
        uint256 collateralUnit = DECIMAL_BASE ** collateralDecimals;

        return (usdAmountInWei * collateralUnit) / normalizedPrice;
    }

    /**
     * @notice Returns the user's collateral value.
     * @param user The user's address.
     * @return totalCollateralValueInUsd The user's total collateral value in USD.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 collateralTokensLength = s_collateralTokens.length;
        for (uint256 i = 0; i < collateralTokensLength;) {
            address collateralAddress = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][collateralAddress];
            totalCollateralValueInUsd += getCollateralUsdValue(collateralAddress, amount);
            unchecked {
                ++i;
            }
        }
        return totalCollateralValueInUsd;
    }

    /**
     * @notice Returns USD value scaled to 1e18 precision.
     * @dev Uses chainlink aggregatorV3Interface to fetch the current price of the collateral token.
     * Scales oracle price to 1e18 using `priceFeed.decimals()` and then normalizes by collateral token decimals.
     * @param collateralAddress The token collateral address.
     * @param amount The amount of token
     * @return The USD value of the amount of token
     */
    function getCollateralUsdValue(address collateralAddress, uint256 amount)
        public
        view
        onlyAllowedCollateral(collateralAddress)
        returns (uint256)
    {
        // Read the collateral's token price using its address from chainlink.
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralAddress]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        // Call the internal _revertIfPriceIsLessThanOrEqualZero function.
        _revertIfPriceIsLessThanOrEqualZero(collateralAddress, price);

        // Read the price feed's decimals.
        uint8 feedDecimals = priceFeed.decimals();

        // Call the internal _checkPriceFeedsAndCollateralDecimals function.
        (uint256 normalizedPrice, uint8 collateralDecimals) =
            _checkPriceFeedsAndCollateralDecimals(price, feedDecimals, collateralAddress);

        // Token scale factor: one whole token in base units (e.g. for 18 decimals, 1 token = 1e18 = 10**18).
        uint256 collateralUnit = DECIMAL_BASE ** collateralDecimals;

        return (normalizedPrice * amount) / collateralUnit;
    }

    /**
     * @notice Returns the user's account information.
     * @param user The user's address.
     * @return totalKusdMinted The total KUSD minted by the user.
     * collateralValueInUsd The user's collateral's value in dollar.
     *
     */
    function getAccountInformation(address user)
        public
        view
        returns (uint256 totalKusdMinted, uint256 collateralValueInUsd)
    {
        (totalKusdMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    // =============================== Private Read Functions ===================================
    /**
     * @notice Returns the user's account information.
     * @param user The user's address.
     * @return totalKusdMinted The total KUSD minted by the user.
     * collateralValueInUsd The user's collateral's value in dollar.
     *
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalKusdMinted, uint256 collateralValueInUsd)
    {
        totalKusdMinted = s_kusdMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);

        return (totalKusdMinted, collateralValueInUsd);
    }

    /**
     * @notice Returns the user's health factor.
     * @return healthFactor The user's health factor, scaled by 1e18.
     */
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        (uint256 totalKusdMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);

        return _calculateHealthFactor(totalKusdMinted, collateralValueInUsd);
    }

    // ======================================== Internal View Functions =========================
    /**
     * @notice Checks user's health factor and revert if user don't have enough collateral.
     * @param user The user's address.
     */
    function _revertIfUserHealthFactorIsBelowMinimum(address user) internal view {
        // Read user's health factor.
        uint256 userHealthFactor = _healthFactor(user);

        // Revert if the user's health factor is less than 1e18.
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert KUSDEngine__HealthFactorIsBelowMinimum(user, userHealthFactor);
        }
    }

    /**
     * @notice Checks collateral's price and revert if price is less than or equal to zero.
     * @param collateralAddress The token collateral address.
     * @param price The collateral's current price.
     */
    function _revertIfPriceIsLessThanOrEqualZero(address collateralAddress, int256 price) internal pure {
        // Revert if price is less than or equal to zero.
        if (price <= 0) {
            revert KUSDEngine__InvalidOraclePrice(collateralAddress);
        }
    }

    /**
     * @notice Checks the priceFeeds and collateral address's decimals.
     * @param price The price of the feeds.
     * @param feedDecimals The decimals of the feed.
     * @param collateralAddress The token collateral address.
     */
    function _checkPriceFeedsAndCollateralDecimals(int256 price, uint8 feedDecimals, address collateralAddress)
        internal
        view
        returns (uint256 normalizedPrice, uint8 collateralDecimals)
    {
        // Read the collateral's decimals.
        collateralDecimals = IERC20Metadata(collateralAddress).decimals();

        // Revert if the feedDecimals or the collateralDecimals is greater than 77 (max uint256 is about 1.1579e77)
        if (feedDecimals > MAX_SAFE_DECIMALS || collateralDecimals > MAX_SAFE_DECIMALS) {
            revert KUSDEngine__UnsupportedDecimals(collateralAddress);
        }
        // Convert price from int256 to uint256.
        normalizedPrice = uint256(price);
        if (feedDecimals < USD_PRECISION_DECIMALS) {
            // Scale feed price up to 18 decimals so all USD math uses one precision (1e18).
            normalizedPrice *= DECIMAL_BASE ** (USD_PRECISION_DECIMALS - feedDecimals);
        } else if (feedDecimals > USD_PRECISION_DECIMALS) {
            revert KUSDEngine__UnsupportedDecimals(collateralAddress);
        }

        return (normalizedPrice, collateralDecimals);
    }

    /**
     * @notice Internal calculates health factor helper function.
     * @dev Health factor < 1e18 means liquidatable.
     * Formula: HF = (collateralValueInUsd * 50 / 100) * 1e18 / totalKusdMinted
     * @param totalKusdMinted The total kusd minted by an account.
     * @param collateralValueInUsd The account's collateral value in usd.
     * @return healthFactor The user's health factor, scaled by 1e18.
     */
    function _calculateHealthFactor(uint256 totalKusdMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        // Return if user has zero KUSD minted.
        if (totalKusdMinted == 0) {
            return type(uint256).max; // no debt => safest state
        }
        // Calculate health factor.
        uint256 liquidationAdjustedCollateralUsd =
            (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (liquidationAdjustedCollateralUsd * PRECISION) / totalKusdMinted;
    }
}
