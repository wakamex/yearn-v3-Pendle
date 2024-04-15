// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPendleMarket} from "./interfaces/IPendleMarket.sol";
import {ISY} from "./interfaces/ISY.sol";
import {IPendleRouter} from "./interfaces/IPendleRouter.sol";
import {IPendleOracle} from "./interfaces/IPendleOracle.sol";

import {IWETH} from "./interfaces/IWETH.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {TradeFactorySwapper, ITradeFactory} from "@periphery/swappers/TradeFactorySwapper.sol";
import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";

import "./interfaces/Chainlink/AggregatorInterface.sol";

/// @title yearn-v3-SingleSidedPT
/// @author mil0x
/// @notice yearn-v3 Strategy that invests into Pendle PT positions.
contract SingleSidedPT is BaseHealthCheck, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    address public market;
    address public immutable SY;
    address public PT;
    address public YT;
    address public immutable redeemToken;
    address internal immutable oracle;

    uint32 public oracleDuration;

    // In case we use a chainlink oracle to check latest PT/asset price
    address public chainlinkOracle;
    uint256 public chainlinkHeartbeat;

    address internal constant pendleRouter = 0x00000000005BBB0EF59571E58418F9a4357b68A0;
    IPendleRouter.ApproxParams public routerParams;

    //uniswapv3 quoter:
    address internal constant quoter = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    // Bools to determine wether or not its necessary to unwrap asset or swap asset before depositing into SY.
    bool internal immutable assetIsValidDepositToken;
    bool internal immutable addressZeroIsValidDepositToken;

    address public immutable GOV; //yearn governance
    uint256 private constant WAD = 1e18;

    uint256 public minAssetAmountToPT;
    // The max in asset we will deposit or withdraw at a time.
    uint256 public maxSingleTrade;
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

    constructor(address _asset, address _market, address _redeemToken, uint24 _feeRedeemTokenToBase, address _base, uint24 _feeBaseToAsset, address _oracle, address _GOV, string memory _name) BaseHealthCheck(_asset, _name) {
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
        
        require(ISY(SY).isValidTokenOut(_redeemToken), "!valid out");  

        //Immutable variables cannot be initialized inside an if statement, so we use a combination logic to check the correct deposit flow into SY.
        assetIsValidDepositToken = ISY(SY).isValidTokenIn(_asset);
        addressZeroIsValidDepositToken = ISY(SY).isValidTokenIn(address(0));

        if (!assetIsValidDepositToken && !addressZeroIsValidDepositToken) { //if asset & address(0) are invalid, redeemToken should be validTokenIn
            require(ISY(SY).isValidTokenIn(_redeemToken), "!valid in"); //if asset & address(0) & redeemToken are all invalid tokenIn --> revert
        }

        redeemToken = _redeemToken;
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

        // Set uni swapper values
        base = _base;
        _setUniFees(_redeemToken, _base, _feeRedeemTokenToBase);
        _setUniFees(_base, _asset, _feeBaseToAsset);
        
        //approvals:
        ERC20(_asset).forceApprove(SY, type(uint).max);
        ERC20(_redeemToken).forceApprove(SY, type(uint).max);
        ERC20(SY).forceApprove(pendleRouter, type(uint).max);
        ERC20(PT).forceApprove(pendleRouter, type(uint).max);
        ERC20(YT).forceApprove(pendleRouter, type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {
        //do nothing, we want to only have the keeper swap funds
    }

    function _invest(uint256 _amount) internal {
        if (_isExpired()) return;
        uint256 currentBalance = _amount;
        //asset --> SY
        if (currentBalance <= minAssetAmountToPT) return;
        uint256 payableBalance;
        address depositToken;
        if (assetIsValidDepositToken) { //asset is valid deposit token
            depositToken = address(asset);
        } else if (addressZeroIsValidDepositToken) { //address(0) is valid deposit token --> unwrap necessary
            IWETH(address(asset)).withdraw(currentBalance);
            payableBalance = currentBalance;
            depositToken = address(0); //unwrapped
        } else { //swap necessary
            depositToken = redeemToken;
            //swap with minAmountOut check == 0, since we check later in swapExactSyForPT versus initial asset amount
            currentBalance = _swapFrom(address(asset), depositToken, currentBalance, 0);
            if (currentBalance == 0) revert("swap 0 out");
        }

        ISY(SY).deposit{value: payableBalance}(address(this), depositToken, currentBalance, 0);
        currentBalance = ERC20(SY).balanceOf(address(this));

        //SY --> PT
        if (currentBalance == 0) return;
        IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address
        //here we check minAmountOut versus initial asset amount
        IPendleRouter(pendleRouter).swapExactSyForPt(address(this), market, currentBalance, 0, routerParams, limit);

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

    function _uninvest(uint256 currentBalance) internal {
        if (currentBalance == 0) return;
        //PT --> SY
        if (_isExpired()) { //if expired, redeem PY to SY
            currentBalance = IPendleRouter(pendleRouter).redeemPyToSy(address(this), YT, currentBalance, 0);
        } else {
            IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address
            // We don't enforce any min amount out since withdrawer's can use 'maxLoss'
            (currentBalance, ) = IPendleRouter(pendleRouter).swapExactPtForSy(address(this), market, currentBalance, 0, limit);
            if (currentBalance == 0) return;
        }
        //SY --> asset
        // We don't enforce any min amount out since withdrawers can use 'maxLoss'
        currentBalance = ISY(SY).redeem(address(this), currentBalance, redeemToken, 0, false);
        if (redeemToken == address(asset)) return;
        // We don't enforce any min amount out since withdrawers can use 'maxLoss'
        _swapFrom(redeemToken, address(asset), currentBalance, 0);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (!TokenizedStrategy.isShutdown()) {
            _invest(Math.min(_balanceAsset(), maxSingleTrade));
        }

        _totalAssets = _balanceAsset() + _PTtoAsset(_balancePT());
    }

    function _PTtoAsset(uint256 _amount) internal view returns (uint256) {
        //PT --> SY
        uint256 rate = IPendleOracle(oracle).getPtToSyRate(market, oracleDuration);
        _amount = _amount * rate / WAD;
        if (redeemToken == address(asset)) {
            //SY --> redeemToken == asset
            _amount = ISY(SY).previewRedeem(redeemToken, _amount);
            return _amount; //full value in asset
        } else if (assetIsValidDepositToken) {
            //SY --> assetIn
            _amount = _amount * WAD / ISY(SY).previewDeposit(address(asset), WAD);
        } else if (addressZeroIsValidDepositToken) {
            //SY --> address(0) == assetIn
            _amount = _amount * WAD / ISY(SY).previewDeposit(address(0), WAD);
        } else { //Chainlink oracle: SY --> redeemToken -- chainlink --> asset
            require(chainlinkOracle != address(0), "chainlink address");
            _amount = ISY(SY).previewRedeem(redeemToken, _amount);
            (, int256 answer, , uint256 updatedAt, ) = AggregatorInterface(chainlinkOracle).latestRoundData();
            uint256 divisor = 10 ** AggregatorInterface(chainlinkOracle).decimals();
            uint256 redeemTokenPrice = uint256(answer);
            require((redeemTokenPrice > 1 && block.timestamp - updatedAt < chainlinkHeartbeat), "!chainlink");
            _amount = _amount * redeemTokenPrice / divisor; //redeemToken --> asset
        }
        return _amount * (MAX_BPS - bufferSlippageBPS) / MAX_BPS; //needs to be swapped to asset --> reduce by bufferSlippageBPS as buffer
    }

    function _tend(uint256) internal override {
        _invest(Math.min(_balanceAsset(), maxSingleTrade));
    }

    function _tendTrigger() internal view override returns (bool _shouldTend) {
        if (block.timestamp - lastDeposit > minDepositInterval && _balanceAsset() > depositTrigger) {
            _shouldTend = block.basefee < maxTendBasefee;
        }
    }

    function availableDepositLimit(address _owner) public view override returns (uint256) {
        // If the owner is whitelisted or the strategy is open.
        if (allowed[_owner] || open) {
            // Allow the max of a single deposit.
            return maxSingleTrade;
        } else {
            // Otherwise they cannot deposit.
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
     * @notice Set the uni fees for swaps.
     * Any incentivized tokens will need a fee to be set for each
     * reward token that it wishes to swap on reports.
     *
     * @param _token0 The first token of the pair.
     * @param _token1 The second token of the pair.
     * @param _fee The fee to be used for the pair.
     */
    function setUniFees(address _token0, address _token1, uint24 _fee) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
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
        oracleDuration = _oracleDuration;
    }

    // Can also be used to pause deposits.
    function setMaxSingleTrade(uint256 _maxSingleTrade) external onlyEmergencyAuthorized {
        require(_maxSingleTrade != type(uint256).max);
        maxSingleTrade = _maxSingleTrade;
    }

    // Set the minimum amount in asset that should be converted to PT.
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
    function setBufferSlippageBPS(uint256 _swapSlippageBPS) external onlyManagement {
        swapSlippageBPS = _swapSlippageBPS;
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
    // Can call tend after this to update internal balances.
    function manualWithdraw(uint256 _amount) external onlyEmergencyAuthorized {
        maxSingleTrade = 0;
        depositTrigger = type(uint256).max;
        uint256 currentBalance = _balancePT();
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }
        _uninvest(_amount);
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 currentBalance = _balancePT();
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }
        _uninvest(_amount);
    }

    /// @notice Roll over into the next maturity. Only callable by governance.
    function rolloverMaturity(address _market, uint256 _slippageBPS) external onlyGovernance {
        require(_isExpired(), "not expired");
        require(_market != address(0), "!market");
        require(market != _market, "same market");

        //redeem all PT to SY
        uint256 currentBalance = IPendleRouter(pendleRouter).redeemPyToSy(address(this), YT, _balancePT(), 0);
        market = _market;

        (address _SY, address _PT, address _YT) = IPendleMarket(_market).readTokens();
        require(_SY == SY, "wrong SY");
        PT = _PT;
        YT = _YT;

        require(ISY(SY).isValidTokenOut(redeemToken), "!valid out");  
        if (assetIsValidDepositToken) {
            require(ISY(SY).isValidTokenIn(address(asset)), "asset !valid in");
        }
        if (addressZeroIsValidDepositToken) {
            require(ISY(SY).isValidTokenIn(address(0)), "0 !valid in");
        }
        if (!assetIsValidDepositToken && !addressZeroIsValidDepositToken) { //if asset & address(0) are invalid, redeemToken should be validTokenIn
            require(ISY(SY).isValidTokenIn(redeemToken), "!valid in"); //if asset & address(0) & redeemToken are all invalid tokenIn --> revert
        }

        //approvals:
        ERC20(PT).forceApprove(pendleRouter, type(uint).max);
        ERC20(YT).forceApprove(pendleRouter, type(uint).max);

        //SY into new PT
        if (currentBalance == 0) return;
        IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address

        //calcualte minPTout
        uint256 rate = IPendleOracle(oracle).getPtToSyRate(_market, oracleDuration); //rate PT to SY
        uint256 minPTout = currentBalance * WAD * (MAX_BPS - _slippageBPS) / rate / MAX_BPS; //calculate SY value in PT accounting for slippage

        IPendleRouter(pendleRouter).swapExactSyForPt(address(this), _market, currentBalance, minPTout, routerParams, limit);
    }

    /// @notice Set the chainlink oracle address & heartbeat. Only callable by governance.
    function setChainlinkOracle(address _chainlinkOracle, uint256 _chainlinkHeartbeat) external onlyGovernance {
        chainlinkOracle = _chainlinkOracle;
        chainlinkHeartbeat = _chainlinkHeartbeat;
    }

    /// @notice Sweep of non-asset ERC20 tokens to governance (onlyGovernance)
    /// @param _token The ERC20 token to sweep
    function sweep(address _token) external onlyGovernance {
        require(_token != address(asset), "!asset");
        ERC20(_token).safeTransfer(GOV, ERC20(_token).balanceOf(address(this)));
    }

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }

    receive() external payable {}
}
