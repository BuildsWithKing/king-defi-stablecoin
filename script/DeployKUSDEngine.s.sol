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

        (address wETH, address wBTC, address wETHUSDPriceFeed, address wBTCUSDPriceFeed) = config.activeNetworkConfig();

        collateralAddresses = [wETH, wBTC];
        priceFeedAddresses = [wETHUSDPriceFeed, wBTCUSDPriceFeed];

        vm.startBroadcast(msg.sender);
        KingUSD kingUSD = new KingUSD(msg.sender);
        KUSDEngine kUSDEngine = new KUSDEngine(collateralAddresses, priceFeedAddresses, payable(address(kingUSD)));
        kingUSD.transferKingshipTo(address(kUSDEngine));
        vm.stopBroadcast();

        return (kingUSD, kUSDEngine, config);
    }
}
