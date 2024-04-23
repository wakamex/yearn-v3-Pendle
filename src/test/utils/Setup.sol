// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {SingleSidedPTFactory} from "../../SingleSidedPTFactory.sol";
import {SingleSidedPT} from "../../SingleSidedPT.sol";
import {IStrategyFactoryInterface} from "../../interfaces/IStrategyFactoryInterface.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IPendleMarket} from "../../interfaces/IPendleMarket.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {TokenizedStrategy} from "@tokenized-strategy/TokenizedStrategy.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instancees that we will use repeatedly.
    ERC20 public asset;
    ERC20 public market;
    address public oracle;
    address public chainlinkOracle;
    uint256 public chainlinkHeartbeat;

    uint256 maxSingleTrade = type(uint256).max;

    uint24 feeRedeemTokenToBase;
    address base;
    uint24 feeBaseToAsset;
    address redeemToken;

    address public GOV;
    IStrategyInterface public strategy;
    IStrategyFactoryInterface public strategyFactory;

    //old:
    uint24 feePENDLEtoBase;
    address public pendleStaking;
    address public PENDLE;
    bool public unwrapRedeemTokenToSY;
    address public additionalReward1;
    uint24 feeAdditionalReward1toBase;
    address public additionalReward2;
    uint24 feeAdditionalReward2toBase;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);

    // Address of the real deployed Factory
    address public factory;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    bool public forceProfit = false; //to be used with minimum deposit contracts

    // Fuzz from $0.01 of 1e6 stable coins up to 1 billion of a 1e18 coin
    uint256 public maxFuzzAmount = 20e18;
    uint256 public minFuzzAmount = 1e17;
    uint256 public expectedMaxLossBPS = 95_00;

    // Default prfot max unlock time is set for 10 days
    //uint256 public profitMaxUnlockTime = 10 days;
    uint256 public profitMaxUnlockTime = 10 days;

    bytes32 public constant BASE_STRATEGY_STORAGE = bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    function setUp() public virtual {
        uint256 mainnetFork = vm.createFork("mainnet");
        uint256 arbitrumFork = vm.createFork("arbitrum");
        //uint256 polygonFork = vm.createFork("polygon");
        //uint256 optimismFork = vm.createFork("optimism");
        

        vm.selectFork(mainnetFork);
        //vm.selectFork(arbitrumFork);
        //vm.selectFork(polygonFork);
        //vm.selectFork(optimismFork);

        //Fork specific parameters:
        //MAINNET:
        if(vm.activeFork() == mainnetFork) {
            asset = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); //WETH
            market = ERC20(0xF32e58F92e60f4b0A37A69b95d642A471365EAe8); //eETH Pool 27 Jun 2024
            redeemToken = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee; //weETH
            feeRedeemTokenToBase = 500;
            base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //WETH
            feeBaseToAsset = 100;
            
            oracle = 0x66a1096C6366b2529274dF4f5D8247827fe4CEA8;
            GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
            //chainlinkOracle = 0x5c9C449BbC9a6075A2c061dF312a35fd1E05fF22; //weETH/ETH //not necessary since WETH is valid depositToken
            chainlinkHeartbeat = 1e30;
        }
        //Arbitrum:
        if(vm.activeFork() == arbitrumFork) {
            asset = ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1); //WETH
            market = ERC20(0x952083cde7aaa11AB8449057F7de23A970AA8472); //eETH Pool 27 Jun 2024
            redeemToken = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe; //weETH
            feeRedeemTokenToBase = 100;
            base = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            feeBaseToAsset = 100;

            oracle = 0x1Fd95db7B7C0067De8D45C0cb35D59796adfD187;
            GOV = 0x6Ba1734209a53a6E63C39D4e36612cc856A34D56;
            chainlinkOracle = 0xE141425bc1594b8039De6390db1cDaf4397EA22b; //weETH/ETH
            chainlinkHeartbeat = 1e30;
        }
        
        // Set decimals
        decimals = asset.decimals();
        strategyFactory = setUpStrategyFactory();

        // Deploy strategy and set variables
        vm.prank(management);
        strategy = IStrategyInterface(strategyFactory.newSingleSidedPT(address(asset), address(market), redeemToken, feeRedeemTokenToBase, base, feeBaseToAsset, "Strategy"));
        setUpStrategy();

        factory = strategy.FACTORY();
        
        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
        vm.label(address(strategyFactory), "strategyFactory");
    }

    function setUpStrategyFactory() public returns (IStrategyFactoryInterface) {
        IStrategyFactoryInterface _factory = IStrategyFactoryInterface(
            address(
                new SingleSidedPTFactory(
                    management,
                    performanceFeeRecipient,
                    keeper,
                    oracle,
                    GOV,
                    GOV
                )
            )
        );
        return _factory;
    }

    function setUpStrategy() public {
        vm.startPrank(management);
        strategy.acceptManagement();
        strategy.setProfitLimitRatio(60535);
        strategy.setDoHealthCheck(false);
        strategy.setLossLimitRatio(50_00);
        strategy.setMaxSingleTrade(1e30);
        strategy.setSwapSlippageBPS(5_00);
        vm.stopPrank();
        vm.prank(GOV);
        strategy.setChainlinkOracle(chainlinkOracle, chainlinkHeartbeat);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        depositIntoStrategy(_strategy, _user, _amount, asset);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount,
        ERC20 _asset
    ) public {
        vm.prank(_user);
        _asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        mintAndDepositIntoStrategy(_strategy, _user, _amount, asset);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount,
        ERC20 _asset
    ) public {
        airdrop(_asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount, _asset);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        assertEq(_strategy.totalAssets(), _totalAssets, "!totalAssets");
        assertEq(asset.balanceOf(address(_strategy)), _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function checkStrategyInvariants(IStrategyInterface _strategy) public {
        (address SY, /*address PT*/, address YT) = IPendleMarket(address(market)).readTokens();
        assertLe(ERC20(SY).balanceOf(address(_strategy)), 10, "SY balance > DUST");
        if (redeemToken != address(asset)) {
            assertLe(ERC20(redeemToken).balanceOf(address(_strategy)), 10, "redeemToken balance > DUST");
        }
        //assertLe(ERC20(PT).balanceOf(address(_strategy)), 10, "PT balance > DUST");
        assertLe(ERC20(YT).balanceOf(address(_strategy)), 10, "YT balance > DUST");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.startPrank(management);
        strategy.setPerformanceFee(_performanceFee);
        vm.stopPrank();
    }


    // For easier calculations we may want to set the performance fee
    // to 0 in some tests which is underneath the minimum. So we do it manually.
    function setPerformanceFeeToZero(address _strategy) public {
        bytes32 slot;
        TokenizedStrategy.StrategyData storage S = _strategyStorage();

        assembly {
            // Perf fee is stored in the 12th slot of the Struct.
            slot := add(S.slot, 12)
        }

        // Performance fee is packed in a slot with other variables so we need
        // to maintain the same variables packed in the slot

        // profitMaxUnlock time is a uint32 at the most significant spot.
        bytes32 data = bytes4(
            uint32(IStrategyInterface(_strategy).profitMaxUnlockTime())
        );
        // Free up space for the uint16 of performancFee
        data = data >> 16;
        // Store 0 in the performance fee spot.
        data |= bytes2(0);
        // Shit 160 bits for an address
        data = data >> 160;
        // Store the strategies peformance fee recipient
        data |= bytes20(
            uint160(IStrategyInterface(_strategy).performanceFeeRecipient())
        );
        // Shift the remainder of padding.
        data = data >> 48;

        // Manually set the storage slot that holds the perfomance fee to 0
        vm.store(_strategy, slot, data);
    }

    function _strategyStorage()
        internal
        pure
        returns (TokenizedStrategy.StrategyData storage S)
    {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = BASE_STRATEGY_STORAGE;
        assembly {
            S.slot := slot
        }
    }
}
