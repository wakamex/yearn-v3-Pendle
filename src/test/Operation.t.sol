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
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation_NoFees(uint256 _amount) public {
        setPerformanceFeeToZero(address(strategy));
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(10 days);
        airdrop(ERC20(PENDLE), address(strategy), 100e18);
        if (additionalReward1 != address(0)) {
            airdrop(ERC20(additionalReward1), address(strategy), 100e18);
        }
        if (additionalReward2 != address(0)) {
            airdrop(ERC20(additionalReward2), address(strategy), 100e18);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // TODO: Adjust if there are fees
        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    function test_profitableReport_expectedFees(
        uint256 _amount,
        uint256 _profit
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        //_profitFactor = uint16(bound(uint256(_profitFactor), 10, 1_00));
        //_profit = uint16(bound(uint256(_profit), 1e10, 10000e18));
        _profit = bound(_profit, 1e15, 10000e18);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        //uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        //airdrop(asset, address(strategy), toAirdrop);
        airdrop(ERC20(PENDLE), address(strategy), _profit);
        if (additionalReward1 != address(0)) {
        airdrop(ERC20(additionalReward1), address(strategy), _profit);
        }
        if (additionalReward2 != address(0)) {
        airdrop(ERC20(additionalReward2), address(strategy), _profit);
        }

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        //assertGe(profit, toAirdrop, "!profit");
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        console.log("BEFORE USER REDEEM", strategy.totalAssets());
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console.log("AFTER USER REDEEM", strategy.totalAssets());

        //uint256 expectedFees = (profit * strategy.performanceFee()) / MAX_BPS;

        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        uint256 strategistShares = strategy.balanceOf(performanceFeeRecipient);
        // empty complete strategy
        console.log("BEFORE STRATEGIST REDEEM", strategy.totalAssets());
        vm.prank(performanceFeeRecipient);
        strategy.redeem(strategistShares, performanceFeeRecipient, performanceFeeRecipient);
        console.log("AFTER STRATEGIST REDEEM", strategy.totalAssets());
        assertGt(asset.balanceOf(performanceFeeRecipient), 0, "fees too low!");
    }

    function test_profitableReport_expectedShares(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));

        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariants(strategy);

        // Check return Values
        assertGe(profit, toAirdrop, "!profit");
        assertEq(loss, 0, "!loss");

        skip(strategy.profitMaxUnlockTime());

        // Get the expected fee
        uint256 expectedShares = (profit * 1_000) / MAX_BPS;

        assertEq(strategy.balanceOf(performanceFeeRecipient), expectedShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // TODO: Adjust if there are fees
        assertGe(asset.balanceOf(user), balanceBefore + _amount, "!final balance");

        vm.prank(performanceFeeRecipient);
        strategy.redeem(expectedShares, performanceFeeRecipient, performanceFeeRecipient);

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(performanceFeeRecipient), expectedShares, "!perf fee out");
    }

    function test_emergencyWithdrawAll(uint256 _amount) public {
        setPerformanceFeeToZero(address(strategy));
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Skip some time
        skip(15 days);
        airdrop(ERC20(PENDLE), address(strategy), 100e18);
        if (additionalReward1 != address(0)) {
            airdrop(ERC20(additionalReward1), address(strategy), 100e18);
        }
        if (additionalReward2 != address(0)) {
            airdrop(ERC20(additionalReward2), address(strategy), 100e18);
        }

        vm.prank(keeper);
        (uint profit, uint loss) = strategy.report();
        checkStrategyInvariants(strategy);
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        vm.prank(management);
        strategy.shutdownStrategy();
        vm.prank(management); 
        strategy.emergencyWithdraw(type(uint256).max);
        assertGe(asset.balanceOf(address(strategy)), _amount, "!all in asset");
        vm.prank(management);
        strategy.setAutocompound(false);

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        assertEq(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        vm.prank(user);
        strategy.redeem(_amount, user, user);
        // verify users earned profit
        assertGt(asset.balanceOf(user), _amount, "!final balance");

        checkStrategyTotals(strategy, 0, 0, 0);
    }
}