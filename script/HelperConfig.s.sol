// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wETH;
        address wBTC;
        address wETHUSDPriceFeed;
        address wBTCUSDPriceFeed;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 65000e8;
    uint256 public constant INITIAL_SUPPLY = 10000e18;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaETHConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilETHConfig();
        }
    }

    function getSepoliaETHConfig() public pure returns (NetworkConfig memory sepoliaETHConfig) {
        return sepoliaETHConfig = NetworkConfig({
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wETHUSDPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBTCUSDPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
        });
    }

    function getOrCreateAnvilETHConfig() public returns (NetworkConfig memory anvilETHConfig) {
        if (activeNetworkConfig.wETHUSDPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wETHUSDpriceFeedMock = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator wBTCUSDPriceFeedMock = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        MockERC20 wETHMock = new MockERC20("Wrapped ETH", "WETH", INITIAL_SUPPLY);
        MockERC20 wBTCMock = new MockERC20("Wrapped BTC", "WBTC", INITIAL_SUPPLY);

        vm.stopBroadcast();

        return anvilETHConfig = NetworkConfig({
            wETH: address(wETHMock),
            wBTC: address(wBTCMock),
            wETHUSDPriceFeed: address(wETHUSDpriceFeedMock),
            wBTCUSDPriceFeed: address(wBTCUSDPriceFeedMock)
        });
    }
}
