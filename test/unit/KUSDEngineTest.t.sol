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

contract KUSDEngineTest is Test {
    DeployKUSDEngine public deployer;
    KUSDEngine public kUSDEngine;
    KingUSD public kUSD;
    HelperConfig public config;
    MockV3Aggregator public newETHPriceFeed;

    address public wETH;
    address public wBTC;
    address public ethUSDPriceFeed;
    address public btcUSDPriceFeed;
    address[] public collateralAddresses;
    address[] public priceFeedAddresses;

    address public USER = makeAddr("USER");
    address public LIQUIDATOR = makeAddr("LIQUIDATOR");
    address public ZERO = makeAddr("ZERO");
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 100e18;

    // ================================== SetUp Function ===========================
    function setUp() public {
        deployer = new DeployKUSDEngine();
        (kUSD, kUSDEngine, config) = deployer.run();
        (wETH, wBTC, ethUSDPriceFeed, btcUSDPriceFeed) = config.activeNetworkConfig();

        MockERC20(wETH).mint(USER, STARTING_ERC20_BALANCE);
        MockERC20(wETH).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }
    // ================================= Modifier ====================================
    modifier depositCollateral() {
        vm.startPrank(USER);
        MockERC20(wETH).approve(address(kUSDEngine), COLLATERAL_AMOUNT);
        kUSDEngine.depositCollateral(wETH, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier mintKUSD() {
        uint256 kUSDAmount = 100e18;

        vm.prank(USER);
        kUSDEngine.mintKUSD(kUSDAmount);
        _;
    }

    // ================================= Unit Test: Constructor ======================
    function testConstructorInitializesCorrectly() public {
        collateralAddresses.push(wETH);
        collateralAddresses.push(wBTC);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);
        new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUSD)));
    }

    function testConstructor_RevertsKUSDEngine__ArrayLengthMismatch() public {
        collateralAddresses.push(wETH);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);

        vm.expectRevert(IKUSDEngine.KUSDEngine__ArrayLengthMismatch.selector);
        new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUSD)));
    }

    function testConstructor_RevertsKUSDEngine__InvalidAddress() public {
        collateralAddresses.push(wETH);
        collateralAddresses.push(wBTC);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);

        vm.expectRevert(IKUSDEngine.KUSDEngine__InvalidAddress.selector);
        new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(USER)));
    }

    function testConstructor_RevertsKUSDEngine__SameCollateralAddress() public {
        collateralAddresses.push(wETH);
        collateralAddresses.push(wETH);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(btcUSDPriceFeed);

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__SameCollateralAddress.selector, wETH));
        new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUSD)));
    }

    // ================================= Unit Test: Deposit Collateral ==============
    function testDepositCollateral_Succeeds_And_ReturnsAccountInformation() public depositCollateral {
        (uint256 totalKUSDMinted, uint256 collateralValueInUSD) = kUSDEngine.getAccountInformation(USER);

        uint256 expectedTotalKUSDMinted = 0;
        uint256 expectedDepositAmount = kUSDEngine.getCollateralAmountFromUSD(wETH, collateralValueInUSD);

        assertEq(totalKUSDMinted, expectedTotalKUSDMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }

    function testDepositCollateral_RevertsKUSDEngine__AmountMustBeGreaterThanZero() public {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(USER);
        kUSDEngine.depositCollateral(wETH, 0);
    }

    function testDepositCollateral_RevertsKUSDEngine__InvalidCollateral() public {
        vm.prank(USER);
        MockERC20 fakeToken = new MockERC20("Fake Token", "fake", STARTING_ERC20_BALANCE);
        uint256 amount = 15e18;

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__InvalidCollateral.selector, address(fakeToken)));
        vm.prank(USER);
        kUSDEngine.depositCollateral(address(fakeToken), amount);
    }

    // ============================== Unit Test: Mint KUSD ==============================
    function testMintKUSD_Succeeds() public depositCollateral mintKUSD {
        (uint256 totalKUSDMinted, uint256 collateralValueInUSD) = kUSDEngine.getAccountInformation(USER);

        uint256 kUSDBalance = kUSDEngine.getKUSDBalanceOf(USER);

        assertEq(totalKUSDMinted, kUSDBalance);
        assertGt(collateralValueInUSD, kUSDBalance);
    }

    function testMintKUSD_RevertsKUSDEngine__AmountMustBeGreaterThanZero() public depositCollateral {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(USER);
        kUSDEngine.mintKUSD(0);
    }

    function testMintKUSD_RevertsKingSafeERC20__TokenTransferFailed() public {
        uint256 amount = 10e18;

        // Note: Caller didn't approve contract to spend wETH.
        vm.expectRevert(
            abi.encodeWithSelector(KingSafeERC20.KingSafeERC20__TokenTransferFailed.selector, address(wETH), amount)
        );
        vm.prank(USER);
        kUSDEngine.depositCollateralAndMintKUSD(wETH, COLLATERAL_AMOUNT, amount);
    }

    function testMintKUSD_RevertsKUSDEngine__HealthFactorIsBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__HealthFactorIsBelowMinimum.selector, USER, 0));
        vm.prank(USER);
        kUSDEngine.mintKUSD(1e18);
    }

    // ======================= Unit Test: Redeem Collateral ========================
    function testRedeemCollateral_Succeeds() public depositCollateral {
        uint256 balanceBefore = MockERC20(wETH).balanceOf(USER);

        vm.prank(USER);
        kUSDEngine.redeemCollateral(wETH, COLLATERAL_AMOUNT);

        uint256 balanceAfter = MockERC20(wETH).balanceOf(USER);
        assertGt(balanceAfter, balanceBefore);
    }

    function testRedeemCollateral_RevertsKUSDEngine__AmountMustBeGreaterThanZero() public depositCollateral {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(USER);
        kUSDEngine.redeemCollateral(wETH, 0);
    }

    function testRedeemCollateral_RevertsKUSDEngine__AmountGreaterThanBalance() public depositCollateral mintKUSD {
        uint256 amount = 50000e18;

        vm.expectRevert(
            abi.encodeWithSelector(IKUSDEngine.KUSDEngine__AmountGreaterThanBalance.selector, COLLATERAL_AMOUNT)
        );
        vm.prank(USER);
        kUSDEngine.redeemCollateral(wETH, amount);
    }

    function testRedeemCollateral_RevertsKUSDEngine__InvalidCollateral() public {
        vm.prank(USER);
        MockERC20 fakeToken = new MockERC20("Fake Token", "fake", STARTING_ERC20_BALANCE);
        uint256 amount = 15e18;

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__InvalidCollateral.selector, address(fakeToken)));
        vm.prank(USER);
        kUSDEngine.redeemCollateral(address(fakeToken), amount);
    }

    // ====================== Unit Test: Burn KUSD =================================
    function testBurnKUSD_Succeeds() public depositCollateral mintKUSD {
        uint256 balance = kUSDEngine.getKUSDBalanceOf(USER);

        vm.startPrank(USER);
        kUSD.approve(address(kUSDEngine), balance);
        kUSDEngine.burnKUSD(balance);
        vm.stopPrank();

        assertEq(kUSDEngine.getKUSDBalanceOf(USER), 0);
    }

    function testBurnKUSD_RevertsKUSDEngine__AmountGreaterThanBalance() public depositCollateral mintKUSD {
        uint256 amount = 5000e18;
        vm.prank(USER);
        kUSD.approve(address(kUSDEngine), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IKUSDEngine.KUSDEngine__AmountGreaterThanBalance.selector, kUSDEngine.getKUSDBalanceOf(USER)
            )
        );
        vm.prank(USER);
        kUSDEngine.burnKUSD(amount);
    }

    // ========================= Unit Test: RedeemCollateralForKUSD ==================
    function testRedeemCollateralForKUSD_Succeeds() public depositCollateral mintKUSD {
        uint256 kUSDAmount = 100e18; // $100
        uint256 balanceBeforeRedeem = MockERC20(wETH).balanceOf(USER);

        vm.startPrank(USER);
        kUSD.approve(address(kUSDEngine), kUSDAmount);
        kUSDEngine.redeemCollateralForKUSD(wETH, COLLATERAL_AMOUNT, kUSDAmount);
        vm.stopPrank();

        uint256 balanceAfterRedeem = MockERC20(wETH).balanceOf(USER);

        assertGt(balanceAfterRedeem, balanceBeforeRedeem);
    }

    // ========================= Unit Test: Liquidate ================================
    function testLiquidate_Succeeds() public depositCollateral {
        // record initial user state
        uint256 userInitialCollateralValueInUSD = kUSDEngine.getAccountCollateralValue(USER);
        uint256 kUSDAmount = 10000e18;

        // user mints and we verify health factor sits exactly at the minimum
        vm.prank(USER);
        kUSDEngine.mintKUSD(kUSDAmount);
        uint256 userInitialHealthFactor = kUSDEngine.getHealthFactor(USER);
        assertEq(userInitialHealthFactor, kUSDEngine.getMinimumHealthFactor());

        // drop the price so the user becomes under‑collateralized
        int256 newPrice = 1500e8; // $1,500 per ETH -> 10 ETH = $15,000
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(newPrice);

        // health factor should now be below the minimum
        uint256 userHFAfterDrop = kUSDEngine.getHealthFactor(USER);
        assertLt(userHFAfterDrop, kUSDEngine.getMinimumHealthFactor());

        // prepare the liquidator with enough KUSD to cover the debt
        uint256 liquidatorCollateralAmount = 100 ether;
        vm.startPrank(LIQUIDATOR);
        MockERC20(wETH).approve(address(kUSDEngine), liquidatorCollateralAmount);
        kUSDEngine.depositCollateralAndMintKUSD(wETH, liquidatorCollateralAmount, kUSDAmount);
        uint256 liquidatorBalanceBefore = MockERC20(wETH).balanceOf(LIQUIDATOR);
        uint256 liquidatorInitialHealthFactor = kUSDEngine.getHealthFactor(LIQUIDATOR);

        // perform liquidation
        kUSD.approve(address(kUSDEngine), kUSDAmount);
        kUSDEngine.liquidate(wETH, USER, kUSDAmount);
        uint256 liquidatorBalanceAfter = MockERC20(wETH).balanceOf(LIQUIDATOR);
        uint256 liquidatorCurrentHealthFactor = kUSDEngine.getHealthFactor(LIQUIDATOR);
        vm.stopPrank();

        // check post‑liquidation user state
        uint256 userCurrentHealthFactor = kUSDEngine.getHealthFactor(USER);
        uint256 userCurrentCollateralValueInUSD = kUSDEngine.getAccountCollateralValue(USER);

        assertLt(userCurrentCollateralValueInUSD, userInitialCollateralValueInUSD, "user lost collateral");
        assertGt(userCurrentHealthFactor, userInitialHealthFactor, "health factor improved");
        assertEq(kUSDEngine.getKUSDBalanceOf(USER), 0, "debt should be cleared");

        // verify liquidator benefited and their health factor changed
        assertGt(liquidatorBalanceAfter, liquidatorBalanceBefore, "liquidator received collateral");
        assertEq(liquidatorCurrentHealthFactor, liquidatorInitialHealthFactor, "liquidator HF remains the same '7' ");
        assertEq(kUSDEngine.getKUSDBalanceOf(LIQUIDATOR), kUSDAmount, "liquidator still owe own debt");
    }

    function testLiquidate_RevertsKUSDEngine__HealthFactorAboveMinimum() public depositCollateral mintKUSD {
        uint256 kUSDAmount = 10000e18;
        uint256 liquidatorCollateralAmount = 100 ether;

        vm.startPrank(LIQUIDATOR);
        MockERC20(wETH).approve(address(kUSDEngine), liquidatorCollateralAmount);
        kUSDEngine.depositCollateralAndMintKUSD(wETH, liquidatorCollateralAmount, kUSDAmount);
        kUSD.approve(address(kUSDEngine), kUSDAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IKUSDEngine.KUSDEngine__HealthFactorAboveMinimum.selector, USER, kUSDEngine.getHealthFactor(USER)
            )
        );
        kUSDEngine.liquidate(wETH, USER, kUSDAmount);
        vm.stopPrank();
    }

    function testLiquidate_RevertsKUSDEngine__UserHealthFactorNotImproved() public depositCollateral {
        uint256 kUSDAmount = 10000e18;

        vm.prank(USER);
        kUSDEngine.mintKUSD(kUSDAmount);

        // drop the price so the user becomes under‑collateralized
        int256 newPrice = 1000e8; // $1,000 per ETH -> 10 ETH = $10,000
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(newPrice);
        uint256 userCurrentHealthFactor = kUSDEngine.getHealthFactor(USER);

        assertLt(userCurrentHealthFactor, kUSDEngine.getMinimumHealthFactor());

        uint256 liquidatorCollateralAmount = 100 ether;
        uint256 liquidateAmount = 1e18; // tiny amount that won't improve HF enough

        vm.startPrank(LIQUIDATOR);
        MockERC20(wETH).approve(address(kUSDEngine), liquidatorCollateralAmount);
        kUSDEngine.depositCollateralAndMintKUSD(wETH, liquidatorCollateralAmount, liquidateAmount);
        kUSD.approve(address(kUSDEngine), liquidateAmount);
        vm.stopPrank();

        vm.expectRevert(IKUSDEngine.KUSDEngine__UserHealthFactorNotImproved.selector);
        vm.startPrank(LIQUIDATOR);
        kUSDEngine.liquidate(wETH, USER, liquidateAmount);
        vm.stopPrank();
    }

    function testLiquidate_RevertsKUSDEngine__HealthFactorIsBelowMinimum() public depositCollateral {
        uint256 kUSDAmount = 10000e18;

        vm.prank(USER);
        kUSDEngine.mintKUSD(kUSDAmount);

        vm.startPrank(LIQUIDATOR);
        MockERC20(wETH).approve(address(kUSDEngine), COLLATERAL_AMOUNT);
        kUSDEngine.depositCollateralAndMintKUSD(wETH, COLLATERAL_AMOUNT, kUSDAmount);
        vm.stopPrank();

        uint256 userInitialHealthFactor = kUSDEngine.getHealthFactor(USER);
        assertEq(userInitialHealthFactor, kUSDEngine.getMinimumHealthFactor());

        int256 newPrice = 1500e8;
        MockV3Aggregator(ethUSDPriceFeed).updateAnswer(newPrice);

        uint256 userCurrentHealthFactor = kUSDEngine.getHealthFactor(USER);
        assertLt(userCurrentHealthFactor, kUSDEngine.getMinimumHealthFactor());

        vm.startPrank(LIQUIDATOR);
        kUSD.approve(address(kUSDEngine), kUSDAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKUSDEngine.KUSDEngine__HealthFactorIsBelowMinimum.selector,
                LIQUIDATOR,
                kUSDEngine.getHealthFactor(LIQUIDATOR)
            )
        );
        kUSDEngine.liquidate(wETH, USER, kUSDAmount);
        vm.stopPrank();
    }

    // ======================= Unit Test: External Read Function ===================
    function testGetHealthFactor_Returns() public depositCollateral mintKUSD {
        assertGt(kUSDEngine.getHealthFactor(USER), kUSDEngine.getMinimumHealthFactor());
    }

    // ======================= Unit Test: Public Read Function =====================
    function testGetCollateralUSDValue_Returns() public view {
        uint256 amount = 15e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = kUSDEngine.getCollateralUSDValue(wETH, amount);
        assertEq(actualUSD, expectedUSD);
    }

    function testGetCollateralUSDValue_RevertsKUSDEngine__InvalidOraclePrice() public {
        uint256 amount = 15e18;

        int256 newPrice = -1000e8;
        MockV3Aggregator(btcUSDPriceFeed).updateAnswer(newPrice);

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__InvalidOraclePrice.selector, wBTC));
        kUSDEngine.getCollateralUSDValue(wBTC, amount);
    }

    function testGetCollateralUSDValue_RevertsKUSDEngine__UnsupportedDecimals() public {
        uint256 amount = 15e18;

        uint8 unsafeDecimals = 78;

        int256 btcUSDPrice = 10000;

        // create a feed whose decimals exceed MAX_SAFE_DECIMALS
        MockV3Aggregator badFeed = new MockV3Aggregator(unsafeDecimals, btcUSDPrice);

        collateralAddresses.push(wETH);
        collateralAddresses.push(wBTC);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(address(badFeed));
        KUSDEngine badEngine = new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUSD)));

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__UnsupportedDecimals.selector, wBTC));
        badEngine.getCollateralUSDValue(wBTC, amount);
    }

    function testGetCollateralUSDValue_RevertsOnDecimalsGreaterThan18() public {
        uint256 amount = 15e18;

        uint8 decimals = 19;

        int256 btcUSDPrice = 10000;

        // create a feed whose decimals exceed 18.
        MockV3Aggregator badFeed = new MockV3Aggregator(decimals, btcUSDPrice);

        collateralAddresses.push(wETH);
        collateralAddresses.push(wBTC);
        priceFeedAddresses.push(ethUSDPriceFeed);
        priceFeedAddresses.push(address(badFeed));
        KUSDEngine badEngine = new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kUSD)));

        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__UnsupportedDecimals.selector, wBTC));
        badEngine.getCollateralUSDValue(wBTC, amount);
    }

    function testGetCollateralAmountFromUSD_Returns() public view {
        uint256 usdAmount = 100e18;
        uint256 expectedWETH = 0.05e18;
        uint256 actualWETH = kUSDEngine.getCollateralAmountFromUSD(wETH, usdAmount);
        assertEq(actualWETH, expectedWETH);
    }
}
