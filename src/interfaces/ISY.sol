// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface ISY {
     function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut) external payable returns (uint256 amountSharesOut);
    function getTokensIn() external view returns (address[] calldata);
}