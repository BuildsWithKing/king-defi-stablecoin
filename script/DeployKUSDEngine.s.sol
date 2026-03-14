// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {KingUSD} from "src/token/KingUSD.sol";
import {KUSDEngine} from "src/KUSDEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployKUSDEngine is Script {
    address[] public collateralAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (KingUSD, KUSDEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address wEth, address wBtc, address wEthUsdPriceFeed, address wBtcUsdPriceFeed) = config.activeNetworkConfig();

        collateralAddresses = [wEth, wBtc];
        priceFeedAddresses = [wEthUsdPriceFeed, wBtcUsdPriceFeed];

        vm.startBroadcast(0x63c013128BF5C7628Fc8B87b68Aa90442AF312aa);
        KingUSD kingUsd = new KingUSD(0x63c013128BF5C7628Fc8B87b68Aa90442AF312aa);
        KUSDEngine kUsdEngine = new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kingUsd)));
        kingUsd.transferKingshipTo(address(kUsdEngine));
        vm.stopBroadcast();

        return (kingUsd, kUsdEngine, config);
    }
}
