// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Import Script from forge standard library and KingUSD contract from src.
import {Script} from "forge-std/Script.sol";
import {KingUSD} from "src/token/KingUSD.sol";

contract DeployKingUSD is Script {
    function run() external returns (KingUSD) {
        vm.startBroadcast();
        KingUSD kingUSD = new KingUSD(msg.sender);
        vm.stopBroadcast();
        return kingUSD;
    }
}
