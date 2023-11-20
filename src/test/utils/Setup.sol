// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {GammaLPCompounderFactory} from "../../GammaLPCompounderFactory.sol";
import {GammaLPCompounder} from "../../GammaLPCompounder.sol";
import {IStrategyFactoryInterface} from "../../interfaces/IStrategyFactoryInterface.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IMasterChef} from "../../interfaces/IMasterChef.sol";
import {ILP} from "../../interfaces/ILP.sol";

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

    // Fuzz from $0.01 of 1e6 stable coins up to 1 trillion of a 1e18 coin
    uint256 public maxFuzzAmount = 1e30;
    uint256 public minFuzzAmount = 5_000e15;

    // Default prfot max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    bytes32 public constant BASE_STRATEGY_STORAGE = bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    function setUp() public virtual {
        _setTokenAddrs();
        //asset = ERC20(tokenAddrs["WMATIC-WETH-LP"]);
        asset = ERC20(tokenAddrs["WBTC-WETH-LP"]); //WBTC Swap route!
        //asset = ERC20(tokenAddrs["WMATIC-MATICX-LP"]); //REWARDS!
        
        address NATIVE = tokenAddrs["WMATIC"];
        address MASTERCHEF = 0x20ec0d06F447d550fC6edee42121bc8C1817b97D;
        uint256 PID = 0;
        uint256 length = IMasterChef(MASTERCHEF).poolLength();
        address tokenAddress;
        for (uint256 i; i < length; ++i) {
            tokenAddress = IMasterChef(MASTERCHEF).lpToken(i);
            if (tokenAddress == address(asset)) {
                PID = i;
                break;
            }
        }

        // Set decimals
        decimals = asset.decimals();
        strategyFactory = setUpStrategyFactory();

        // Deploy strategy and set variables
        strategy = IStrategyInterface(strategyFactory.newGammaLPCompounder(address(asset), PID, NATIVE, "Strategy"));
        setUpStrategy();

        /*
        //"WMATIC-MATICX-LP" set-up:
        vm.prank(management);
        strategy.addReward(tokenAddrs["WMATIC"]);
        vm.prank(management);
        strategy.addReward(tokenAddrs["SD"]);
        vm.prank(management);
        route.push(tokenAddrs["USDC"]);
        //route.push(tokenAddrs["WETH"]);
        strategy.setMidRouteRewardToNative(tokenAddrs["SD"], route);
        */

        
        //"WBTC-WETH-LP" set-up:
        vm.prank(management);
        route.push(tokenAddrs["USDC"]);
        strategy.setMidRouteNativeToToken0(route);
        
        

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
                new GammaLPCompounderFactory(
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
        assertEq(_strategy.totalDebt(), _totalDebt, "!totalDebt");
        assertEq(_strategy.totalIdle(), _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function checkStrategyInvariants(IStrategyInterface _strategy) public {
        address token0 = ILP(address(asset)).token0();
        address token1 = ILP(address(asset)).token1();
        console.log("token0", ERC20(token0).symbol());
        assertLe(ERC20(token0).balanceOf(address(_strategy)), 10, "token0 balance > DUST");
        console.log("token1", ERC20(token1).symbol());
        assertLe(ERC20(token1).balanceOf(address(_strategy)), 10, "token1 balance > DUST");
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
