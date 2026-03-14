// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract HelperConfigTest is Test {
    uint256 internal constant ANVIL_CHAIN_ID = 31337;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;

    function testConstructor_UsesSepoliaConfig_WhenOnSepolia() public {
        vm.chainId(SEPOLIA_CHAIN_ID);
        HelperConfig config = new HelperConfig();

        (address wEth, address wBtc, address wEthUsdPriceFeed, address wBtcUsdPriceFeed) = config.activeNetworkConfig();

        assertEq(wEth, 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14);
        assertEq(wBtc, 0xdE43B354d506Ce213C4bE70B750b5c6AcC09D7CA);
        assertEq(wEthUsdPriceFeed, 0x694AA1769357215DE4FAC081bf1f309aDC325306);
        assertEq(wBtcUsdPriceFeed, 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43);
    }

    function testConstructor_UsesAnvilConfig_WhenNotOnSepolia() public {
        vm.chainId(ANVIL_CHAIN_ID);
        HelperConfig config = new HelperConfig();

        (address wEth, address wBtc, address wEthUsdPriceFeed, address wBtcUsdPriceFeed) = config.activeNetworkConfig();

        assertTrue(wEth != address(0));
        assertTrue(wBtc != address(0));
        assertTrue(wEthUsdPriceFeed != address(0));
        assertTrue(wBtcUsdPriceFeed != address(0));

        assertGt(wEth.code.length, 0);
        assertGt(wBtc.code.length, 0);
        assertGt(wEthUsdPriceFeed.code.length, 0);
        assertGt(wBtcUsdPriceFeed.code.length, 0);

        assertEq(MockV3Aggregator(wEthUsdPriceFeed).decimals(), config.DECIMALS());
        assertEq(MockV3Aggregator(wEthUsdPriceFeed).latestAnswer(), config.ETH_USD_PRICE());

        assertEq(MockV3Aggregator(wBtcUsdPriceFeed).decimals(), config.DECIMALS());
        assertEq(MockV3Aggregator(wBtcUsdPriceFeed).latestAnswer(), config.BTC_USD_PRICE());

        assertEq(MockERC20(wEth).balanceOf(address(this)), 0);
    }

    function testGetOrCreateAnvilEthConfig_ReturnsActiveConfig_WhenAlreadySet() public {
        vm.chainId(ANVIL_CHAIN_ID);
        HelperConfig config = new HelperConfig();

        (address wEth, address wBtc, address wEthUsdPriceFeed, address wBtcUsdPriceFeed) = config.activeNetworkConfig();
        HelperConfig.NetworkConfig memory cfg = config.getOrCreateAnvilEthConfig();

        assertEq(cfg.wEth, wEth);
        assertEq(cfg.wBtc, wBtc);
        assertEq(cfg.wEthUsdPriceFeed, wEthUsdPriceFeed);
        assertEq(cfg.wBtcUsdPriceFeed, wBtcUsdPriceFeed);
    }
}
