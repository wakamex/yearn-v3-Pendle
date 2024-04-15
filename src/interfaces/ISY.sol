// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface ISY {
    function deposit(
        address receiver,
        address tokenIn,
        uint256 amountTokenToDeposit,
        uint256 minSharesOut) external payable returns (uint256 amountSharesOut);
    
 
    function getTokensIn() external view returns (address[] calldata);
    function redeem(
        address receiver,
        uint256 amountSharesToRedeem,
        address tokenOut,
        uint256 minTokenOut,
        bool burnFromInternalBalance) external payable returns (uint256 amountTokenOut);
    function isValidTokenIn(address) external view returns (bool);
    function isValidTokenOut(address) external view returns (bool);
    function previewRedeem(address tokenOut, uint256 amountSharesToRedeem) external view returns (uint256 amountTokenOut);
    function previewDeposit(address tokenIn, uint256 amountTokenInToDeposit) external view returns (uint256 amountSharesOut);
}