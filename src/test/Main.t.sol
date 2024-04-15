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
        setFees(0, 0);
        //init
        uint256 _amount = 1e18;
        uint256 profit;
        uint256 loss;
        uint256 _profitFactor = 10_00;
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
        console.log("assetBalance: ", strategy.balanceAsset());

        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);
        checkStrategyInvariants(strategy);

        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop: ", toAirdrop);
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        checkStrategyInvariants(strategy);

        toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop: ", toAirdrop);
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        checkStrategyInvariants(strategy);

        skip(strategy.profitMaxUnlockTime());

        // Withdraw all funds
        console.log("performanceFeeReceipient: ", strategy.balanceOf(performanceFeeRecipient));
        console.log("redeem strategy.totalAssets() before redeem: ", strategy.totalAssets());
        console.log("totalSupply before redeem: ", strategy.totalSupply());
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console.log("redeem strategy.totalAssets() after redeem: ", strategy.totalAssets());

        checkStrategyInvariants(strategy);
        
        console.log("assetBalance of strategy: ", strategy.balanceAsset());
        console.log("asset balance of strategy: ", asset.balanceOf(address(strategy)));
        console.log("asset.balanceOf(user) at end: ", asset.balanceOf(user));

        assertEq(strategy.totalAssets(), 0, "not 0 at end!");
    }
    
    function test_withdraw_after_expiry() public {
        setFees(0, 0);
        //init
        uint256 _amount = 10e18;
        uint256 profit;
        uint256 loss;
        uint256 _profitFactor = 10_00;
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
        console.log("assetBalance: ", strategy.balanceAsset());

        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop: ", toAirdrop);
        airdrop(asset, address(strategy), toAirdrop);

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);

        checkStrategyInvariants(strategy);

        skip(strategy.profitMaxUnlockTime());

        skip(10000 days);

        // Withdraw all funds
        console.log("performanceFeeReceipient: ", strategy.balanceOf(performanceFeeRecipient));
        console.log("redeem strategy.totalAssets() before redeem: ", strategy.totalAssets());
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console.log("redeem strategy.totalAssets() after redeem: ", strategy.totalAssets());

        checkStrategyInvariants(strategy);
        
        console.log("assetBalance of strategy: ", strategy.balanceAsset());
        console.log("asset balance of strategy: ", asset.balanceOf(address(strategy)));
        console.log("asset.balanceOf(user) at end: ", asset.balanceOf(user));
    }
    
}


