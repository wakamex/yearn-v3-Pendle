// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {PendleLPCompounderFactory} from "../../PendleLPCompounderFactory.sol";
import {PendleLPCompounder} from "../../PendleLPCompounder.sol";
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
    address public pendleStaking;
    address public PENDLE;
    uint24 feePENDLEtoBase;
    address base; 
    uint24 feeBaseToTargetToken; 
    address targetToken;
    address public GOV;
    address public additionalReward1;
    uint24 feeAdditionalReward1toBase;
    address public additionalReward2;
    uint24 feeAdditionalReward2toBase;
    IStrategyInterface public strategy;
    IStrategyFactoryInterface public strategyFactory;
    address[] route;

    mapping(string => address) public tokenAddrs;

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

    // Fuzz from $0.01 of 1e6 stable coins up to 1 billion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e27;
    uint256 public minFuzzAmount = 5_00e15;

    // Default prfot max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    bytes32 public constant BASE_STRATEGY_STORAGE = bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    function setUp() public virtual {
        uint256 mainnetFork = vm.createFork("mainnet");
        uint256 arbitrumFork = vm.createFork("arbitrum");
        //uint256 polygonFork = vm.createFork("polygon");
        //uint256 optimismFork = vm.createFork("optimism");
        

        //vm.selectFork(mainnetFork);
        vm.selectFork(arbitrumFork);
        //vm.selectFork(polygonFork);
        //vm.selectFork(optimismFork);

        //Fork specific parameters:
        //MAINNET:
        if(vm.activeFork() == mainnetFork) {
            asset = ERC20(0xF32e58F92e60f4b0A37A69b95d642A471365EAe8); //PT-eETH-27JUN24 /SY-weETH Market
            pendleStaking = 0x6E799758CEE75DAe3d84e09D40dc416eCf713652; //https://docs.penpiexyz.io/smart-contracts --> PendleStaking
            PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
            feePENDLEtoBase = 3000;
            base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            feeBaseToTargetToken = 500;
            targetToken = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;

            GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
        }
        //Polygon:
        if(vm.activeFork() == arbitrumFork) {
            //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> PT-eETH-25APR24/SY-weETH Market --> asset
            asset = ERC20(0xE11f9786B06438456b044B3E21712228ADcAA0D1); //PT-eETH-25APR24/SY-weETH Market
            //targetToken from asset --> readTokens --> SY --> getTokensIn --> targetToken
            targetToken = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe; //weETH
            feeBaseToTargetToken = 100;

            //ARB rewards:
            additionalReward1 = 0x912CE59144191C1204E64559FE8253a0e49E6548;
            feeAdditionalReward1toBase = 500;

            //PNP rewards:
            additionalReward2 = 0x2Ac2B254Bc18cD4999f64773a966E4f4869c34Ee;
            feeAdditionalReward2toBase = 10000;
            
            //chain specific:
            base = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
            PENDLE = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8;
            feePENDLEtoBase = 3000;

            pendleStaking = 0x6DB96BBEB081d2a85E0954C252f2c1dC108b3f81; //https://docs.penpiexyz.io/smart-contracts --> Arbitrum --> PendleStaking
            GOV = 0x6Ba1734209a53a6E63C39D4e36612cc856A34D56;
        }
        
        // Set decimals
        decimals = asset.decimals();
        strategyFactory = setUpStrategyFactory();

        // Deploy strategy and set variables
        vm.prank(management);
        strategy = IStrategyInterface(strategyFactory.newPendleLPCompounder(address(asset), pendleStaking, PENDLE, feePENDLEtoBase, base, feeBaseToTargetToken, targetToken, GOV, "Strategy"));
        setUpStrategy();

        factory = strategy.FACTORY();

        // reward:
        if (additionalReward1 != address(0)) {
            vm.prank(management);
            strategy.addReward(additionalReward1, feeAdditionalReward1toBase);
        }

        // reward:
        if (additionalReward2 != address(0)) {
            vm.prank(management);
            strategy.addReward(additionalReward2, feeAdditionalReward2toBase);
        }
        
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
                new PendleLPCompounderFactory(
                    management,
                    performanceFeeRecipient,
                    keeper
                )
            )
        );
        return _factory;
    }

    function setUpStrategy() public {
        vm.prank(management);
        strategy.acceptManagement();
        vm.prank(management);
        strategy.setProfitLimitRatio(1_000_000_000_000);
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
        //assertEq(_strategy.totalDebt(), _totalDebt, "!totalDebt");
        //assertEq(_strategy.totalDebt(), _totalDebt, "!totalDebt");
        //assertEq(_strategy.totalIdle(), _totalIdle, "!totalIdle");
        assertEq(asset.balanceOf(address(_strategy)), _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function checkStrategyInvariants(IStrategyInterface _strategy) public {
        (address SY, address PT, address YT) = IPendleMarket(address(asset)).readTokens();
        assertLe(ERC20(SY).balanceOf(address(_strategy)), 10, "SY balance > DUST");
        assertLe(ERC20(PT).balanceOf(address(_strategy)), 10, "PT balance > DUST");
        assertLe(ERC20(YT).balanceOf(address(_strategy)), 10, "YT balance > DUST");
        assertLe(ERC20(PENDLE).balanceOf(address(_strategy)), 10, "PENDLE balance > DUST");
        if (additionalReward1 != address(0)) {
            assertLe(ERC20(additionalReward1).balanceOf(address(_strategy)), 10, "additionalReward1 balance > DUST");
        }
        if (additionalReward2 != address(0)) {
            assertLe(ERC20(additionalReward2).balanceOf(address(_strategy)), 10, "additionalReward2 balance > DUST");
        }
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

    function _setTokenAddrs() internal {
        tokenAddrs["WMATIC"] = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        tokenAddrs["WBTC"] = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
        tokenAddrs["WETH"] = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        tokenAddrs["USDT"] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
        tokenAddrs["DAI"] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        tokenAddrs["USDC"] = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
        tokenAddrs["SD"] = 0x1d734A02eF1e1f5886e66b0673b71Af5B53ffA94;

        tokenAddrs["WMATIC-WETH-LP"] = 0x02203f2351E7aC6aB5051205172D3f772db7D814;
        tokenAddrs["WBTC-WETH-LP"] = 0x4B9e26a02121a1C541403a611b542965Bd4b68Ce;
        tokenAddrs["USDC-WETH-LP"] = 0x3Cc20A6795c4b57d9817399F68E83e71C8626580;
        tokenAddrs["WMATIC-USDC-LP"] = 0x04d521E2c414E6d898c6F2599FdD863Edf49e247;
        tokenAddrs["WBTC-USDC-LP"] = 0x3f35705479d9d77c619b2aAC9dd7a64e57151506;
        tokenAddrs["USDC-USDT-LP"] = 0x795f8c9B0A0Da9Cd8dea65Fc10f9B57AbC532E58;
        tokenAddrs["WMATIC-WETH-WIDE-LP"] = 0x81Cec323BF8C4164c66ec066F53cc053A535f03D;
        tokenAddrs["USDC-DAI-LP"] = 0x9E31214Db6931727B7d63a0D2b6236DB455c0965;
        tokenAddrs["WMATIC-MATICX-LP"] = 0x8dd3BF71eF18dd88869d128BDE058C9d8c270176;
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
