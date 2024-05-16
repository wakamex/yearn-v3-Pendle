// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPendleMarket} from "./interfaces/IPendleMarket.sol";
import {ISY} from "./interfaces/ISY.sol";
import {IPendleRouter} from "./interfaces/IPendleRouter.sol";
import {IPendleOracle} from "./interfaces/IPendleOracle.sol";

/// @title yearn-v3-SingleSidedPTcore
/// @author mil0x
/// @notice yearn-v3 Strategy that invests into Pendle PT positions.
contract SingleSidedPTcore is BaseHealthCheck {
    using SafeERC20 for ERC20;

    address public market;
    address public immutable SY;
    address public PT;
    address internal YT;

    address internal immutable oracle;
    uint32 public oracleDuration;

    address internal constant pendleRouter = 0x888888888889758F76e7103c6CbF23ABbF58F946;
    IPendleRouter.ApproxParams public routerParams;

    address public immutable GOV; //yearn governance
    uint256 private constant WAD = 1e18;

    uint256 public minAssetAmountToPT;
    // The max in asset we will deposit or withdraw at a time.
    uint256 public maxSingleTrade;
    // The total deposit limit for the strategy.
    uint256 public depositLimit = type(uint256).max;
    // The amount in asset that will trigger a tend if idle.
    uint256 public depositTrigger;
    // The max amount the base fee can be for a tend to happen.
    uint256 public maxTendBasefee;
    // Minimum time between deposits to wait.
    uint256 public minDepositInterval;
    // Time stamp of the last deployment of funds.
    uint256 public lastDeposit;
    // Amount in Basis Points to allow for slippage when reporting.
    uint256 public swapSlippageBPS;
    // Amount in Basis Points to account for as buffer when reporting. Can also manually account for bigger depeg scenarios.
    uint256 public bufferSlippageBPS;
    
    // Bool if the strategy is open for any depositors. Default = true.
    bool public open = true;

    // Mapping of addresses allowed to deposit.
    mapping(address => bool) public allowed;

    constructor(address _asset, address _market, address _oracle, address _GOV, string memory _name) BaseHealthCheck(_asset, _name) {
        market = _market;
        require(!_isExpired(), "expired");

        //Default oracle duration to 15 minutes price smoothing recommendation by Pendle Finance
        oracleDuration = 900;
        //Default maxSingleTrade to 501 ETH as a majority of markets are ETH based. Change this for non-ETH.
        maxSingleTrade = 501e18;
        // Default the deposit trigger to 5 ETH. Change this for non-ETH.
        depositTrigger = 5e18;
        // Default max tend fee to 100 gwei.
        maxTendBasefee = 100e9;
        // Default min deposit interval to 12 hours.
        minDepositInterval = 60 * 60 * 12;
        // Default slippage to 1%.
        swapSlippageBPS = 100;
        bufferSlippageBPS = 50;
        
        (SY, PT, YT) = IPendleMarket(_market).readTokens();        
        
        require(ISY(SY).isValidTokenOut(_asset), "!valid out");  
        require(ISY(SY).isValidTokenIn(_asset), "!valid in");

        oracle = _oracle;
        GOV = _GOV;

        routerParams.guessMin = 0;
        routerParams.guessMax = type(uint256).max;
        routerParams.guessOffchain = 0; // strictly 0
        routerParams.maxIteration = 256;
        routerParams.eps = 1e15; // max 0.1% unused

        // Allow for 1% loss.
        _setLossLimitRatio(1_00);
        // Allow a 500% gain.
        _setProfitLimitRatio(500_00);
        
        //approvals:
        ERC20(_asset).forceApprove(SY, type(uint).max);
        ERC20(SY).forceApprove(pendleRouter, type(uint).max);
        ERC20(PT).forceApprove(pendleRouter, type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {
        //do nothing, we want to only have the keeper swap funds
    }

    function _invest(uint256 _amount) internal {
        //asset --> SY
        uint256 currentBalance = _amount;
        ISY(SY).deposit(address(this), address(asset), currentBalance, 0);
        currentBalance = ERC20(SY).balanceOf(address(this));

        //SY --> PT
        IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address
        (currentBalance, ) = IPendleRouter(pendleRouter).swapExactSyForPt(address(this), market, currentBalance, 0, routerParams, limit);
        //here we check minAmountOut versus initial asset amount
        require(_PTtoAsset(currentBalance) > _amount * (MAX_BPS - swapSlippageBPS) / MAX_BPS, "too little PT out");

        // Update the last time that we deposited.
        lastDeposit = block.timestamp;
    }

    function _freeFunds(uint256 _amount) internal override {
        //Redeem PT shares proportional to the SSPT shares redeemed:
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        uint256 totalDebt = totalAssets - _balanceAsset();
        uint256 PTtoUninvest = _balancePT() * _amount / totalDebt;
        _uninvest(PTtoUninvest);
    }

    function _uninvest(uint256 currentBalance) internal returns (uint256) {
        if (currentBalance == 0) return 0;
        //PT --> SY
        if (_isExpired()) { //if expired, redeem PY to SY
            currentBalance = IPendleRouter(pendleRouter).redeemPyToSy(address(this), YT, currentBalance, 0);
        } else {
            IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address
            // We don't enforce any min amount out since withdrawer's can use 'maxLoss'
            (currentBalance, ) = IPendleRouter(pendleRouter).swapExactPtForSy(address(this), market, currentBalance, 0, limit);
            if (currentBalance == 0) return 0;
        }
        //SY --> asset
        // We don't enforce any min amount out since withdrawers can use 'maxLoss'
        return ISY(SY).redeem(address(this), currentBalance, address(asset), 0, false);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (!_isExpired() && !TokenizedStrategy.isShutdown()) {
            uint256 assetBalance = _balanceAsset();
            if (assetBalance > minAssetAmountToPT) {
                _invest(_min(assetBalance, maxSingleTrade));
            }
        }

        _totalAssets = _balanceAsset() + _PTtoAsset(_balancePT()) * (MAX_BPS - bufferSlippageBPS) / MAX_BPS; //reduce PT balance by bufferSlippageBPS to account for the fact that it will need to be swapped back to asset
    }

    function _PTtoAsset(uint256 _amount) internal view returns (uint256) {
        //PT --> SY
        uint256 rate = IPendleOracle(oracle).getPtToSyRate(market, oracleDuration);
        _amount = _amount * rate / WAD;
        //SY --> asset
        return ISY(SY).previewRedeem(address(asset), _amount);
    }

    function _tend(uint256) internal override {
        uint256 assetBalance = _balanceAsset();
        if (assetBalance > minAssetAmountToPT) {
            _invest(_min(assetBalance, maxSingleTrade));
        }
    }

    function _tendTrigger() internal view override returns (bool _shouldTend) {
        if (!_isExpired() && block.timestamp - lastDeposit > minDepositInterval && _balanceAsset() > depositTrigger) {
            _shouldTend = block.basefee < maxTendBasefee;
        }
    }
    
    function availableDepositLimit(address _owner) public view override returns (uint256) {
        // If the owner is whitelisted or the strategy is open.
        if (allowed[_owner] || open) {
            uint256 totalDeposits = TokenizedStrategy.totalAssets();
            if (depositLimit > totalDeposits) {
                return depositLimit - totalDeposits;
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return _balanceAsset() + maxSingleTrade;
    }

    function _balanceAsset() internal view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _balancePT() internal view returns (uint256) {
        return ERC20(PT).balanceOf(address(this));
    }

    function _isExpired() internal view returns (bool) {
        return IPendleMarket(market).isExpired();
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }

    function balancePT() external view returns (uint256) {
        return _balancePT();
    }

    function isExpired() external view returns (bool) {
        return _isExpired();
    }

    /**
     * @notice Set the routerParams for the pendleRouter. Pendle's AMM only supports the built-in swapSyForExactPt. To execute a swapExactSyForPt, the router will conduct a binary search to determine the amount of PT to swap.
     * @param _guessMin The minimum value for binary search. Default: 0.
     * @param _guessMax The maximum value for binary search. Default: type(uint256).max.
     * @param _maxIteration The maximum number of times binary search will be performed. Default: 256.
     * @param _eps The precision of binary search - the maximum proportion of the input that can be unused. Default: 1e15 == max 0.1% unused. Alternatively: 1e14 implies that no more than 0.01% unused.     
     */
    function setRouterParams(uint256 _guessMin, uint256 _guessMax, uint256 _maxIteration, uint256 _eps) external onlyManagement {
        routerParams.guessMin = _guessMin; // default: 0
        routerParams.guessMax = _guessMax; // default: type(uint256).max
        routerParams.maxIteration = _maxIteration; // default: 256
        routerParams.eps = _eps; // default: 1e15 == max 0.1% unused. Alternatively: 1e14 implies that no more than 0.01% unused.
    }

    // Set oracle duration price smoothing
    function setOracleDuration(uint32 _oracleDuration) external onlyEmergencyAuthorized {
        require(_oracleDuration != 0);
        _checkOracle(market, _oracleDuration);
        oracleDuration = _oracleDuration;
    }

    function _checkOracle(address _market, uint32 _oracleDuration) internal view {
        (bool increaseCardinalityRequired, , bool oldestObservationSatisfied) = IPendleOracle(oracle).getOracleState(_market, _oracleDuration);
        if (increaseCardinalityRequired || !oldestObservationSatisfied) {
            revert("oracle not ready");
        }
    }

    // Can also be used to pause deposits.
    function setMaxSingleTrade(uint256 _maxSingleTrade) external onlyEmergencyAuthorized {
        require(_maxSingleTrade != type(uint256).max);
        maxSingleTrade = _maxSingleTrade;
    }

    // Set the deposit limit in asset. Set this to 0 to disallow deposits.
    function setDepositLimit(uint256 _depositLimit) external onlyManagement {
        depositLimit = _depositLimit;
    }

    // Set the minimum amount in asset that should be converted to PT. Set this to max in order to not trigger any PT buying.
    function setMinAssetAmountToPT(uint256 _minAssetAmountToPT) external onlyManagement {
        minAssetAmountToPT = _minAssetAmountToPT;
    }

    // Set the max base fee for tending to occur at.
    function setMaxTendBasefee(uint256 _maxTendBasefee) external onlyManagement {
        maxTendBasefee = _maxTendBasefee;
    }

    // Set the amount in asset that should trigger a tend if idle.
    function setDepositTrigger(uint256 _depositTrigger) external onlyManagement {
        depositTrigger = _depositTrigger;
    }

    // Set the slippage for deposits in basis points.
    function setSwapSlippageBPS(uint256 _swapSlippageBPS) external onlyManagement {
        swapSlippageBPS = _swapSlippageBPS;
    }

    // Set the buffer for reports in basis points. Can also be used to manually account for bigger depeg scenarios
    function setBufferSlippageBPS(uint256 _bufferSlippageBPS) external onlyManagement {
        bufferSlippageBPS = _bufferSlippageBPS;
    }

    // Set the minimum deposit wait time.
    function setDepositInterval(uint256 _newDepositInterval) external onlyManagement {
        // Cannot set to 0.
        require(_newDepositInterval > 0, "interval too low");
        minDepositInterval = _newDepositInterval;
    }

    // Change if anyone can deposit in or only white listed addresses
    function setOpen(bool _open) external onlyManagement {
        open = _open;
    }

    // Set or update an addresses whitelist status.
    function setAllowed(address _address,bool _allowed) external onlyManagement {
        allowed[_address] = _allowed;
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY & GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    // Manually pull funds out from the PT stack without shuting down.
    // This will also stop new deposits and withdraws.
    function manualWithdraw(uint256 _amount, uint256 _expectedAssetAmountOut) external onlyEmergencyAuthorized {
        maxSingleTrade = 0;
        depositTrigger = type(uint256).max;
        uint256 currentBalance = _balancePT();
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }
        uint256 _amountOut = _uninvest(_amount);
        require(_amountOut >= _expectedAssetAmountOut, "too little amountOut");
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 currentBalance = _balancePT();
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }
        uint256 expectedAssetAmountOut = _PTtoAsset(_amount);
        uint256 _amountOut = _uninvest(_amount);
        require(_amountOut >= expectedAssetAmountOut * (MAX_BPS - swapSlippageBPS) / MAX_BPS, "too little amountOut");
    }

    /// @notice Stagger the withdrawal for the rollover into the next maturity in case the strategy has a large amount of total assets and cannot simply rollover entirely into the next maturity.
    function staggerRolloverWithdrawal(uint256 _amount) external onlyEmergencyAuthorized {
        require(_isExpired(), "not expired");
        _emergencyWithdraw(_amount);
    }

    /// @notice Roll over into the next maturity. Call staggerRolloverWithdrawal first if you need to stagger the rollover withdrawals into several stages in case the strategy has a large amount of total assets. Only callable by governance.
    function rolloverMaturity(address _market, uint256 _slippageBPS) external onlyGovernance {
        require(_isExpired(), "not expired");
        require(_market != address(0), "!market");
        require(market != _market, "same market");

        //check new market exists long enough for preset oracleDuration
        uint32 _oracleDuration = oracleDuration;
        _checkOracle(_market, _oracleDuration);

        //redeem all PT to SY
        uint256 currentBalance = _balancePT();
        if (currentBalance > 0) {
            currentBalance = IPendleRouter(pendleRouter).redeemPyToSy(address(this), YT, currentBalance, 0);
        }
        market = _market;

        (address _SY, address _PT, address _YT) = IPendleMarket(_market).readTokens();
        require(_SY == SY, "wrong SY");
        PT = _PT;
        YT = _YT;

        //approvals:
        ERC20(_PT).forceApprove(pendleRouter, type(uint).max);

        //SY into new PT
        if (currentBalance == 0) return;
        IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address

        //calculate minPTout
        uint256 rate = IPendleOracle(oracle).getPtToSyRate(_market, _oracleDuration); //rate PT to SY
        uint256 minPTout = currentBalance * WAD * (MAX_BPS - _slippageBPS) / rate / MAX_BPS; //calculate SY value in PT accounting for slippage

        IPendleRouter(pendleRouter).swapExactSyForPt(address(this), _market, currentBalance, minPTout, routerParams, limit);
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance (onlyGovernance)
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external onlyGovernance {
        require(_token != address(asset), "!asset");
        require(_token != PT, "!PT");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }

}
