// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface ILP {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);
    function deposit0Max() external view returns (uint256);
    function deposit1Max() external view returns (uint256);
}