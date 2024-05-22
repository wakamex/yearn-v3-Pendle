// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IPendleMarket {
    function readTokens() external view returns (address _SY, address _PT, address _YT);
    function isExpired() external view returns (bool);
}