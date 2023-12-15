// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseHealthCheck} from "@periphery/HealthCheck/BaseHealthCheck.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IUniswapRouterV3} from "./interfaces/IUniswapRouterV3.sol";
import {IHypervisor} from "./interfaces/IHypervisor.sol";
import {IGamma} from "./interfaces/IGamma.sol";
import {IQuoter} from "./interfaces/IQuoter.sol";
import {ILP} from "./interfaces/ILP.sol";
import {IMasterChef} from "./interfaces/IMasterChef.sol";
import {IDQUICK} from "./interfaces/IDQUICK.sol";

/// @title yearn-v3-Gamma
/// @author mil0x
/// @notice yearn-v3 Strategy that autocompounds Gamma LP positions.
contract GammaLPCompounder is BaseHealthCheck {
    using SafeERC20 for ERC20;

    // Bool to keep autocompounding the strategy. Defaults to true. Set this to false to deactivate the strategy completely after a shutdown & emergencyWithdraw to leave everything withdrawable in asset.
    bool public autocompound = true;

    address[] public rewards;
    mapping(address => bytes) public midRouteRewardToNative;
    bytes public midRouteNativeToToken0;
    bytes public midRouteNativeToToken1;

    address public router = 0xf5b509bB0909a69B1c207E495f687a596C168E12;

    uint256 public immutable PID;
    address public immutable GAMMA;
    address public immutable token0;
    address public immutable token1;
    address public immutable NATIVE;
    address public constant MASTERCHEF = 0x20ec0d06F447d550fC6edee42121bc8C1817b97D;
    address public constant QUOTER = 0xa15F0D7377B2A0C0c10db057f641beD21028FC89;
    address private constant DQUICK = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;
    address private constant QUICK = 0xB5C064F955D8e7F38fE0460C556a72987494eE17;
    uint256 private constant WAD = 1e18;

    address public constant GOV = 0xC4ad0000E223E398DC329235e6C497Db5470B626; //yearn governance on polygon

    constructor(address _asset, uint256 _PID, address _NATIVE, string memory _name) BaseHealthCheck(_asset, _name) {
        require(IMasterChef(MASTERCHEF).lpToken(_PID) == _asset, "WRONG_PID");
        GAMMA = IHypervisor(_asset).whitelistedAddress();
        PID = _PID; //pid needs to match _asset with MasterChef's lpToken view function index
        NATIVE = _NATIVE;
        token0 = ILP(_asset).token0();
        token1 = ILP(_asset).token1();

        //approvals:
        ERC20(_asset).safeApprove(MASTERCHEF, type(uint).max);
        ERC20(token0).safeApprove(_asset, type(uint).max);
        ERC20(token1).safeApprove(_asset, type(uint).max);
        ERC20(QUICK).safeApprove(router, type(uint).max);
        ERC20(NATIVE).safeApprove(router, type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _amount) internal override {
        IMasterChef(MASTERCHEF).deposit(PID, _amount, address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        IMasterChef(MASTERCHEF).withdraw(PID, _amount, address(this));
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        if (autocompound) {
            IMasterChef(MASTERCHEF).harvest(PID, address(this)); //harvest LP
            
            uint256 rewardBalance = _balanceDQUICK(); //DQUICK --> QUICK
            if (rewardBalance > 0) {
                IDQUICK(DQUICK).leave(rewardBalance);
            }

            rewardBalance = _balanceQUICK(); //QUICK --> NATIVE
            _swapRewardToNative(QUICK, rewardBalance);

            uint256 rewardsLength = rewards.length; //REWARDS --> NATIVE
            if (rewardsLength > 0) {
                address currentReward;
                for (uint256 i; i < rewardsLength; ++i) {
                    currentReward = rewards[i];
                    rewardBalance = ERC20(currentReward).balanceOf(address(this));
                    _swapRewardToNative(currentReward, rewardBalance);
                }
            }

            _addLiquidity(); //NATIVE --> LP

            rewardBalance = _balanceAsset();
            if (rewardBalance > 0) {
                _deployFunds(rewardBalance); //stake LP
            }
        }

        _totalAssets = _balanceAsset() + _balanceStaked();
    }

    function _addLiquidity() internal {
        uint256 NATIVEbalance = _balanceNATIVE(); //NATIVE balance to invest into LP tokens
        uint256 amountToken0 = NATIVEbalance / 2;
        uint256 amountToken1 = NATIVEbalance - amountToken0;

        //Use oracle to get accurate amountOut if 50% of NATIVE balance was invested into LP tokens:
        if (token0 != NATIVE) {
            bytes memory path0 = abi.encodePacked(NATIVE, midRouteNativeToToken0, token0);
            (amountToken0, ) = IQuoter(QUOTER).quoteExactInput(path0, amountToken0);
        }
        if (token1 != NATIVE) {
            bytes memory path1 = abi.encodePacked(NATIVE, midRouteNativeToToken1, token1);
            (amountToken1, ) = IQuoter(QUOTER).quoteExactInput(path1, amountToken1);
        }

        //LP creation calculations:
        (uint256 amountStart, uint256 amountEnd) = IGamma(GAMMA).getDepositAmount(address(asset), token0, amountToken0);
        amountEnd = (amountStart + amountEnd) / 2;
        uint256 LPratio = amountEnd * WAD / amountToken1;
        amountToken0 = NATIVEbalance * WAD / (WAD + LPratio); //correct NATIVE investment into LP tokens by actual LP ratio
        amountToken1 = NATIVEbalance - amountToken0;
        _swapNativeToToken0(amountToken0);
        _swapNativeToToken1(amountToken1);

        //Correct deposit arguments by actual swap results:
        amountToken0 = ERC20(token0).balanceOf(address(this));
        amountToken1 = ERC20(token1).balanceOf(address(this));
        (amountStart, amountEnd) = IGamma(GAMMA).getDepositAmount(address(asset), token0, amountToken0);
        (, uint256 amountEndToken0) = IGamma(GAMMA).getDepositAmount(address(asset), token1, amountToken1);
        if (amountToken1 > amountEnd) {
            amountToken1 = amountEnd;
        } else if (amountToken1 < amountStart) {
            (, amountToken0) = IGamma(GAMMA).getDepositAmount(address(asset), token1, amountToken1);
        }
        amountToken0 = Math.min(amountToken0, amountEndToken0);
        uint[4] memory minIn; //pass in empty array
        IGamma(GAMMA).deposit(amountToken0, amountToken1, address(this), address(asset), minIn); //create LP
    }

    function _swapRewardToNative(address _rewardToken, uint256 _amountIn) internal {
        if (_amountIn == 0) {
            return;
        }
        if (_rewardToken == NATIVE) {
            return;
        }
        bytes memory path = abi.encodePacked(_rewardToken, midRouteRewardToNative[_rewardToken], NATIVE);
        _swap(path, _amountIn);
    }

    function _swapNativeToToken0(uint256 _amountIn) internal {
        if (_amountIn == 0) {
            return;
        }
        if (token0 == NATIVE) {
            return;
        }
        bytes memory path = abi.encodePacked(NATIVE, midRouteNativeToToken0, token0);
        _swap(path, _amountIn);
    }

    function _swapNativeToToken1(uint256 _amountIn) internal {
        if (_amountIn == 0) {
            return;
        }
        if (token1 == NATIVE) {
            return;
        }
        bytes memory path = abi.encodePacked(NATIVE, midRouteNativeToToken1, token1);
        _swap(path, _amountIn);
    }

    function _swap(bytes memory _path, uint256 _amountIn) internal {
        IUniswapRouterV3.ExactInputParams memory params = IUniswapRouterV3.ExactInputParams({
            path: _path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: 0
        });
        IUniswapRouterV3(router).exactInput(params);
    }

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceStaked() internal view returns (uint256 _amount) {
        (_amount, ) = IMasterChef(MASTERCHEF).userInfo(PID, address(this));
    }
    
    function _balanceDQUICK() internal view returns (uint256) {
        return ERC20(DQUICK).balanceOf(address(this));
    }

    function _balanceQUICK() internal view returns (uint256) {
        return ERC20(QUICK).balanceOf(address(this));
    }

    function _balanceNATIVE() internal view returns (uint256) {
        return ERC20(NATIVE).balanceOf(address(this));
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

    /**
     * @notice Set wether or not to keep autocompounding the strategy. Defaults to true. Set this to false to deactivate the strategy completely after a shutdown & emergencyWithdraw to leave everything withdrawable in asset.
     * @param _autocompound Wether or not to deactivate the autocompounding of the strategy.
     */
    function setAutocompound(bool _autocompound) external onlyManagement {
        autocompound = _autocompound;
    }

    /**
     * @notice Add a reward address that will be sold to autocompound the LP.
     * @param _rewardToken address of the reward token to be sold.
     */
    function addReward(address _rewardToken) external onlyManagement {
        ERC20(_rewardToken).safeApprove(router, 0);
        ERC20(_rewardToken).safeApprove(router, type(uint).max);
        rewards.push(_rewardToken);
    }

    /**
     * @notice Remove a reward by its index in the reward array to stop it being autocompounded to the LP.
     * @param _rewardIndex index inside the reward array for the reward to remove.
     */
    function removeRewardByIndex(uint256 _rewardIndex) external onlyManagement {
        ERC20(rewards[_rewardIndex]).safeApprove(router, 0);
        rewards[_rewardIndex] = rewards[rewards.length - 1];
        rewards.pop();
    }

    /**
     * @notice Set the route for a specific reward token inbetween the fixed start point Reward and the fixed endpoint NATIVE declared token (usually wrapped gas). 
     * @param _tokensMidRouteRewardToNative array of addresses describing each token in the route inbetween the reward and the NATIVE token.
     */
    function setMidRouteRewardToNative(address _rewardToken, address[] calldata _tokensMidRouteRewardToNative) external onlyManagement {
        uint256 length = _tokensMidRouteRewardToNative.length;
        if (length == 0) {
            midRouteRewardToNative[_rewardToken] = "";
        } else {
            bytes memory data;
            for (uint256 i; i < length; ++i) {
                data = abi.encodePacked(data, _tokensMidRouteRewardToNative[i]);
            }
            midRouteRewardToNative[_rewardToken] = data;
        }        
    }

    /**
     * @notice Set the route for the NATIVE declared token (usually wrapped gas) inbetween the NATIVE token and the token0 of the LP. 
     * @param _tokensMidRouteNativeToToken0 array of addresses describing each token inbetween the route inbetween the NATIVE token and the token0 of the LP.
     */
    function setMidRouteNativeToToken0(address[] calldata _tokensMidRouteNativeToToken0) external onlyManagement {
        uint256 length = _tokensMidRouteNativeToToken0.length;
        if (length == 0) {
            midRouteNativeToToken0 = "";
        } else {
            bytes memory data;
            for (uint256 i; i < length; ++i) {
                data = abi.encodePacked(data, _tokensMidRouteNativeToToken0[i]);
            }
            midRouteNativeToToken0 = data;
        }        
    }

    /**
     * @notice Set the route for the NATIVE declared token (usually wrapped gas) inbetween the NATIVE token and the token1 of the LP. 
     * @param _tokensMidRouteNativeToToken1 array of addresses describing each token inbetween the route inbetween the NATIVE token and the token1 of the LP.
     */
    function setMidRouteNativeToToken1(address[] calldata _tokensMidRouteNativeToToken1) external onlyManagement {
        uint256 length = _tokensMidRouteNativeToToken1.length;
        if (length == 0) {
            midRouteNativeToToken1 = "";
        } else {
            bytes memory data;
            for (uint256 i; i < length; ++i) {
                data = abi.encodePacked(data, _tokensMidRouteNativeToToken1[i]);
            }
            midRouteNativeToToken1 = data;
        }        
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY & GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 stakedBalance = _balanceStaked();
        _freeFunds(Math.min(stakedBalance, _amount));
    }

    /// @notice Change router address (onlyGovernance).
    /// @param _newRouter The new router address
    function setRouter(address _newRouter) external onlyGovernance {
        require(_newRouter != address(0));
        address _router = router; //save gas
        //remove allowances
        ERC20(QUICK).safeApprove(_router, 0);
        ERC20(NATIVE).safeApprove(_router, 0);
        //new approval
        ERC20(QUICK).safeApprove(_newRouter, 0);
        ERC20(QUICK).safeApprove(_newRouter, type(uint).max);
        ERC20(NATIVE).safeApprove(_newRouter, 0);
        ERC20(NATIVE).safeApprove(_newRouter, type(uint).max);
        //rewards: remove allowances & approve new
        uint256 rewardsLength = rewards.length;
        if (rewardsLength > 0) {
            address currentReward;
            for (uint256 i; i < rewardsLength; ++i) {
                currentReward = rewards[i];
                ERC20(currentReward).safeApprove(_router, 0);
                ERC20(currentReward).safeApprove(_newRouter, 0);
                ERC20(currentReward).safeApprove(_newRouter, type(uint).max);
            }
        }
        router = _newRouter;
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
}
