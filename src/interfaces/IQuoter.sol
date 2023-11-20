// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IQuoter {
    function quoteExactInput(bytes memory path, uint amountIn) external returns (uint amountOut, uint16[] memory fees);
}