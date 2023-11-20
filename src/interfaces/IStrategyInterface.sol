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
    function balanceDQUICK() external view returns (uint256);
    function balanceQUICK() external view returns (uint256);
    function balanceNATIVE() external view returns (uint256);

    function addReward(address _rewardToken) external;
    function setMidRouteRewardToNative(address _rewardToken, address[] calldata _tokensMidRouteRewardToNative) external;
    function setMidRouteNativeToToken0(address[] calldata _tokensMidRouteNativeToToken0) external;
    function setMidRouteNativeToToken1(address[] calldata _tokensMidRouteNativeToToken1) external;

}
