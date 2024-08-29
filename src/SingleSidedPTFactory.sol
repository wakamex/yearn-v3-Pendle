// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {SingleSidedPTcore} from "./SingleSidedPT.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract SingleSidedPTcoreFactory {
    event NewSingleSidedPTcore(address indexed strategy, address indexed asset);

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    address public immutable oracle;
    address public immutable emergencyAdmin;
    address public immutable GOV;

    mapping(address => address) public assetToStrategy;

    constructor(
        address _management,
        address _peformanceFeeRecipient,
        address _keeper,
        address _oracle,
        address _emergencyAdmin,
        address _GOV
    ) {
        management = _management;
        performanceFeeRecipient = _peformanceFeeRecipient;
        keeper = _keeper;
        oracle = _oracle;
        emergencyAdmin = _emergencyAdmin;
        GOV = _GOV;
    }

    modifier onlyManagement() {
        require(msg.sender == management, "!management");
        _;
    }

    /**
     * @notice Deploy a new Single Sided Pendle PT Core Strategy.
     * @return . The address of the new strategy.
     */
    function newSingleSidedPTcore(
        address _asset,
        address _market,
        string memory _name
    ) external onlyManagement returns (address) {
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new SingleSidedPTcore(_asset, _market, oracle, GOV, _name))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        newStrategy.setEmergencyAdmin(emergencyAdmin);

        emit NewSingleSidedPTcore(address(newStrategy), _asset);

        assetToStrategy[_asset] = address(newStrategy);

        return address(newStrategy);
    }

    /**
     * @notice Deploy a new Single Sided Pendle PT Strategy.
     * @return . The address of the new strategy.
     */
    function newSingleSidedPTcore(
        address _asset,
        address _market,
        uint128 _minAssetAmountToPT,
        uint128 _maxSingleTrade,
        uint256 _depositLimit,
        uint128 _depositTrigger,
        uint48 _maxTendBaseFee,
        uint40 _minDepositInterval,
        string memory _name
    ) external onlyManagement returns (address) {
        IStrategyInterface newStrategy = IStrategyInterface(
            address(new SingleSidedPTcore(_asset, _market, oracle, GOV, _name))
        );

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        newStrategy.setEmergencyAdmin(emergencyAdmin);

        newStrategy.setTendTriggerParams(
            _depositTrigger,
            _maxTendBaseFee,
            _minDepositInterval
        );

        newStrategy.setTradeParams(_minAssetAmountToPT, _maxSingleTrade);

        if (_depositLimit != type(uint256).max) {
            newStrategy.setDepositLimit(_depositLimit);
        }

        emit NewSingleSidedPTcore(address(newStrategy), _asset);

        assetToStrategy[_asset] = address(newStrategy);

        return address(newStrategy);
    }

    /**
     * @notice Retrieve the address of a strategy by asset address
     * @param _asset asset address
     * @return strategy address
     */
    function getStrategyByAsset(
        address _asset
    ) external view returns (address) {
        return assetToStrategy[_asset];
    }

    /**
     * @notice Check if a strategy has been deployed by this Factory
     * @param _strategy strategy address
     */
    function isDeployedStrategy(
        address _strategy
    ) external view returns (bool) {
        address _asset = IStrategyInterface(_strategy).asset();
        return assetToStrategy[_asset] == _strategy;
    }

    function setStrategyByAsset(
        address _asset,
        address _strategy
    ) external onlyManagement {
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
