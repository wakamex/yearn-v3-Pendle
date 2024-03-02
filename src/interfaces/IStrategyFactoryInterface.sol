// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IStrategyFactoryInterface {
    function newPendleLPCompounder(
        address _asset,
        address _pendleStaking, 
        address _PENDLE, 
        uint24 _feePENDLEtoBase, 
        address _base, 
        uint24 _feeBaseToTargetToken, 
        address _targetToken, 
        address _GOV, 
        string memory _name
    ) external returns (address);

    function management() external view returns (address);

    function performanceFeeRecipient() external view returns (address);

    function keeper() external view returns (address);
}
