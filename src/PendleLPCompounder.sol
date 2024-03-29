// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPendleMarket} from "./interfaces/IPendleMarket.sol";
import {IPendleStaking, IMarketDepositHelper} from "./interfaces/IPendleStaking.sol";
import {IMasterPenpie} from "./interfaces/IMasterPenpie.sol";
import {ISY} from "./interfaces/ISY.sol";
import {IPendleRouter} from "./interfaces/IPendleRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {TradeFactorySwapper, ITradeFactory} from "@periphery/swappers/TradeFactorySwapper.sol";
import {AuctionSwapper, Auction} from "@periphery/swappers/AuctionSwapper.sol";

/// @title yearn-v3-Pendle
/// @author mil0x
/// @notice yearn-v3 Strategy that autocompounds Pendle LP positions.
contract PendleLPCompounder is BaseHealthCheck, UniswapV3Swapper, TradeFactorySwapper, AuctionSwapper {
    using SafeERC20 for ERC20;

    // Bool to keep autocompounding the strategy. Defaults to true. Set this to false to deactivate the strategy completely after a shutdown & emergencyWithdraw to leave everything withdrawable in asset.
    bool public autocompound = true;

    // If rewards should be sold through TradeFactory.
    bool public useTradeFactory;

    // If rewards should be sold through Auctions.
    bool public useAuction;

    // Mapping to be set by management for any reward tokens.
    // This can be used to set different mins for different tokens
    // or to set to uin256.max if selling a reward token is reverting
    // to allow for reports to still work properly.
    mapping(address => uint256) public minAmountToSellMapping;

    address internal constant pendleRouter = 0x00000000005BBB0EF59571E58418F9a4357b68A0;
    IPendleRouter.ApproxParams public routerParams;

    address internal immutable pendleStaking;
    address internal immutable marketDepositHelper;
    address internal immutable masterPenpie;
    address internal immutable PENDLE;

    address internal immutable SY;
    address public immutable targetToken;
    
    // Bool wether or not its necessary to unwrap asset before depositing into SY.
    bool public immutable unwrapTargetTokenToSY;

    address public immutable GOV; //yearn governance
    uint256 private constant WAD = 1e18;

    constructor(address _asset, address _pendleStaking, address _PENDLE, uint24 _feePENDLEtoBase, address _base, uint24 _feeBaseToTargetToken, address _targetToken, address _GOV, string memory _name) BaseHealthCheck(_asset, _name) {
        require(!_isExpired(), "expired");

        (SY, , ) = IPendleMarket(_asset).readTokens();
        unwrapTargetTokenToSY = !ISY(SY).isValidTokenIn(_targetToken); //if targetToken is invalid tokenIn, unwrapping is necessary.
        if (unwrapTargetTokenToSY) {
            require(ISY(SY).isValidTokenIn(address(0)), "!valid"); //if targetToken & address(0) are both invalid tokenIn --> revert
        }

        targetToken = _targetToken;
        pendleStaking = _pendleStaking;
        marketDepositHelper = IPendleStaking(pendleStaking).marketDepositHelper();
        masterPenpie = IPendleStaking(_pendleStaking).masterPenpie();
        PENDLE = _PENDLE;
        GOV = _GOV;

        routerParams.guessMin = 0;
        routerParams.guessMax = type(uint256).max;
        routerParams.guessOffchain = 0; // strictly 0
        routerParams.maxIteration = 256;
        routerParams.eps = 1e15; // max 0.1% unused

        // Set uni swapper values
        base = _base;
        _setUniFees(PENDLE, base, _feePENDLEtoBase);
        _setUniFees(_base, _targetToken, _feeBaseToTargetToken);

        //approvals:
        ERC20(_asset).safeApprove(pendleStaking, type(uint).max);
        ERC20(_targetToken).safeApprove(SY, type(uint).max);
        ERC20(SY).safeApprove(pendleRouter, type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {
        IMarketDepositHelper(marketDepositHelper).depositMarket(address(asset), _amount);
    }

    function _freeFunds(uint256 _amount) internal override {
        IMarketDepositHelper(marketDepositHelper).withdrawMarket(address(asset), _amount);
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (autocompound) {
            _claimAndSellRewards();

            uint256 assetBalance = _balanceAsset();
            if (assetBalance > 0) {
                _deployFunds(assetBalance); //stake LP
            }
        }

        _totalAssets = _balanceAsset() + _balanceStaked();
    }

    function _claimRewards() internal override {
        address[] memory stakingTokens = new address[](1);
        stakingTokens[0] = address(asset);
        IMasterPenpie(masterPenpie).multiclaim(stakingTokens);
    }

    function _claimAndSellRewards() internal {
        _claimRewards();
        uint256 rewardBalance;

        // If both tradeFactory and Auction are not being used, we sell rewards here:
        if (!useTradeFactory && !useAuction) {
            //PENDLE --> targetToken
            if (PENDLE != targetToken) {
                rewardBalance = _balancePENDLE();
                if (rewardBalance > minAmountToSellMapping[PENDLE]) {
                    _swapFrom(PENDLE, targetToken, rewardBalance, 0);
                }
            }

            //Other rewards --> targetToken
            address[] memory _rewardTokens = rewardTokens();
            uint256 rewardsLength = _rewardTokens.length;
            if (rewardsLength > 0) {
                address currentReward;
                for (uint256 i; i < rewardsLength; ++i) {
                    currentReward = _rewardTokens[i];
                    if (currentReward != targetToken) {
                        rewardBalance = ERC20(currentReward).balanceOf(address(this));
                        if (rewardBalance > minAmountToSellMapping[currentReward]) {
                            _swapFrom(currentReward, targetToken, rewardBalance, 0);
                        }
                    }
                }
            }
        }

        // If the maturity of the Pendle LP is reached, we cannot compound anymore.
        if (_isExpired()) return;

        //Create asset from targetToken:
        //targetToken --> SY
        rewardBalance = ERC20(targetToken).balanceOf(address(this));
        if (rewardBalance <= minAmountToSellMapping[targetToken]) return; //set minAmountToSell for targetToken in case of deposit minimum in SY
        uint256 payableBalance;
        address depositToken;
        if (unwrapTargetTokenToSY) { //for pools that require unwrapped gas as SY deposit asset
            IWETH(targetToken).withdraw(rewardBalance);
            payableBalance = rewardBalance;
            depositToken = address(0); //unwrapped
        } else {
            depositToken = targetToken;
        }
        ISY(SY).deposit{value: payableBalance}(address(this), depositToken, rewardBalance, 0);
        rewardBalance = ERC20(SY).balanceOf(address(this));

        //SY --> asset
        if (rewardBalance == 0) return;
        IPendleRouter.LimitOrderData memory limit; //skip limit order by passing zero address
        IPendleRouter(pendleRouter).addLiquiditySingleSy(address(this), address(asset), rewardBalance, 0, routerParams, limit);
    }

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceStaked() internal view returns (uint256) {
        return IMarketDepositHelper(marketDepositHelper).balance(address(asset), address(this));
    }
    
    function _balancePENDLE() internal view returns (uint256) {
        return ERC20(PENDLE).balanceOf(address(this));
    }

    function _isExpired() internal view returns (bool) {
        return IPendleMarket(address(asset)).isExpired();
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }

    function balanceStaked() external view returns (uint256) {
        return _balanceStaked();
    }

    function isExpired() external view returns (bool) {
        return _isExpired();
    }

    /**
     * @notice Set wether or not to keep autocompounding the strategy. Defaults to true. Set this to false to deactivate the strategy completely after a shutdown & emergencyWithdraw to leave everything withdrawable in asset.
     * @param _autocompound Wether or not to deactivate the autocompounding of the strategy.
     */
    function setAutocompound(bool _autocompound) external onlyManagement {
        autocompound = _autocompound;
    }

    /**
     * @notice Set wether to use the trade factory contract address.
     * @param _useTradeFactory wether to use the trade factory or not.
     */
    function setUseTradeFactory(bool _useTradeFactory) external onlyManagement {
        require(tradeFactory() != address(0));
        useTradeFactory = _useTradeFactory;
    }

    /**
     * @notice Remove all the permissions of the tradeFactory and set its address to zero.
     */
    function removeTradeFactory() external onlyManagement {
        require(tradeFactory() != address(0));
        _removeTradeFactoryPermissions();
        useTradeFactory = false;
    }

    /**
     * @notice Add a reward address that will be sold to autocompound the LP.
     * @param _rewardToken address of the reward token to be sold.
     * @param _feeRewardTokenToBase automatic swapping fee tier between rewardToken and base (0.01% = 100, 0.05% = 500, 0.3% = 3000, 1% = 10000).
     */
    function addReward(address _rewardToken, uint24 _feeRewardTokenToBase) external onlyManagement {
        require(_rewardToken != address(asset));
        _setUniFees(_rewardToken, base, _feeRewardTokenToBase);
        _addToken(_rewardToken, address(asset));
        if (targetToken != address(asset)) {
            _addToken(_rewardToken, targetToken);
        }
    }

    /**
     * @notice Remove a reward token to stop it being autocompounded to the LP.
     * @param _rewardToken address of the reward token to be removed.
     */
    function removeReward(address _rewardToken) external onlyManagement {
        _removeToken(_rewardToken, address(asset));
        if (targetToken != address(asset)) {
            _removeToken(_rewardToken, targetToken);
        }
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
    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    /**
     * @notice Set the `minAmountToSellMapping` for a specific `_token`.
     * @dev This can be used by management to adjust wether or not the
     * _claimAndSellRewards() function will attempt to sell a specific
     * reward token. This can be used if liquidity is too low, amounts
     * are too low or any other reason that may cause reverts.
     *
     * @param _token The address of the token to adjust.
     * @param _amount Min required amount to sell.
     */
    function setMinAmountToSellMapping(
        address _token,
        uint256 _amount
    ) external onlyManagement {
        minAmountToSellMapping[_token] = _amount;
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

    ///////////// DUTCH AUCTION FUNCTIONS \\\\\\\\\\\\\\\\\\
    function setAuction(address _auction) external onlyEmergencyAuthorized {
        if (_auction != address(0)) {
            address want = Auction(_auction).want();
            require(want == targetToken || want == address(asset), "wrong want");
        }
        auction = _auction;
    }

    function _auctionKicked(address _token) internal virtual override returns (uint256 _kicked) {
        require(_token != address(asset), "asset");
        _kicked = super._auctionKicked(_token);
        require(_kicked >= minAmountToSellMapping[_token], "< minAmount");
    }

    /**
     * @notice Set if tokens should be sold through the dutch auction contract.
     */
    function setUseAuction(bool _useAuction) external onlyManagement {
        useAuction = _useAuction;
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY & GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 stakedBalance = _balanceStaked();
        if (_amount > stakedBalance) {
            _amount = stakedBalance;
        }
        _freeFunds(_amount);
    }

    /**
     * @notice Set the trade factory contract address.
     * @dev For disabling, call removeTradeFactory.
     * @param _tradeFactory The address of the trade factory contract.
     */
    function setTradeFactory(address _tradeFactory, bool _useTradeFactory) external onlyGovernance {
        _setTradeFactory(_tradeFactory, address(asset));
        if (targetToken != address(asset)) { //enable tradeFactory also for targetToken for all rewardTokens 
            address[] memory _rewardTokensLocal = rewardTokens();
            uint256 rewardsLength = _rewardTokensLocal.length;
            for (uint256 i; i < rewardsLength; ++i) {
                address reward = _rewardTokensLocal[i];
                ERC20(reward).safeApprove(_tradeFactory, type(uint256).max);
                ITradeFactory(_tradeFactory).enable(reward, targetToken);
            }
        }
        useTradeFactory = _useTradeFactory;
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
