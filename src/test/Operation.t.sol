// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OperationTest is Setup {
    function setUp() public virtual override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation_NoFees(uint256 _amount /*, uint8 _profitFactor*/) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint8 _profitFactor = 2_00;
        //_profitFactor = uint8(bound(uint256(_profitFactor), 100, 5_00));
        setFees(0, 0);
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        // Earn Interest
        skip(1 days);
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop: ", toAirdrop);
        airdrop(asset, address(strategy), toAirdrop);
        

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);

        console.log("profit: ", profit);
        console.log("loss: ", loss);

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), (balanceBefore + _amount) * expectedMaxLossBPS / MAX_BPS, "!final balance");
        assertEq(strategy.totalAssets(), 0, "not 0 at end!");
    }

    function test_profitableReport_expectedFees(
        uint256 _amount
        /* ,uint8 _profitFactor*/
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint8 _profitFactor = 2_00;
        //_profitFactor = uint8(bound(uint256(_profitFactor), 100, 1_00));
        uint256 profit;
        uint256 loss;
        //_profit = uint16(bound(uint256(_profit), 1e10, 10000e18));
        //_profit = bound(_profit, 1e15, 1000e18);
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Earn Interest
        skip(1 days);

        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);
        
        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, toAirdrop * 90_00 / MAX_BPS, "!profit");
        if (forceProfit == false) {
            assertGt(profit, 0, "!profit");
        }
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        console.log("BEFORE USER REDEEM", strategy.totalAssets());
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console.log("AFTER USER REDEEM", strategy.totalAssets());

        //uint256 expectedFees = (profit * strategy.performanceFee()) / MAX_BPS;

        assertGe(asset.balanceOf(user), (balanceBefore + _amount) * expectedMaxLossBPS / MAX_BPS, "!final balance");

        uint256 strategistShares = strategy.balanceOf(performanceFeeRecipient);
        if (strategistShares > 0) {
            // empty complete strategy
            vm.prank(performanceFeeRecipient);
            strategy.redeem(strategistShares, performanceFeeRecipient, performanceFeeRecipient);
            assertGt(asset.balanceOf(performanceFeeRecipient), 0, "fees too low!");
        }

        assertEq(strategy.totalAssets(), 0, "not 0 at end!");
    }

    function test_profitableReport_expectedProfit(
        uint256 _amount
        /* ,uint8 _profitFactor*/
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint8 _profitFactor = 2_00;
        //_profitFactor = uint8(bound(uint256(_profitFactor), 1_00, 20_00));
        uint256 profit;
        uint256 loss;
        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);
        
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);
        console.log("toAirdrop: ", toAirdrop);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);
        
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, toAirdrop * expectedMaxLossBPS / MAX_BPS, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected profit
        uint256 expectedProfit = (profit * 1_000) / MAX_BPS;
        uint256 balanceBefore = asset.balanceOf(user);
        
        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertGe(asset.balanceOf(user), (balanceBefore + _amount) * expectedMaxLossBPS / MAX_BPS, "!final balance");

        uint256 shares = strategy.balanceOf(performanceFeeRecipient);
        vm.prank(performanceFeeRecipient);
        strategy.redeem(shares, performanceFeeRecipient, performanceFeeRecipient);
        assertGe(asset.balanceOf(performanceFeeRecipient), expectedProfit * expectedMaxLossBPS / MAX_BPS, "!perf fee out");

        assertEq(strategy.totalAssets(), 0, "not 0 at end!");
    }

    function test_emergencyWithdrawAll(uint256 _amount /* ,uint8 _profitFactor*/) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint8 _profitFactor = 2_00;
        //_profitFactor = uint8(bound(uint256(_profitFactor), 100, MAX_BPS));
        setFees(0, 0);
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Skip some time
        skip(1 days);
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);
        console.log("toAirdrop: ", toAirdrop);

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariants(strategy);
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        vm.prank(management);
        strategy.shutdownStrategy();
        vm.prank(management); 
        strategy.emergencyWithdraw(type(uint256).max);
        assertGe(asset.balanceOf(address(strategy)), (_amount + toAirdrop) * expectedMaxLossBPS / MAX_BPS, "!all in asset");
        checkStrategyInvariants(strategy);

        vm.prank(management);
        strategy.setDoHealthCheck(false);

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        assertGt(_amount * 5_00 / MAX_BPS, 0, "!loss");

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        vm.prank(user);
        strategy.redeem(_amount, user, user);
        // verify users earned profit
        assertGt(asset.balanceOf(user), _amount * expectedMaxLossBPS / MAX_BPS, "!final balance");

        assertEq(strategy.totalAssets(), 0, "not 0 at end!");
    }
}