// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.18;

interface IPendleOracle {
    function getPtToSyRate(address market, uint32 oracleDuration) external view returns (uint256 rate);
    function getPtToAssetRate(address market, uint32 oracleDuration) external view returns (uint256 rate);
}