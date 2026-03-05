// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IKUSDEngine} from "src/interfaces/IKUSDEngine.sol";
import {KingUSD} from "src/token/KingUSD.sol";
import {IERC20} from "@buildswithking-security/tokens/ERC20/interfaces/IERC20.sol";
import {IERC20Metadata} from "@buildswithking-security/tokens/ERC20/interfaces/IERC20Metadata.sol";
import {KingSafeERC20} from "src/Utils/KingSafeERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {KingClaimMistakenETH} from "@buildswithking-security/access/guards/KingClaimMistakenETH.sol";

/**
 * @title KUSDEngine - The engine contract controlling KUSD minting and burning.
 * @author Michealking (@BuildsWithKing)
 * @dev This contract accepts WETH and WBTC as collateral, uses an algorithm for its minting & burning and it is pegged to USD.
 *
 * @notice This is an KingUSD governing contract.
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
    using KingSafeERC20 for IERC20;

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
    mapping(address user => uint256 kUSD) private s_kUSDMinted;

    /// @notice Records collateral tokens addresses.
    address[] private s_collateralTokens;

    /// @notice Records KingUSD token address.
    KingUSD public immutable i_kUSD;

    // =============================== Modifiers ================================================
    /**
     * @notice Validates amount and revert if amount is equal to zero.
     * @dev Ensures amount is greater than zero.
     * @param amount The amount to be validated.
     */
    modifier validateAmount(uint256 amount) {
        // Revert if amount is equal to zero.
        if (amount == 0) {
            revert KUSDEngine__AmountMustBeGreaterThanZero();
        }
        _;
    }

    /**
     * @notice Validates address and revert if the address's pricefeed is the zero address.
     * @dev Ensures each address has an existing pricefeed and reverts if pricefeed is the zero address.
     * @param collateralAddress The address to be validated.
     */
    modifier onlyAllowedCollateral(address collateralAddress) {
        if (s_priceFeeds[collateralAddress] == address(0)) {
            revert KUSDEngine__InvalidCollateral(collateralAddress);
        }
        _;
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
            if (
                collateralAddresses[i] == address(0) || collateralAddresses[i] == kusdAddress
                    || collateralAddresses[i].code.length == 0 || priceFeedAddresses[i] == address(0)
                    || priceFeedAddresses[i].code.length == 0 || priceFeedAddresses[i] == kusdAddress
            ) {
                revert KUSDEngine__InvalidAddress();
            }
            s_priceFeeds[collateralAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(collateralAddresses[i]);
            unchecked {
                ++i;
            }
        }
        i_kUSD = KingUSD(kusdAddress);
    }
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
    ) external {
        // Call the depositCollateral and mintKUSD public function.
        depositCollateral(collateralAddress, collateralAmount);
        mintKUSD(amountOfKUSDToMint);
    }

    /**
     * @notice Burns KUSD and redeems caller's collateral.
     * @param collateralAddress The address of the collateral to redeem.
     * @param collateralAmount The amount of collateral to redeem.
     * @param amountOfKUSD The amount of KUSD to burn.
     */
    function redeemCollateralForKUSD(address collateralAddress, uint256 collateralAmount, uint256 amountOfKUSD)
        external
    {
        burnKUSD(amountOfKUSD);
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
        uint256 userPreviousHealthFactor = _calculateHealthFactor(user);
        if (userPreviousHealthFactor >= MIN_HEALTH_FACTOR) {
            revert KUSDEngine__HealthFactorAboveMinimum(userPreviousHealthFactor);
        }
        // Read the user's collateral amount from USD.
        uint256 userCollateralAmount = getCollateralAmountFromUSD(collateralAddress, debtToCover);
        // Calculate the caller's bonus for liquidating a user and add it to the total collateral to be redeemed.
        uint256 bonusCollateral = (userCollateralAmount * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = userCollateralAmount + bonusCollateral;

        // Redeem collateral to the caller and burn kusd.
        _redeemCollateral(user, collateralAddress, totalCollateralToRedeem);
        _burnKUSD(user, msg.sender, debtToCover);

        // Read user's current health factor and  revert if less than or equal to user's Previous HF. 
        uint256 userCurrentHealthFactor = _calculateHealthFactor(user);
        if (userCurrentHealthFactor <= userPreviousHealthFactor) {
            revert KUSDEngine__UserHealthFactorNotImproved(userCurrentHealthFactor);
        }
        _revertIfUserHealthFactorIsBroken(msg.sender);
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
    function mintKUSD(uint256 amount) public nonReentrant validateAmount(amount) {
        // Add amount to the number of tokens minted by the caller.
        s_kUSDMinted[msg.sender] += amount;

        // Call the internal function and check the caller's health factor.
        _revertIfUserHealthFactorIsBroken(msg.sender);

        // Mint KUSD to the caller.
        bool success = i_kUSD.mint(msg.sender, amount);
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
    }

    /**
     * @notice Burns KUSD. i.e Removes certain amount of the KUSD from existence.
     * @param amount The amount of KUSD to be burned.
     */
    function burnKUSD(uint256 amount) public nonReentrant validateAmount(amount) {
        _burnKUSD(msg.sender, msg.sender, amount);
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

        // Revert if user's health factor is less than the minimum health factor.
        _revertIfUserHealthFactorIsBroken(user);
    }

    /**
     * @notice Burns KUSD. i.e Removes certain amount of the KUSD from existence.
     * @param onBehalfOf The debtor's address.
     * @param from The caller's address.
     * @param amount The amount of KUSD to be burned.
     */
    function _burnKUSD(address onBehalfOf, address from, uint256 amount) private validateAmount(amount) {
        // Read debtor's KUSD balance.
        uint256 kUSDBalance = s_kUSDMinted[onBehalfOf];

        // Revert if amount is greater than the debtor's balance.
        if (amount > kUSDBalance) {
            revert KUSDEngine__AmountGreaterThanBalance(kUSDBalance);
        }

        // Deduct amount from debtor's KUSD balance.
        s_kUSDMinted[onBehalfOf] = kUSDBalance - amount;

        // Safely transfer KUSD from the caller to this contract.
        IERC20(i_kUSD).safeTransferFrom(from, address(this), amount);

        i_kUSD.burn(amount);
    }

    // =============================== External Read Functions ==================================
    /**
     * @notice Returns the user's health factor.
     * @param user The user's address.
     */
    function getHealthFactor(address user) external view returns (uint256 healthFactor) {
        return _calculateHealthFactor(user);
    }

    // =============================== Public Read Functions ====================================
    /**
     * @notice Returns the collateral token amount equivalent to a USD amount.
     * @param collateralAddress The collateral token address.
     * @param usdAmountInWei The USD amount scaled to 1e18 (e.g. 1 USD = 1e18).
     * @return collateralAmount The collateral amount in the token's base units.
     */
    function getCollateralAmountFromUSD(address collateralAddress, uint256 usdAmountInWei)
        public
        view
        onlyAllowedCollateral(collateralAddress)
        returns (uint256 collateralAmount)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

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
     * @return totalCollateralValueInUSD The user's total collateral value in USD.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length;) {
            address collateralAddress = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][collateralAddress];
            totalCollateralValueInUSD += getCollateralUSDValue(collateralAddress, amount);
            unchecked {
                ++i;
            }
        }
        return totalCollateralValueInUSD;
    }

    /**
     * @notice Returns USD value scaled to 1e18 precision.
     * @dev Uses chainlink aggregatorV3Interface to fetch the current price of the collateral token.
     * Scales oracle price to 1e18 using `priceFeed.decimals()` and then normalizes by collateral token decimals.
     * @param collateralAddress The token collateral address.
     * @param amount The amount of token
     * @return The USD value of the amount of token
     */
    function getCollateralUSDValue(address collateralAddress, uint256 amount)
        public
        view
        onlyAllowedCollateral(collateralAddress)
        returns (uint256)
    {
        // Read the collateral's token price using its address from chainlink.
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[collateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

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

    // =============================== Private Read Functions ===================================
    /**
     * @notice Returns the user's account information.
     * @param user The user's address.
     * @return totalKUSDMinted The total KUSD minted by the user.
     * collateralValueInUSD The user's collateral's value in dollar.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalKUSDMinted, uint256 collateralValueInUSD)
    {
        totalKUSDMinted = s_kUSDMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);

        return (totalKUSDMinted, collateralValueInUSD);
    }

    /**
     * @notice Returns the user's health factor.
     * @dev Health factor < 1e18 means liquidatable.
     * Formula: HF = (collateralUsd * 50 / 100) * 1e18 / totalKUSDMinted
     * @param user The user's address.
     * @return healthFactor The user's health factor, scaled by 1e18.
     */
    function _calculateHealthFactor(address user) private view returns (uint256 healthFactor) {
        (uint256 totalKUSDMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);

        // Return if user has zero KUSD minted.
        if (totalKUSDMinted == 0) {
            return type(uint256).max; // no debt => safest state
        }

        // Calculate the user's health factor.
        uint256 liquidationAdjustedCollateralUsd =
            (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return (liquidationAdjustedCollateralUsd * PRECISION) / totalKUSDMinted;
    }

    // ======================================== Internal View Function =========================
    /**
     * @notice Checks user's health factor and revert if user don't have enough collateral.
     * @param user The user's address.
     */
    function _revertIfUserHealthFactorIsBroken(address user) internal view {
        // Read user's health factor.
        uint256 userHealthFactor = _calculateHealthFactor(user);

        // Revert if the user's health factor is less than 1.
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert KUSDEngine__HealthFactorIsBelowMinimum(userHealthFactor);
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
}
