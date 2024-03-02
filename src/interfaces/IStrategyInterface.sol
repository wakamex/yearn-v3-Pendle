// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {

    function reportTrigger(
        address _strategy
    ) external view returns (bool, bytes memory);

    function sweep(address _token) external;

    function balanceAsset() external view returns (uint256);
    function balanceStaked() external view returns (uint256);

    function addReward(address _rewardToken, uint24 _feeRewardTokenToBase) external;
    function setProfitLimitRatio(uint256) external;
    function setAutocompound(bool) external;
}
