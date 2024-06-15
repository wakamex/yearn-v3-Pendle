// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface AggregatorInterface {
    function latestAnswer() external view returns (int256);

    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
