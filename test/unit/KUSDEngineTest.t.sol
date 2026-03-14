// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployKUSDEngine} from "script/DeployKUSDEngine.s.sol";
import {KUSDEngine} from "src/KUSDEngine.sol";
import {IKUSDEngine} from "src/interfaces/IKUSDEngine.sol";
import {KingUSD} from "src/token/KingUSD.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {KingSafeERC20} from "src/Utils/KingSafeERC20.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {MockBadERC20} from "test/mocks/MockBadERC20.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

contract KUSDEngineTest is Test {
    DeployKUSDEngine public deployer;
    KUSDEngine public kUsdEngine;
    KingUSD public kUsd;
    HelperConfig public config;
    MockV3Aggregator public newEthPriceFeed;

    address public wEth;
    address public wBtc;
    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address[] public collateralAddresses;
    address[] public priceFeedAddresses;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    address public zero = makeAddr("ZERO");
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_BONUS = 15;

    // ================================== SetUp Function ===========================
    function setUp() public {
        deployer = new DeployKUSDEngine();
        (kUsd, kUsdEngine, config) = deployer.run();
        (wEth, wBtc, ethUsdPriceFeed, btcUsdPriceFeed) = config.activeNetworkConfig();

        MockERC20(wEth).mint(user, STARTING_ERC20_BALANCE);
        MockERC20(wEth).mint(liquidator, STARTING_ERC20_BALANCE);
    }
    // ================================= Modifier ====================================
    modifier depositCollateral() {
        vm.startPrank(user);
        MockERC20(wEth).approve(address(kUsdEngine), COLLATERAL_AMOUNT);
        kUsdEngine.depositCollateral(wEth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier mintKusd() {
        uint256 kUsdAmount = 100e18;

        vm.prank(user);
        kUsdEngine.mintKusd(kUsdAmount);
        _;
    }

    // ================================= Unit Test: Constructor ======================
    function testConstructorInitializesCorrectly() public {
        collateralAddresses.push(wEth);
        collateralAddresses.push(wBtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUsd)));
    }

    function testConstructor_RevertsKUSDEngine__ArrayLengthMismatch() public {
        collateralAddresses.push(wEth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(IKUSDEngine.KUSDEngine__ArrayLengthMismatch.selector);
        new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUsd)));
    }

    function testConstructor_RevertsKUSDEngine__InvalidAddress() public {
        collateralAddresses.push(wEth);
        collateralAddresses.push(wBtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(IKUSDEngine.KUSDEngine__InvalidAddress.selector);
        new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(user)));
    }

    // ================================= Unit Test: Deposit Collateral ==============
    function testDepositCollateral_Succeeds_And_ReturnsAccountInformation() public depositCollateral {
        (uint256 totalKusdMinted, uint256 collateralValueInUsd) = kUsdEngine.getAccountInformation(user);

        uint256 expectedTotalKusdMinted = 0;
        uint256 expectedDepositAmount = kUsdEngine.getCollateralAmountFromUsd(wEth, collateralValueInUsd);

        assertEq(totalKusdMinted, expectedTotalKusdMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }

    function testDepositCollateral_RevertsKUSDEngine__AmountMustBeGreaterThanZero() public {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(user);
        kUsdEngine.depositCollateral(wEth, 0);
    }

    function testDepositCollateral_RevertsKUSDEngine__InvalidCollateral() public {
        vm.prank(user);
        MockERC20 fakeToken = new MockERC20("Fake Token", "fake", STARTING_ERC20_BALANCE);
        uint256 amount = 15e18;

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__InvalidCollateral.selector, address(fakeToken)));
        vm.prank(user);
        kUsdEngine.depositCollateral(address(fakeToken), amount);
    }

    function testDepositCollateral_RevertsKingSafeERC20__TokenTransferFailed() public {
        // Note: Caller didn't approve contract to spend wEth.
        vm.expectRevert(
            abi.encodeWithSelector(
                KingSafeERC20.KingSafeERC20__TokenTransferFailed.selector, address(wBtc), COLLATERAL_AMOUNT
            )
        );
        vm.prank(user);
        kUsdEngine.depositCollateral(address(wBtc), COLLATERAL_AMOUNT);
    }

    // ============================== Unit Test: Mint KUSD ==============================
    function testMintKUSD_Succeeds() public depositCollateral mintKusd {
        (uint256 totalKusdMinted, uint256 collateralValueInUsd) = kUsdEngine.getAccountInformation(user);

        uint256 kUsdBalance = kUsdEngine.getKusdBalanceOf(user);

        assertEq(totalKusdMinted, kUsdBalance);
        assertGt(collateralValueInUsd, kUsdBalance);
    }

    function testMintKUSD_RevertsKUSDEngine__AmountMustBeGreaterThanZero() public depositCollateral {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(user);
        kUsdEngine.mintKusd(0);
    }

    function testMintKUSD_RevertsKingSafeERC20__TokenTransferFailed() public {
        uint256 amount = 10e18;

        // Note: Caller didn't approve contract to spend wEth.
        vm.expectRevert(
            abi.encodeWithSelector(KingSafeERC20.KingSafeERC20__TokenTransferFailed.selector, address(wEth), amount)
        );
        vm.prank(user);
        kUsdEngine.depositCollateralAndMintKusd(wEth, COLLATERAL_AMOUNT, amount);
    }

    function testMintKUSD_RevertsKUSDEngine__HealthFactorIsBelowMinimum() public {
        uint256 amount = 10e18;

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__HealthFactorIsBelowMinimum.selector, user, 0));
        vm.prank(user);
        kUsdEngine.mintKusd(amount);
    }

    function testMintKusd_RevertsKUSDEngine__MintFailed() public {
        MockBadERC20 badToken = new MockBadERC20("Bad Token", "BAD", STARTING_ERC20_BALANCE);

        collateralAddresses.push(wEth);
        collateralAddresses.push(wBtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        KUSDEngine badEngine = new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(badToken)));

        vm.startPrank(user);
        MockERC20(wEth).approve(address(badEngine), COLLATERAL_AMOUNT);
        badEngine.depositCollateral(wEth, COLLATERAL_AMOUNT);
        uint256 amount = 1e18;
        vm.stopPrank();

        vm.expectRevert(IKUSDEngine.KUSDEngine__MintFailed.selector);
        vm.prank(user);
        badEngine.mintKusd(amount);
    }

    // ======================= Unit Test: Redeem Collateral ========================
    function testRedeemCollateral_Succeeds() public depositCollateral {
        uint256 balanceBefore = MockERC20(wEth).balanceOf(user);

        vm.prank(user);
        kUsdEngine.redeemCollateral(wEth, COLLATERAL_AMOUNT);

        uint256 balanceAfter = MockERC20(wEth).balanceOf(user);
        assertGt(balanceAfter, balanceBefore);
    }

    function testRedeemCollateral_RevertsKUSDEngine__AmountMustBeGreaterThanZero() public depositCollateral {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(user);
        kUsdEngine.redeemCollateral(wEth, 0);
    }

    function testRedeemCollateral_RevertsKUSDEngine__AmountGreaterThanBalance() public depositCollateral mintKusd {
        uint256 amount = 50000e18;

        vm.expectRevert(
            abi.encodeWithSelector(IKUSDEngine.KUSDEngine__AmountGreaterThanBalance.selector, COLLATERAL_AMOUNT)
        );
        vm.prank(user);
        kUsdEngine.redeemCollateral(wEth, amount);
    }

    function testRedeemCollateral_RevertsKUSDEngine__InvalidCollateral() public {
        vm.prank(user);
        MockERC20 fakeToken = new MockERC20("Fake Token", "FAKE", STARTING_ERC20_BALANCE);
        uint256 amount = 15e18;

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__InvalidCollateral.selector, address(fakeToken)));
        vm.prank(user);
        kUsdEngine.redeemCollateral(address(fakeToken), amount);
    }

    function testRedeemCollateral_RevertsKingSafeERC20__TokenTransferFailed() public {
        vm.prank(user);
        MockBadERC20 badToken = new MockBadERC20("Bad Token", "BAD", STARTING_ERC20_BALANCE);

        collateralAddresses.push(address(badToken));
        collateralAddresses.push(wBtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        KUSDEngine badEngine = new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUsd)));

        vm.startPrank(user);
        MockERC20(address(badToken)).approve(address(badEngine), COLLATERAL_AMOUNT);
        badEngine.depositCollateral(address(badToken), COLLATERAL_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                KingSafeERC20.KingSafeERC20__TokenTransferFailed.selector, address(badToken), COLLATERAL_AMOUNT
            )
        );

        badEngine.redeemCollateral(address(badToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    // ====================== Unit Test: Burn KUSD =================================
    function testBurnKUSD_Succeeds() public depositCollateral mintKusd {
        uint256 balance = kUsdEngine.getKusdBalanceOf(user);

        vm.startPrank(user);
        kUsd.approve(address(kUsdEngine), balance);
        kUsdEngine.burnKusd(balance);
        vm.stopPrank();

        assertEq(kUsdEngine.getKusdBalanceOf(user), 0);
    }

    function testBurnKUSD_RevertsKUSDEngine__AmountGreaterThanBalance() public depositCollateral mintKusd {
        uint256 amount = 5000e18;
        vm.prank(user);
        kUsd.approve(address(kUsdEngine), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IKUSDEngine.KUSDEngine__AmountGreaterThanBalance.selector, kUsdEngine.getKusdBalanceOf(user)
            )
        );
        vm.prank(user);
        kUsdEngine.burnKusd(amount);
    }

    // ========================= Unit Test: RedeemCollateralForKUSD ==================
    function testRedeemCollateralForKUSD_Succeeds() public depositCollateral mintKusd {
        uint256 kUsdAmount = 100e18; // $100
        uint256 balanceBeforeRedeem = MockERC20(wEth).balanceOf(user);

        vm.startPrank(user);
        kUsd.approve(address(kUsdEngine), kUsdAmount);
        kUsdEngine.redeemCollateralForKusd(wEth, COLLATERAL_AMOUNT, kUsdAmount);
        vm.stopPrank();

        uint256 balanceAfterRedeem = MockERC20(wEth).balanceOf(user);

        assertGt(balanceAfterRedeem, balanceBeforeRedeem);
    }

    function testRedeemCollateralForKUSD_RevertsKUSDEngine__AmountMustBeGreaterThanZero()
        public
        depositCollateral
        mintKusd
    {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(user);
        kUsdEngine.redeemCollateralForKusd(wEth, 0, 0);
    }

    // ========================= Unit Test: Liquidate ================================
    function testLiquidate_Succeeds() public depositCollateral {
        // record initial user state
        uint256 userInitialCollateralValueInUsd = kUsdEngine.getAccountCollateralValue(user);
        uint256 kUsdAmount = 10000e18;

        // user mints and we verify health factor sits exactly at the minimum
        vm.prank(user);
        kUsdEngine.mintKusd(kUsdAmount);
        uint256 userInitialHealthFactor = kUsdEngine.getHealthFactor(user);
        assertEq(userInitialHealthFactor, kUsdEngine.getMinimumHealthFactor());

        // drop the price so the user becomes under‑collateralized
        int256 newPrice = 1500e8; // $1,500 per ETH -> 10 ETH = $15,000
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);

        // health factor should now be below the minimum
        uint256 userHfAfterDrop = kUsdEngine.getHealthFactor(user);
        assertLt(userHfAfterDrop, kUsdEngine.getMinimumHealthFactor());

        // prepare the liquidator with enough KUSD to cover the debt
        uint256 liquidatorCollateralAmount = 100 ether;
        vm.startPrank(liquidator);
        MockERC20(wEth).approve(address(kUsdEngine), liquidatorCollateralAmount);
        kUsdEngine.depositCollateralAndMintKusd(wEth, liquidatorCollateralAmount, kUsdAmount);
        uint256 liquidatorBalanceBefore = MockERC20(wEth).balanceOf(liquidator);
        uint256 liquidatorInitialHealthFactor = kUsdEngine.getHealthFactor(liquidator);

        // perform liquidation
        kUsd.approve(address(kUsdEngine), kUsdAmount);
        kUsdEngine.liquidate(wEth, user, kUsdAmount);
        uint256 liquidatorBalanceAfter = MockERC20(wEth).balanceOf(liquidator);
        uint256 liquidatorCurrentHealthFactor = kUsdEngine.getHealthFactor(liquidator);
        vm.stopPrank();

        // check post‑liquidation user state
        uint256 userCurrentHealthFactor = kUsdEngine.getHealthFactor(user);
        uint256 userCurrentCollateralValueInUsd = kUsdEngine.getAccountCollateralValue(user);

        assertLt(userCurrentCollateralValueInUsd, userInitialCollateralValueInUsd, "user lost collateral");
        assertGt(userCurrentHealthFactor, userInitialHealthFactor, "health factor improved");
        assertEq(kUsdEngine.getKusdBalanceOf(user), 0, "debt should be cleared");

        // verify liquidator benefited and their health factor changed
        assertGt(liquidatorBalanceAfter, liquidatorBalanceBefore, "liquidator received collateral");
        assertEq(liquidatorCurrentHealthFactor, liquidatorInitialHealthFactor, "liquidator HF remains the same '7' ");
        assertEq(kUsdEngine.getKusdBalanceOf(liquidator), kUsdAmount, "liquidator still owe own debt");
    }

    function testLiquidate_RevertsKUSDEngine__HealthFactorAboveMinimum() public depositCollateral mintKusd {
        uint256 kUsdAmount = 10000e18;
        uint256 liquidatorCollateralAmount = 100 ether;

        vm.startPrank(liquidator);
        MockERC20(wEth).approve(address(kUsdEngine), liquidatorCollateralAmount);
        kUsdEngine.depositCollateralAndMintKusd(wEth, liquidatorCollateralAmount, kUsdAmount);
        kUsd.approve(address(kUsdEngine), kUsdAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IKUSDEngine.KUSDEngine__HealthFactorAboveMinimum.selector, user, kUsdEngine.getHealthFactor(user)
            )
        );
        kUsdEngine.liquidate(wEth, user, kUsdAmount);
        vm.stopPrank();
    }

    function testLiquidate_RevertsKUSDEngine__UserHealthFactorNotImproved() public depositCollateral {
        uint256 kUsdAmount = 10000e18;

        vm.prank(user);
        kUsdEngine.mintKusd(kUsdAmount);

        // drop the price so the user becomes under‑collateralized
        int256 newPrice = 1000e8; // $1,000 per ETH -> 10 ETH = $10,000
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);
        uint256 userCurrentHealthFactor = kUsdEngine.getHealthFactor(user);

        assertLt(userCurrentHealthFactor, kUsdEngine.getMinimumHealthFactor());

        uint256 liquidatorCollateralAmount = 100 ether;
        uint256 liquidateAmount = 1e18; // tiny amount that won't improve HF enough

        vm.startPrank(liquidator);
        MockERC20(wEth).approve(address(kUsdEngine), liquidatorCollateralAmount);
        kUsdEngine.depositCollateralAndMintKusd(wEth, liquidatorCollateralAmount, liquidateAmount);
        kUsd.approve(address(kUsdEngine), liquidateAmount);
        vm.stopPrank();

        vm.expectRevert(IKUSDEngine.KUSDEngine__UserHealthFactorNotImproved.selector);
        vm.startPrank(liquidator);
        kUsdEngine.liquidate(wEth, user, liquidateAmount);
        vm.stopPrank();
    }

    function testLiquidate_RevertsKUSDEngine__HealthFactorIsBelowMinimum() public depositCollateral {
        uint256 kUsdAmount = 10000e18;

        vm.prank(user);
        kUsdEngine.mintKusd(kUsdAmount);

        vm.startPrank(liquidator);
        MockERC20(wEth).approve(address(kUsdEngine), COLLATERAL_AMOUNT);
        kUsdEngine.depositCollateralAndMintKusd(wEth, COLLATERAL_AMOUNT, kUsdAmount);
        vm.stopPrank();

        uint256 userInitialHealthFactor = kUsdEngine.getHealthFactor(user);
        assertEq(userInitialHealthFactor, kUsdEngine.getMinimumHealthFactor());

        int256 newPrice = 1500e8;
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(newPrice);

        uint256 userCurrentHealthFactor = kUsdEngine.getHealthFactor(user);
        assertLt(userCurrentHealthFactor, kUsdEngine.getMinimumHealthFactor());

        vm.startPrank(liquidator);
        kUsd.approve(address(kUsdEngine), kUsdAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKUSDEngine.KUSDEngine__HealthFactorIsBelowMinimum.selector,
                liquidator,
                kUsdEngine.getHealthFactor(liquidator)
            )
        );
        kUsdEngine.liquidate(wEth, user, kUsdAmount);
        vm.stopPrank();
    }

    function testLiquidate_RevertsKUSDEngine__AmountMustBeGreaterThanZero() public depositCollateral mintKusd {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(liquidator);
        kUsdEngine.liquidate(wEth, user, 0);
    }

    function testLiquidate_RevertsOracleLib__StalePrice() public depositCollateral {
        uint256 kUsdAmount = 10000e18;

        vm.prank(user);
        kUsdEngine.mintKusd(kUsdAmount);

        // health factor sits at minimum
        uint256 userInitialHealthFactor = kUsdEngine.getHealthFactor(user);
        assertEq(userInitialHealthFactor, kUsdEngine.getMinimumHealthFactor());

        // advance time beyond TIMEOUT without updating oracle
        vm.warp(block.timestamp + 5 hours);

        // expect revert due to stale price
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        kUsdEngine.liquidate(wEth, user, kUsdAmount);
    }

    // ======================= Unit Test: External Read Function ===================
    function testGetHealthFactor_Returns() public depositCollateral mintKusd {
        assertGt(kUsdEngine.getHealthFactor(user), kUsdEngine.getMinimumHealthFactor());
    }

    function testCalculateHealthFactor_Returns() public depositCollateral mintKusd {
        uint256 expectedHealthFactor = 100e18;
        (uint256 totalKusdMinted, uint256 collateralValueInUsd) = kUsdEngine.getAccountInformation(user);
        uint256 userHealthFactor = kUsdEngine.calculateHealthFactor(totalKusdMinted, collateralValueInUsd);
        assertEq(userHealthFactor, expectedHealthFactor);
    }

    function testGetCollateralAddresses_Returns() public view {
        address[] memory collaterals = kUsdEngine.getCollateralAddresses();
        assertEq(collaterals[0], wEth);
        assertEq(collaterals[1], wBtc);
    }

    function testGetLiquidationThreshold_Returns() public view {
        assertEq(kUsdEngine.getLiquidationThreshold(), LIQUIDATION_THRESHOLD);
    }

    function testCollateralBalanceOf_Returns() public depositCollateral {
        assertEq(kUsdEngine.getCollateralBalanceOf(user, wEth), COLLATERAL_AMOUNT);
    }

    function testGetCollateralPricefeedAddress_Returns() public view {
        assertEq(kUsdEngine.getCollateralPriceFeedAddress(wEth), ethUsdPriceFeed);
        assertEq(kUsdEngine.getCollateralPriceFeedAddress(wBtc), btcUsdPriceFeed);
    }

    function testGetLiquidationBonus_Returns() public view {
        assertEq(kUsdEngine.getLiquidationBonus(), LIQUIDATION_BONUS);
    }

    function testGetKusd_Returns() public view {
        assertEq(address(kUsd), kUsdEngine.getKusd());
    }

    // ======================= Unit Test: Public Read Function =====================
    function testGetCollateralUSDValue_Returns() public view {
        uint256 amount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = kUsdEngine.getCollateralUsdValue(wEth, amount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetCollateralUSDValue_RevertsKUSDEngine__InvalidOraclePrice() public {
        uint256 amount = 15e18;

        int256 newPrice = -1000e8;
        MockV3Aggregator(btcUsdPriceFeed).updateAnswer(newPrice);

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__InvalidOraclePrice.selector, wBtc));
        kUsdEngine.getCollateralUsdValue(wBtc, amount);
    }

    function testGetCollateralUSDValue_RevertsKUSDEngine__UnsupportedDecimals() public {
        uint256 amount = 15e18;

        uint8 unsafeDecimals = 78;

        int256 btcUsdPrice = 10000;

        // create a feed whose decimals exceed MAX_SAFE_DECIMALS
        MockV3Aggregator badFeed = new MockV3Aggregator(unsafeDecimals, btcUsdPrice);

        collateralAddresses.push(wEth);
        collateralAddresses.push(wBtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(address(badFeed));
        KUSDEngine badEngine = new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUsd)));

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__UnsupportedDecimals.selector, wBtc));
        badEngine.getCollateralUsdValue(wBtc, amount);
    }

    function testGetCollateralUSDValue_RevertsOnDecimalsGreaterThan18() public {
        uint256 amount = 15e18;

        uint8 decimals = 19;

        int256 btcUsdPrice = 10000;

        // create a feed whose decimals exceed 18.
        MockV3Aggregator badFeed = new MockV3Aggregator(decimals, btcUsdPrice);

        collateralAddresses.push(wEth);
        collateralAddresses.push(wBtc);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(address(badFeed));
        KUSDEngine badEngine = new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUsd)));

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__UnsupportedDecimals.selector, wBtc));
        badEngine.getCollateralUsdValue(wBtc, amount);
    }

    function testGetCollateralAmountFromUSD_Returns() public view {
        uint256 usdAmount = 100e18;
        uint256 expectedWeth = 0.05e18;
        uint256 actualWeth = kUsdEngine.getCollateralAmountFromUsd(wEth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }
}
