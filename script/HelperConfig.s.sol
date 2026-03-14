// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wEth;
        address wBtc;
        address wEthUsdPriceFeed;
        address wBtcUsdPriceFeed;
    }

    NetworkConfig public activeNetworkConfig;

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 65000e8;
    uint256 public constant INITIAL_SUPPLY = 10000e18;

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;

    constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory sepoliaEthConfig) {
        return sepoliaEthConfig = NetworkConfig({
            wEth: 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            wBtc: 0xdE43B354d506Ce213C4bE70B750b5c6AcC09D7CA,
            wEthUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wBtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilEthConfig) {
        if (activeNetworkConfig.wEthUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wEthUsdpriceFeedMock = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator wBtcUsdPriceFeedMock = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        MockERC20 wEthMock = new MockERC20("Wrapped ETH", "WETH", INITIAL_SUPPLY);
        MockERC20 wBtcMock = new MockERC20("Wrapped BTC", "WBTC", INITIAL_SUPPLY);

        vm.stopBroadcast();

        return anvilEthConfig = NetworkConfig({
            wEth: address(wEthMock),
            wBtc: address(wBtcMock),
            wEthUsdPriceFeed: address(wEthUsdpriceFeedMock),
            wBtcUsdPriceFeed: address(wBtcUsdPriceFeedMock)
        });
    }
}
