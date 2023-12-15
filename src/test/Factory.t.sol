// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {IMasterChef} from "../interfaces/IMasterChef.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FactoryTest is Setup {
    address public constant chef = 0x20ec0d06F447d550fC6edee42121bc8C1817b97D;

    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyFactoryOK() public {
        console.log("address of strategy factory", address(strategyFactory));
        assertTrue(address(0) != address(strategyFactory));
        assertEq(strategyFactory.management(), management);
        assertEq(
            strategyFactory.performanceFeeRecipient(),
            performanceFeeRecipient
        );
        assertEq(strategyFactory.keeper(), keeper);
    }

    function getPID(address _asset) public view returns (uint256 _PID) {
        uint256 length = IMasterChef(chef).poolLength();
        address tokenAddress;
        for (uint256 i; i < length; ++i) {
            tokenAddress = IMasterChef(chef).lpToken(i);
            if (tokenAddress == _asset) {
                _PID = i;
                break;
            }
        }
    }

    function test_deploy(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        address _asset;
        uint256 _PID;
        address _NATIVE;
        IStrategyInterface strategyTest;

        console.log("WBTC-WETH-LP");
        _asset = tokenAddrs["WBTC-WETH-LP"];
        console.log("_asset", _asset);
        _PID = getPID(_asset);
        console.log("_PID", _PID);
        _NATIVE = tokenAddrs["WMATIC"];
        vm.prank(management);
        strategyTest = IStrategyInterface(strategyFactory.newGammaLPCompounder(_asset, _PID, _NATIVE, "2"));
        strategy_testing(strategyTest, _amount);
/*
        console.log("USDC-USDT-LP");
        _asset = tokenAddrs["USDC-USDT-LP"];
        _PID = getPID(_asset);
        console.log("_PID", _PID);
        strategyTest = IStrategyInterface(strategyFactory.newGammaLPCompounder(_asset, _PID, _NATIVE, "1"));
        console.log("factory done");
        strategy_testing(strategyTest, _amount);

        console.log("USDC-WETH-LP");
        _asset = tokenAddrs["USDC-WETH-LP"];
        _PID = getPID(_asset);
        console.log("_PID", _PID);
        strategyTest = IStrategyInterface(strategyFactory.newGammaLPCompounder(_asset, _PID, _NATIVE, "3"));
        strategy_testing(strategyTest, _amount);

        console.log("WMATIC-USDC-LP");
        _asset = tokenAddrs["WMATIC-USDC-LP"];
        _PID = getPID(_asset);
        strategyTest = IStrategyInterface(strategyFactory.newGammaLPCompounder(_asset, _PID, _NATIVE, ""));
        strategy_testing(strategyTest, _amount);

        console.log("WBTC-USDC-LP");
        _asset = tokenAddrs["WBTC-USDC-LP"];
        _PID = getPID(_asset);
        strategyTest = IStrategyInterface(strategyFactory.newGammaLPCompounder(_asset, _PID, _NATIVE, ""));
        strategy_testing(strategyTest, _amount);

        console.log("WMATIC-WETH-WIDE-LP");
        _asset = tokenAddrs["WMATIC-WETH-WIDE-LP"];
        _PID = getPID(_asset);
        strategyTest = IStrategyInterface(strategyFactory.newGammaLPCompounder(_asset, _PID, _NATIVE, ""));
        strategy_testing(strategyTest, _amount);

        console.log("USDC-DAI-LP");
        _asset = tokenAddrs["USDC-DAI-LP"];
        _PID = getPID(_asset);
        strategyTest = IStrategyInterface(strategyFactory.newGammaLPCompounder(_asset, _PID, _NATIVE, ""));
        strategy_testing(strategyTest, _amount);
*/
        console.log("WMATIC-MATICX-LP");
        _asset = tokenAddrs["WMATIC-MATICX-LP"];
        _PID = getPID(_asset);
        vm.prank(management);
        strategyTest = IStrategyInterface(strategyFactory.newGammaLPCompounder(_asset, _PID, _NATIVE, ""));
        strategy_testing(strategyTest, _amount);
    }

    function strategy_testing(
        IStrategyInterface _strategy,
        uint256 _amount
    ) internal {
        ERC20 _asset = ERC20(_strategy.asset());
        console.log(_amount);
        // Deposit into strategy
        mintAndDepositIntoStrategy(_strategy, user, _amount, _asset);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(_strategy, _amount, _amount, 0);

        // Earn Interest
        skip(20 days);
        vm.roll(block.number + 1);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = _strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(_strategy.profitMaxUnlockTime());

        uint256 balanceBefore = _asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        _strategy.redeem(_amount, user, user);

        assertGe(
            _asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }
}
