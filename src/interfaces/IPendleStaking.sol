// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IPendleStaking {
    function masterPenpie() external view returns (address);
    function marketDepositHelper() external view returns (address);
}

interface IMarketDepositHelper {
    function depositMarket(address market, uint256 amount) external;
    function withdrawMarket(address market, uint256 amount) external;
    function withdrawMarketWithClaim(address market, uint256 amount, bool doClaim) external;
    function balance(address market, address user) external view returns (uint256);
}