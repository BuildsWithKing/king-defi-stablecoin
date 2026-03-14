// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployKUSDEngine} from "script/DeployKUSDEngine.s.sol";
import {KUSDEngine} from "src/KUSDEngine.sol";
import {KingUSD} from "src/token/KingUSD.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@buildswithking-security/tokens/ERC20/interfaces/IERC20.sol";
import {Handler} from "test/invariants/Handler.t.sol";

contract Invariants is StdInvariant, Test {
    DeployKUSDEngine public deployer;
    KUSDEngine public kUsdEngine;
    KingUSD public kUsd;
    HelperConfig public config;
    address public wEth;
    address public wBtc;
    Handler public handler;

    function setUp() public {
        deployer = new DeployKUSDEngine();
        (kUsd, kUsdEngine, config) = deployer.run();
        (wEth, wBtc,,) = config.activeNetworkConfig();
        handler = new Handler(kUsdEngine, kUsd);

        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralThanTotalSupply() public view {
        uint256 totalSupply = kUsd.totalSupply();
        uint256 totalWethDeposited = IERC20(wEth).balanceOf(address(kUsdEngine));
        uint256 totalWbtcDeposited = IERC20(wBtc).balanceOf(address(kUsdEngine));

        uint256 wEthUsdValue = kUsdEngine.getCollateralUsdValue(wEth, totalWethDeposited);
        uint256 wBtcUsdValue = kUsdEngine.getCollateralUsdValue(wBtc, totalWbtcDeposited);

        console.log("wEth value: ", wEthUsdValue);
        console.log("wBtc value: ", wBtcUsdValue);
        console.log("total supply: ", totalSupply);
        console.log("number of times mint was called:", handler.mintCounter());

        assertGe(wEthUsdValue + wBtcUsdValue, totalSupply);
    }

    function invariant_readFunctionShouldAlways_Return() public view {
        kUsdEngine.getLiquidationBonus();
        kUsdEngine.getLiquidationThreshold();
        kUsdEngine.getCollateralAddresses();
        kUsdEngine.getMinimumHealthFactor();
    }
}
