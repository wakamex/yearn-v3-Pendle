// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IStrategyFactoryInterface {
    function newSingleSidedPTcore(address _asset, address _market, string memory _name) external returns (address);

    function management() external view returns (address);

    function performanceFeeRecipient() external view returns (address);

    function keeper() external view returns (address);
}
