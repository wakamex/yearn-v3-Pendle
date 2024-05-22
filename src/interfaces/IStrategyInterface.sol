// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {

    function reportTrigger(
        address _strategy
    ) external view returns (bool, bytes memory);

    function sweep(address _token) external;

    function balanceAsset() external view returns (uint256);
    function balancePT() external view returns (uint256);

    function setProfitLimitRatio(uint256) external;
    function setLossLimitRatio(uint256) external;
    function setDoHealthCheck(bool) external;
    function setRouterParams(uint256 _guessMin, uint256 _guessMax, uint256 _maxIteration, uint256 _eps) external;

    function isExpired() external view returns (bool);
    function setMaxSingleTrade(uint256) external;
    function setMaxSingleWithdraw(uint256) external;
    function setDepositLimit(uint256) external;
    function setDepositTrigger(uint256) external;
    function market() external view returns (address);
    function setSwapSlippageBPS(uint256) external;
    function setOracleDuration(uint32) external;
    function setChainlinkOracle(address _chainlinkOracle, uint256 _chainlinkHeartbeat) external;
    function rolloverMaturity(address market, uint256 _slippageBPS) external;
    function PT() external view returns (address);
    function SY() external view returns (address);
    function YT() external view returns (address);
}