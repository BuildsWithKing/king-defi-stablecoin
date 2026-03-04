// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployKUSDEngine} from "script/DeployKUSDEngine.s.sol";
import {KUSDEngine} from "src/KUSDEngine.sol";
import {IKUSDEngine} from "src/interfaces/IKUSDEngine.sol";
import {KingUSD} from "src/token/KingUSD.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract KUSDEngineTest is Test {
    DeployKUSDEngine public deployer;
    KUSDEngine public kUSDEngine;
    KingUSD public kingUSD;
    HelperConfig public config;

    address public wETH;
    address public wBTC;
    address public wETHUSDPriceFeed;
    address public wBTCUSDPriceFeed;

    address public USER = makeAddr("USER");
    uint256 public constant COLLATERAL_AMOUNT = 10e18;
    uint256 public constant STARTING_ERC20_BALANCE = 10e18;

    // ================================== SetUp Function ===========================
    function setUp() public {
        deployer = new DeployKUSDEngine();
        (kingUSD, kUSDEngine, config) = deployer.run();
        (wETH, wBTC, wETHUSDPriceFeed, wBTCUSDPriceFeed) = config.activeNetworkConfig();

        MockERC20(wETH).mint(USER, STARTING_ERC20_BALANCE);
    }

    // ================================= Unit Test: External Write Functions =========
    function testDepositCollateral_Succeeds() public {}

    function testDepositCollateral_RevertsKUSDEngine__AmountMustBeGreaterThanZero() public {
        vm.expectRevert(IKUSDEngine.KUSDEngine__AmountMustBeGreaterThanZero.selector);
        vm.prank(USER);
        kUSDEngine.depositCollateral(wETH, 0);
    }

    function testMintKUSD_RevertsKUSDEngine__HealthFactorIsBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IKUSDEngine.KUSDEngine__HealthFactorIsBelowMinimum.selector, 0));
        vm.prank(USER);
        kUSDEngine.mintKUSD(1e18);
    }
    // ======================= Unit Test: Public Read Function =====================

    function testGetCollateralUSDValue_Returns() public view {
        uint256 amount = 15e18;
        uint256 expectedUSD = 30000e18;
        uint256 actualUSD = kUSDEngine.getCollateralUSDValue(wETH, amount);

        assertEq(actualUSD, expectedUSD);
    }
}
