// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IKUSDEngine - The interface of KUSDEngine.
 *     @author Michealking(@BuildsWithKing)
 *  @dev This interface lists all the functions available on KUSDEngine.
 */
interface IKUSDEngine {
    function depositCollateralAndMintKUSD() external;

    function depositCollateral() external;

    function redeemCollateralForKUSD() external;

    function redeemCollateral() external;

    function mintKUSD() external;

    function burnKUSD() external;

    function liquidate() external;

    function getHealthFactor() external view;
}
