// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

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

    ///@notice Address of our Pendle market.
    address public market;
    address internal immutable oracle;

    ///@notice Oracle TWAP duration, in seconds.
    uint32 public oracleDuration;

    ///@notice Bool if the strategy is open for any depositors. Default = true.
    bool public open = true;

    ///@notice Mapping of addresses allowed to deposit.
    mapping(address => bool) public allowed;

    struct TradeParams {
        ///@notice Set the minimum asset amount to be converted to PT. Set to max to prevent PT buying.
        uint128 minAssetAmountToPT;
        ///@notice The max in asset will be invested by the keeper at a time.
        uint128 maxSingleTrade;
    }

    ///@notice Parameters used to contrin size of strategy investing into PT.
    TradeParams public tradeParams;

    ///@notice The total deposit limit for the strategy. Use in case we want to cap a given strategy.
    uint256 public depositLimit = type(uint256).max;

    address internal constant pendleRouter =
        0x888888888889758F76e7103c6CbF23ABbF58F946;

    ///@notice Parameters passed to Pendle's router for swaps in using binary search.
    IPendleRouter.ApproxParams public routerParams;

    ///@notice Address of this market's SY token.
    address public immutable SY;

    ///@notice Address of this market's PT token.
    address public PT;
    address internal YT;

    ///@notice Amount in Basis Points to allow for slippage when reporting.
    uint256 public swapSlippageBPS;

    ///@notice Amount in Basis Points to account for as buffer when reporting. Can also manually account for bigger depeg scenarios.
    uint256 public bufferSlippageBPS;

    // Struct for all variables involved in tendTrigger
    struct TendTriggerParams {
        ///@notice The amount in asset that will trigger a tend if idle.
        uint128 depositTrigger;
        ///@notice The max amount the base fee can be for a tend to happen.
        uint48 maxTendBaseFee;
        ///@notice Minimum time between deposits to wait.
        uint40 minDepositInterval;
        ///@notice Time stamp of the last deployment of funds.
        uint40 lastDeposit;
    }

    ///@notice Contains adjustable variables that govern when to tend this strategy.
    TendTriggerParams public tendTriggerParams;

    ///@notice Yearn governance
    address public immutable GOV;

    uint256 internal constant WAD = 1e18;

    constructor(
        address _asset,
        address _market,
        address _oracle,
        address _GOV,
        string memory _name
    ) BaseHealthCheck(_asset, _name) {
        market = _market;
        require(!_isExpired(), "expired");
        oracle = _oracle;
        //Default oracle duration to 1 hour price smoothing recommendation by Pendle Finance
        oracleDuration = 3600;

        //Default maxSingleTrade to 15 ETH as a majority of markets are ETH based. Change this for non-ETH.
        tradeParams.maxSingleTrade = 15e18;

        (SY, PT, YT) = IPendleMarket(_market).readTokens();
        require(ISY(SY).isValidTokenOut(_asset), "!valid out");
        require(ISY(SY).isValidTokenIn(_asset), "!valid in");

        // Default slippage to 0.5%.
        swapSlippageBPS = 50;
        bufferSlippageBPS = 50;

        routerParams.guessMax = type(uint256).max;
        routerParams.maxIteration = 256;
        routerParams.eps = 1e15; // max 0.1% unused

        TendTriggerParams memory _tendTriggerParams;
        _tendTriggerParams.depositTrigger = 5e18; // The amount in asset that will trigger a tend if idle. Default to 5 ETH; update for non-ETH.
        _tendTriggerParams.maxTendBaseFee = 20e9; // The max amount the base fee can be for a tend to happen. Default max tend fee to 20 gwei.
        _tendTriggerParams.minDepositInterval = 43200; // Minimum time between deposits to wait. Default min deposit interval to 12 hours.
        tendTriggerParams = _tendTriggerParams;

        // Allow a 500% gain.
        _setProfitLimitRatio(500_00);

        GOV = _GOV;

        //approvals:
        ERC20(_asset).forceApprove(SY, type(uint256).max);
        ERC20(SY).forceApprove(pendleRouter, type(uint256).max);
        ERC20(PT).forceApprove(pendleRouter, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {
        //do nothing, we want to only have the keeper swap funds
    }

    function _invest(uint256 _amount) internal {
        if (_amount == 0) return;
        //asset --> SY
        ISY(SY).deposit(address(this), address(asset), _amount, 0);
        _amount = ERC20(SY).balanceOf(address(this));

        //SY --> PT
        IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address
        uint256 minPTout = (_SYtoPT(_amount) * (MAX_BPS - swapSlippageBPS)) /
            MAX_BPS; //calculate minimum expected PT out
        IPendleRouter(pendleRouter).swapExactSyForPt(
            address(this),
            market,
            _amount,
            minPTout,
            routerParams,
            limit
        );

        // Update the last time that we deposited.
        tendTriggerParams.lastDeposit = uint40(block.timestamp);
    }

    function _freeFunds(uint256 _amount) internal override {
        //Redeem PT shares proportional to the SSPT shares redeemed:
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        uint256 totalDebt = totalAssets - _balanceOfAsset();
        uint256 PTtoUninvest = (_balanceOfPT() * _amount) / totalDebt;
        _uninvest(PTtoUninvest);
    }

    function _uninvest(uint256 currentBalance) internal returns (uint256) {
        if (currentBalance == 0) return 0;
        //PT --> SY
        if (_isExpired()) {
            //if expired, redeem PY to SY
            currentBalance = IPendleRouter(pendleRouter).redeemPyToSy(
                address(this),
                YT,
                currentBalance,
                0
            );
        } else {
            IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address
            // We don't enforce any min amount out since withdrawer's can use 'maxLoss'
            (currentBalance, ) = IPendleRouter(pendleRouter).swapExactPtForSy(
                address(this),
                market,
                currentBalance,
                0,
                limit
            );
            if (currentBalance == 0) return 0;
        }
        //SY --> asset
        // We don't enforce any min amount out since withdrawers can use 'maxLoss'
        return
            ISY(SY).redeem(
                address(this),
                currentBalance,
                address(asset),
                0,
                false
            );
    }

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        if (!_isExpired() && !TokenizedStrategy.isShutdown()) {
            uint256 assetBalance = _balanceOfAsset();
            TradeParams memory _tradeParams = tradeParams;
            if (assetBalance > _tradeParams.minAssetAmountToPT) {
                _invest(_min(assetBalance, _tradeParams.maxSingleTrade));
            }
        }

        _totalAssets =
            _balanceOfAsset() +
            (_PTtoAsset(_balanceOfPT()) * (MAX_BPS - bufferSlippageBPS)) /
            MAX_BPS; //reduce PT balance by bufferSlippageBPS to account for the fact that it will need to be swapped back to asset
    }

    function _SYtoPT(uint256 _amount) internal view returns (uint256) {
        return
            (_amount * WAD) /
            IPendleOracle(oracle).getPtToSyRate(market, oracleDuration);
    }

    function _PTtoSY(uint256 _amount) internal view returns (uint256) {
        return
            (_amount *
                IPendleOracle(oracle).getPtToSyRate(market, oracleDuration)) /
            WAD;
    }

    function _PTtoAsset(uint256 _amount) internal view returns (uint256) {
        return ISY(SY).previewRedeem(address(asset), _PTtoSY(_amount));
    }

    function _tend(uint256) internal override {
        uint256 assetBalance = _balanceOfAsset();
        TradeParams memory _tradeParams = tradeParams;
        if (assetBalance > _tradeParams.minAssetAmountToPT) {
            _invest(_min(assetBalance, _tradeParams.maxSingleTrade));
        }
    }

    function _tendTrigger() internal view override returns (bool _shouldTend) {
        TendTriggerParams memory _tendTriggerParams = tendTriggerParams;
        if (
            !_isExpired() &&
            block.timestamp - _tendTriggerParams.lastDeposit >
            _tendTriggerParams.minDepositInterval &&
            _balanceOfAsset() > _tendTriggerParams.depositTrigger &&
            tradeParams.maxSingleTrade > 0 &&
            !TokenizedStrategy.isShutdown()
        ) {
            _shouldTend = block.basefee < _tendTriggerParams.maxTendBaseFee;
        }
    }

    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
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

    function _balanceOfAsset() internal view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _balanceOfPT() internal view returns (uint256) {
        return ERC20(PT).balanceOf(address(this));
    }

    function _isExpired() internal view returns (bool) {
        return IPendleMarket(market).isExpired();
    }

    function _checkOracle(
        address _market,
        uint32 _oracleDuration
    ) internal view {
        (
            bool increaseCardinalityRequired,
            ,
            bool oldestObservationSatisfied
        ) = IPendleOracle(oracle).getOracleState(_market, _oracleDuration);
        if (increaseCardinalityRequired || !oldestObservationSatisfied) {
            revert("oracle not ready");
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    function balanceOfAsset() external view returns (uint256) {
        return _balanceOfAsset();
    }

    function balanceOfPT() external view returns (uint256) {
        return _balanceOfPT();
    }

    function isExpired() external view returns (bool) {
        return _isExpired();
    }

    /**
     * @notice Set oracle duration price smoothing
     * @param _oracleDuration twap duration in seconds
     */
    function setOracleDuration(
        uint32 _oracleDuration
    ) external onlyEmergencyAuthorized {
        require(_oracleDuration >= 900, "duration too low");
        _checkOracle(market, _oracleDuration);
        oracleDuration = _oracleDuration;
    }

    /**
     * @notice Set the tradeParams for the strategy to decide on minimum investment and maximum single investments for the keeper.
     * @param _minAssetAmountToPT Set the minimum amount in asset that should be converted to PT. Set this to max in order to not trigger any PT buying.
     * @param _maxSingleTrade Set the max in asset amount that will be invested by the keeper at a time. Can also be used to pause keeper investments.
     */
    function setTradeParams(
        uint128 _minAssetAmountToPT,
        uint128 _maxSingleTrade
    ) external onlyManagement {
        require(
            _maxSingleTrade <= type(uint128).max &&
                _minAssetAmountToPT <= type(uint128).max,
            "too large"
        );
        TradeParams memory _tradeParams;
        _tradeParams.minAssetAmountToPT = _minAssetAmountToPT;
        _tradeParams.maxSingleTrade = _maxSingleTrade;
        tradeParams = _tradeParams;
    }

    /**
     * @notice Set the routerParams for the pendleRouter. Pendle's AMM only supports the built-in swapSyForExactPt. To execute a swapExactSyForPt, the
     *  router will conduct a binary search to determine the amount of PT to swap.
     * @param _guessMin The minimum value for binary search. Default: 0.
     * @param _guessMax The maximum value for binary search. Default: type(uint256).max.
     * @param _maxIteration The maximum number of times binary search will be performed. Default: 256.
     * @param _eps The precision of binary search - the maximum proportion of the input that can be unused. Default: 1e15 == max 0.1% unused.
     *  Alternatively: 1e14 implies that no more than 0.01% unused.
     */
    function setRouterParams(
        uint256 _guessMin,
        uint256 _guessMax,
        uint256 _maxIteration,
        uint256 _eps
    ) external onlyManagement {
        routerParams.guessMin = _guessMin; // default: 0
        routerParams.guessMax = _guessMax; // default: type(uint256).max
        routerParams.maxIteration = _maxIteration; // default: 256
        routerParams.eps = _eps; // default: 1e15 == max 0.1% unused. Alternatively: 1e14 implies that no more than 0.01% unused.
    }

    /**
     * @notice Set the tendTriggerParams for all variables involved in tendTrigger.
     * @param _depositTrigger The amount in asset that will trigger a tend if idle.
     * @param _maxTendBaseFee The max amount the base fee can be for a tend to happen in wei.
     * @param _minDepositInterval Minimum time between deposits to wait in seconds.
     */
    function setTendTriggerParams(
        uint128 _depositTrigger,
        uint48 _maxTendBaseFee,
        uint40 _minDepositInterval
    ) external onlyManagement {
        require(_minDepositInterval > 0, "interval too low");
        require(_depositTrigger <= type(uint128).max, "too large");
        tendTriggerParams.depositTrigger = _depositTrigger;
        tendTriggerParams.maxTendBaseFee = _maxTendBaseFee;
        tendTriggerParams.minDepositInterval = _minDepositInterval;
    }

    /**
     * @notice Set the deposit limit in asset amount. Set this to 0 to disallow deposits.
     * @param _depositLimit the deposit limit in asset units
     */
    function setDepositLimit(uint256 _depositLimit) external onlyManagement {
        depositLimit = _depositLimit;
    }

    /**
     * @notice Set the slippage for keeper investments in basis points.
     * @param _swapSlippageBPS the maximum slippage in basis points (BPS)
     */
    function setSwapSlippageBPS(
        uint256 _swapSlippageBPS
    ) external onlyManagement {
        require(_swapSlippageBPS <= MAX_BPS);
        swapSlippageBPS = _swapSlippageBPS;
    }

    /**
     * @notice Set the buffer for reports in basis points. Can also be used to manually account for bigger depeg scenarios
     * @param _bufferSlippageBPS the buffer slippage in basis points (BPS)
     */
    function setBufferSlippageBPS(
        uint256 _bufferSlippageBPS
    ) external onlyManagement {
        require(_bufferSlippageBPS <= MAX_BPS);
        bufferSlippageBPS = _bufferSlippageBPS;
    }

    /**
     * @notice Change if anyone can deposit in or only white listed addresses
     * @param _open the bool deciding if anyone can deposit (true) or only whitelisted addresses (false)
     */
    function setOpen(bool _open) external onlyManagement {
        open = _open;
    }

    /**
     * @notice Set or update an addresses whitelist status.
     * @param _address the address for which to change the whitelist status
     * @param _allowed the bool to set as whitelisted (true) or not (false)
     */
    function setAllowed(
        address _address,
        bool _allowed
    ) external onlyManagement {
        allowed[_address] = _allowed;
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY & GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Manually pull funds out from the PT stack without shuting down. This will also stop keeper investments.
     * @param _amount the PT amount to uninvest into asset
     * @param _expectedAssetAmountOut the minimum acceptable asset amount as a result of uninvestment
     */
    function manualWithdraw(
        uint256 _amount,
        uint256 _expectedAssetAmountOut
    ) external onlyEmergencyAuthorized {
        tradeParams.maxSingleTrade = 0;
        uint256 currentBalance = _balanceOfPT();
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }
        uint256 _amountOut = _uninvest(_amount);
        require(_amountOut >= _expectedAssetAmountOut, "too little amountOut");
    }

    /**
     * @notice Manually pull funds out from the PT stack after the strategy has been shutdown.
     * @param _amount the PT amount to uninvest into asset
     */
    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 currentBalance = _balanceOfPT();
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }
        uint256 expectedAssetAmountOut = _PTtoAsset(_amount);
        uint256 _amountOut = _uninvest(_amount);
        require(
            _amountOut >=
                (expectedAssetAmountOut * (MAX_BPS - swapSlippageBPS)) /
                    MAX_BPS,
            "too little amountOut"
        );
    }

    /**
     * @notice Redeem all PT into asset and rollover the market into a new maturity. Only callable by governance.
     * @param _market the market address (not PT address) for the new maturity to rollover into
     * @param _minAssetAmountOut the acceptable minimum amount of asset out for the PT amount currently held by the strategy
     */
    function rolloverMaturity(
        address _market,
        uint256 _minAssetAmountOut
    ) external onlyGovernance {
        require(_isExpired(), "not expired");
        require(_market != address(0), "!market");
        require(market != _market, "same market");

        //check new market exists long enough for preset oracleDuration
        _checkOracle(_market, oracleDuration);

        //redeem all PT to SY
        uint256 currentBalance = _balanceOfPT();
        if (currentBalance > 0) {
            currentBalance = IPendleRouter(pendleRouter).redeemPyToSy(
                address(this),
                YT,
                currentBalance,
                0
            );
        }

        //set addresses to new maturity
        market = _market;
        require(!_isExpired(), "expired");
        (address _SY, address _PT, address _YT) = IPendleMarket(_market)
            .readTokens();
        require(_SY == SY, "wrong SY");
        PT = _PT;
        YT = _YT;
        ERC20(_PT).forceApprove(pendleRouter, type(uint256).max);

        //redeem all SY into asset (let keeper move asset to new PT over time)
        if (currentBalance == 0 && _minAssetAmountOut == 0) return;
        ISY(SY).redeem(
            address(this),
            currentBalance,
            address(asset),
            _minAssetAmountOut,
            false
        );
    }

    /**
     * @notice Sweep of non-asset ERC20 tokens to governance (onlyGovernance)
     * @param _token The ERC20 token to sweep
     */
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
