// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";

contract MockV3AggregatorTest is Test {
    MockV3Aggregator internal agg;

    uint8 internal constant DECIMALS = 8;
    int256 internal constant INITIAL_ANSWER = 2000e8;

    function setUp() public {
        vm.warp(123);
        agg = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER);
    }

    function testConstructor_SetsDecimalsAndInitialRoundData() public view {
        assertEq(agg.decimals(), DECIMALS);
        assertEq(agg.latestAnswer(), INITIAL_ANSWER);
        assertEq(agg.latestRound(), 1);
        assertEq(agg.latestTimestamp(), 123);
        assertEq(agg.getAnswer(1), INITIAL_ANSWER);
        assertEq(agg.getTimestamp(1), 123);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            agg.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, INITIAL_ANSWER);
        assertEq(startedAt, 123);
        assertEq(updatedAt, 123);
        assertEq(answeredInRound, 1);
    }

    function testUpdateAnswer_IncrementsRound_AndUpdatesTimestamps() public {
        vm.warp(200);
        int256 newAnswer = 2100e8;

        agg.updateAnswer(newAnswer);

        assertEq(agg.latestRound(), 2);
        assertEq(agg.latestAnswer(), newAnswer);
        assertEq(agg.latestTimestamp(), 200);
        assertEq(agg.getAnswer(2), newAnswer);
        assertEq(agg.getTimestamp(2), 200);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            agg.latestRoundData();
        assertEq(roundId, 2);
        assertEq(answer, newAnswer);
        assertEq(startedAt, 200);
        assertEq(updatedAt, 200);
        assertEq(answeredInRound, 2);
    }

    function testUpdateRoundData_SetsExplicitRoundAndData() public {
        agg.updateRoundData(42, -1, 999, 555);

        assertEq(agg.latestRound(), 42);
        assertEq(agg.latestAnswer(), -1);
        assertEq(agg.latestTimestamp(), 999);
        assertEq(agg.getAnswer(42), -1);
        assertEq(agg.getTimestamp(42), 999);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            agg.latestRoundData();
        assertEq(roundId, 42);
        assertEq(answer, -1);
        assertEq(startedAt, 555);
        assertEq(updatedAt, 999);
        assertEq(answeredInRound, 42);
    }

    function testGetRoundData_ReturnsRequestedRound() public {
        agg.updateRoundData(7, 123, 10, 5);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            agg.getRoundData(7);
        assertEq(roundId, 7);
        assertEq(answer, 123);
        assertEq(startedAt, 5);
        assertEq(updatedAt, 10);
        assertEq(answeredInRound, 7);
    }

    function testDescription_ReturnsExpectedValue() public view {
        assertEq(agg.description(), "v0.6/tests/MockV3Aggregator.sol");
    }
}
