// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MainTest is Setup {

    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_main() public {
        //init
        uint256 _amount = 100e18;
        uint256 profit;
        uint256 loss;
        console.log("asset: ", asset.symbol());
        console.log("amount:", _amount);
        //user funds:
        airdrop(asset, user, _amount);
        console.log("airdrop done");
        assertEq(asset.balanceOf(user), _amount, "!totalAssets");
        //user deposit:
        depositIntoStrategy(strategy, user, _amount);
        console.log("deposit done");
        assertEq(asset.balanceOf(user), 0, "user balance after deposit =! 0");
        assertEq(strategy.totalAssets(), _amount, "strategy.totalAssets() != _amount after deposit");
        console.log("strategy.totalAssets() after deposit: ", strategy.totalAssets());
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt());
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle());
        console.log("assetBalance: ", strategy.balanceAsset());

        // Earn Interest
        skip(12 days);

        airdrop(ERC20(PENDLE), address(strategy), 10e18);
        airdrop(ERC20(additionalReward1), address(strategy), 10e18);
        airdrop(ERC20(additionalReward2), address(strategy), 10e18);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);
        checkStrategyInvariants(strategy);

        airdrop(ERC20(PENDLE), address(strategy), 10e18);
        airdrop(ERC20(additionalReward1), address(strategy), 10e18);
        airdrop(ERC20(additionalReward2), address(strategy), 10e18);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        checkStrategyInvariants(strategy);

        airdrop(ERC20(PENDLE), address(strategy), 10e18);
        airdrop(ERC20(additionalReward1), address(strategy), 10e18);
        airdrop(ERC20(additionalReward2), address(strategy), 10e18);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        checkStrategyInvariants(strategy);

        airdrop(ERC20(PENDLE), address(strategy), 10e18);
        airdrop(ERC20(additionalReward1), address(strategy), 10e18);
        airdrop(ERC20(additionalReward2), address(strategy), 10e18);

        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        checkStrategyInvariants(strategy);

        skip(strategy.profitMaxUnlockTime());

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console.log("redeem strategy.totalAssets() after deposit: ", strategy.totalAssets());
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt());
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle());

        checkStrategyInvariants(strategy);
        
        console.log("assetBalance: ", strategy.balanceAsset());
        console.log("asset.balanceOf(user): ", asset.balanceOf(user));
    }
/*
    function test_main_profitableReport_withMutipleUsers(uint256 _amount, uint16 _divider, uint16 _secondDivider) public {
        setPerformanceFeeToZero(address(strategy));
        uint256 maxDivider = 100000;
        vm.assume(_amount > minFuzzAmount * maxDivider && _amount < maxFuzzAmount);
        // vm.assume(_profit > minFuzzAmount * maxDivider && _profit < maxFuzzAmount);
        vm.assume(_divider > 0 && _divider < maxDivider);
        vm.assume(_secondDivider > 0 && _secondDivider < maxDivider);

        // profit must be below 100%
        uint256 _profit = _amount / 10;
        address secondUser = address(22);
        address thirdUser = address(33);
        uint256 secondUserAmount = _amount / _divider;
        uint256 thirdUserAmount = _amount / _secondDivider;

        mintAndDepositIntoStrategy(strategy, user, _amount);
        mintAndDepositIntoStrategy(strategy, secondUser, secondUserAmount);
        mintAndDepositIntoStrategy(strategy, thirdUser, thirdUserAmount);

        // DONE: Implement logic so totalDebt is _amount and totalIdle = 0.
        uint256 strategyTotal = _amount + secondUserAmount + thirdUserAmount;
        checkStrategyTotals(strategy, strategyTotal, strategyTotal, 0);

        // Earn Interest
        skip(1 days);
        // drop some addtional profit
        airdrop(ERC20(PENDLE), address(strategy), _profit);
        airdrop(ERC20(additionalReward1), address(strategy), _profit);
        airdrop(ERC20(additionalReward2), address(strategy), _profit);
        airdrop(asset, address(strategy), _profit);

        // DONE: implement logic to simulate earning interest.
        skip(30 days);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // Check return Values
        assertGe(profit, _profit, "!profit"); // profit should be at least airdrop amount
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        //withdraw part of the funds
        vm.prank(user);
        strategy.redeem(_amount / 8, user, user);
        vm.prank(secondUser);
        strategy.redeem(secondUserAmount / 6, secondUser, secondUser);
        vm.prank(thirdUser);
        strategy.redeem(thirdUserAmount / 4, thirdUser, thirdUser);

        // Skip some time, this will earn some profit
        skip(3 days);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();

        // Check return Values
        assertGe(profit, 0, "!profit"); // no airdrop so profit can be mininmal
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // withdraw all funds
        console.log("user shares: ", strategy.balanceOf(user));
        console.log("user2 shares: ", strategy.balanceOf(secondUser));
        console.log("user3 shares: ", strategy.balanceOf(thirdUser));
        uint redeemAmount = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(redeemAmount, user, user);
        redeemAmount = strategy.balanceOf(secondUser);
        vm.prank(secondUser);
        strategy.redeem(redeemAmount, secondUser, secondUser);
        redeemAmount = strategy.balanceOf(thirdUser);
        vm.prank(thirdUser);
        strategy.redeem(redeemAmount, thirdUser, thirdUser);
        // verify users earned profit
        assertGt(asset.balanceOf(user), _amount, "!final balance");
        assertGt(asset.balanceOf(secondUser), secondUserAmount, "!final balance");
        assertGt(asset.balanceOf(thirdUser), thirdUserAmount, "!final balance");

        // verify vault is empty
        checkStrategyTotals(strategy, 0, 0, 0);
    }
*/
}


