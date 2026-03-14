// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Michealking (@BuildsWithKing)
 * @notice This library is used to check the chainlink Oracle for stale data.
 * @dev Whenever a price is stale, function reverts and makes KusdEngine unusable. KusdEngine freezes once price get stale.
 */
library OracleLib {
    error OracleLib__StalePrice();

    /// @notice maximum hours required, before
    uint256 private constant TIMEOUT = 3 hours;

    /**
     * @notice Check if price is stale.
     * @param priceFeed The price feed's address.
     * @return The price feed's latest round data.
     */
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 lastUpdatedAt = block.timestamp - updatedAt;

        // Revert if the last updated time is greater than 3 hours.
        if (lastUpdatedAt > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
