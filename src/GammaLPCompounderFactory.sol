// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {GammaLPCompounder} from "./GammaLPCompounder.sol";
import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";

contract GammaLPCompounderFactory {
    event NewGammaLPCompounder(address indexed strategy, address indexed asset);

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

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
     * @dev This will set the msg.sender to all of the permissioned roles.
     * @param _asset The underlying asset for the lender to use.
     * @param _name The name for the lender to use.
     * @return . The address of the new lender.
     */
    function newGammaLPCompounder(
        address _asset,
        uint256 _PID,
        address _NATIVE,
        string memory _name
    ) external returns (address) {
        // We need to use the custom interface with the
        // tokenized strategies available setters.
        IStrategyInterface newStrategy = IStrategyInterface(address(new GammaLPCompounder(_asset, _PID, _NATIVE, _name)));

        newStrategy.setPerformanceFeeRecipient(performanceFeeRecipient);

        newStrategy.setKeeper(keeper);

        newStrategy.setPendingManagement(management);

        emit NewGammaLPCompounder(address(newStrategy), _asset);
        return address(newStrategy);
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
