// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.18;

interface IDQUICK {
    function leave(uint256 amount) external; 
    function dQuickForQuick(uint256 amount) external view returns (uint256);
}