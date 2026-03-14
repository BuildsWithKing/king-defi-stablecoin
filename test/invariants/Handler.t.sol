// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {KUSDEngine} from "src/KUSDEngine.sol";
import {KingUSD} from "src/token/KingUSD.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract Handler is Test {
    KUSDEngine public kUsdEngine;
    KingUSD public kUsd;

    MockERC20 public wEth;
    MockERC20 public wBtc;
    MockV3Aggregator public ethUsdPriceFeed;

    uint256 public mintCounter;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    mapping(address user => bool) private hasDeposited;

    constructor(KUSDEngine _kUsdEngine, KingUSD _kUsd) {
        kUsdEngine = _kUsdEngine;
        kUsd = _kUsd;

        address[] memory collateralAddresses = kUsdEngine.getCollateralAddresses();
        wEth = MockERC20(collateralAddresses[0]);
        wBtc = MockERC20(collateralAddresses[1]);

        ethUsdPriceFeed = MockV3Aggregator(kUsdEngine.getCollateralPriceFeedAddress(address(wEth)));
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        MockERC20 collateral = _getCollateralFromSeed(collateralSeed);
        amount = bound(amount, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amount);
        collateral.approve(address(kUsdEngine), amount);
        kUsdEngine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        if (hasDeposited[msg.sender] == true) {
            return;
        }
        hasDeposited[msg.sender] = true;
    }

    function mintKusd(uint256 amount) public {
        if (!hasDeposited[msg.sender]) {
            return;
        }

        (uint256 totalKusdMinted, uint256 collateralValueInUsd) = kUsdEngine.getAccountInformation(msg.sender);

        uint256 maxKusdToMint = collateralValueInUsd / 2;
        if (totalKusdMinted >= maxKusdToMint) {
            return;
        }

        maxKusdToMint -= totalKusdMinted;

        amount = bound(amount, 1, uint256(maxKusdToMint));

        vm.prank(msg.sender);
        kUsdEngine.mintKusd(amount);
        mintCounter++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        if (!hasDeposited[msg.sender]) {
            return;
        }

        MockERC20 collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateral = kUsdEngine.getCollateralBalanceOf(msg.sender, address(collateral));

        (uint256 totalKusdMinted, uint256 collateralValueInUsd) = kUsdEngine.getAccountInformation(msg.sender);

        // Calculate maximum redeemable while maintaining health factor
        if (totalKusdMinted > 0) {
            uint256 minCollateralValueNeeded = (totalKusdMinted * 2); // 200% collateralization

            if (collateralValueInUsd <= minCollateralValueNeeded) {
                return; // Already at minimum collateral
            }

            uint256 maxValueToRedeem = collateralValueInUsd - minCollateralValueNeeded;

            // Convert USD value to token amount
            uint256 collateralPriceInUsd = kUsdEngine.getCollateralUsdValue(address(collateral), 1e18);
            uint256 maxTokensToRedeem = (maxValueToRedeem * 1e18) / collateralPriceInUsd;

            // Take minimum of user's balance and health-factor-constrained amount
            maxCollateral = maxCollateral < maxTokensToRedeem ? maxCollateral : maxTokensToRedeem;
        }

        amount = bound(amount, 0, maxCollateral);
        if (amount == 0) {
            return;
        }

        vm.prank(msg.sender);
        kUsdEngine.redeemCollateral(address(collateral), amount);
    }

    function updateCollateralPrice(uint96 newPrice) public {
        if (newPrice == 0) {
            return;
        }

        int256 thousandDollar = 1000e8;
        int256 tenThousandDollar = 10000e8;

        int256 newPriceInt = int256(uint256(newPrice));

        // Constrain to realistic ETH price range ($1000 - $10000)
        newPriceInt = bound(newPriceInt, thousandDollar, tenThousandDollar);

        ethUsdPriceFeed.updateAnswer(newPriceInt);
    }

    // ========================= Private Helper Functions ======================
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (MockERC20) {
        if (collateralSeed % 2 == 0) {
            return wEth;
        } else {
            return wBtc;
        }
    }
}
