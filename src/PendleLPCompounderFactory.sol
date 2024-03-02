// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {PendleLPCompounder} from "./PendleLPCompounder.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract PendleLPCompounderFactory {
    event NewPendleLPCompounder(address indexed strategy, address indexed asset);

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    mapping(address => address) public assetToStrategy;

    constructor(
        address _management,
        address _peformanceFeeRecipient,
        address _keeper
    ) {
        management = _management;
        performanceFeeRecipient = _peformanceFeeRecipient;
        keeper = _keeper;
    }

    modifier onlyManagement() {
        require(msg.sender == management, "!management");
        _;
    }

    /**
     * @notice Deploy a new Gamma Stable LP Compounder Strategy.
     * @return . The address of the new lender.
     */
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
    ) external onlyManagement returns (address) {

        IStrategyInterface newStrategy = IStrategyInterface(address(new PendleLPCompounder(_asset, _pendleStaking, _PENDLE, _feePENDLEtoBase, _base, _feeBaseToTargetToken, _targetToken, _GOV, _name)));

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        emit NewPendleLPCompounder(address(newStrategy), _asset);

        assetToStrategy[_asset] = address(newStrategy);

        return address(newStrategy);
    }

    /**
     * @notice Retrieve the address of a strategy by LP address
     * @param _asset LP address
     * @return strategy address
     */
    function getStrategyByAsset(address _asset) external view returns (address) {
        return assetToStrategy[_asset];
    }

    /**
     * @notice Check if a strategy has been deployed by this Factory
     * @param _strategy strategy address
     */
    function isDeployedStrategy(address _strategy) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return assetToStrategy[_asset] == _strategy;
    }


    function setStrategyByAsset(address _asset, address _strategy) external onlyManagement {
        assetToStrategy[_asset] = _strategy;
    }

    /**
     * @notice Set the management address.
     * @dev This is the address that can call the management functions.
     * @param _management The address to set as the management address.
     */
    function setManagement(address _management) external onlyManagement {
        require(_management != address(0), "ZERO_ADDRESS");
        management = _management;
    }

    /**
     * @notice Set the performance fee recipient address.
     * @dev This is the address that will receive the performance fee.
     * @param _performanceFeeRecipient The address to set as the performance fee recipient address.
     */
    function setPerformanceFeeRecipient(
        address _performanceFeeRecipient
    ) external onlyManagement {
        require(_performanceFeeRecipient != address(0), "ZERO_ADDRESS");
        performanceFeeRecipient = _performanceFeeRecipient;
    }

    /**
     * @notice Set the keeper address.
     * @dev This is the address that will be able to call the keeper functions.
     * @param _keeper The address to set as the keeper address.
     */
    function setKeeper(address _keeper) external onlyManagement {
        keeper = _keeper;
    }
}
