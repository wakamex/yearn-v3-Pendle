// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IStrategyFactoryInterface {
    function newSingleSidedPT(address _asset, address _market, address _redeemToken, uint24 _feeRedeemTokenToBase, address _base, uint24 _feeBaseToAsset, string memory _name) external returns (address);

    function management() external view returns (address);

    function performanceFeeRecipient() external view returns (address);

    function keeper() external view returns (address);
}
