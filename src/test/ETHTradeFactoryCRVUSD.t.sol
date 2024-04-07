// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract TradeFactoryDummy {
    function enable(address tokenFrom, address tokenTo) public {
        console.log("ENABLE: ");
        console.log("tokenFrom: ", tokenFrom);
        console.log("tokenTo: ", tokenTo);
    }
}

contract ETHTradeFactoryCRVUSDTest is Setup {
    function setUp() public override {
        //super.setUp();
        uint256 mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

        //asset from https://docs.pendle.finance/Developers/Deployments/: PT-Silo-crvUSD-27JUN24/SY-Silo-crvUSD Market --> asset
        asset = ERC20(0xBBd395D4820da5C89A3bCA4FA28Af97254a0FCBe); //PT-Silo-crvUSD-27JUN24/SY-Silo-crvUSD Market
        //targetToken from asset --> readTokens --> SY --> getTokensIn --> targetToken
        targetToken = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; //CRVUSD
        //(0.01% = 100, 0.05% = 500, 0.3% = 3000, 1% = 10000)
        feeBaseToTargetToken = 500;
        
        //chain specific:
        base = 0xdAC17F958D2ee523a2206206994597C13D831ec7; //USDT
        PENDLE = 0x808507121B80c02388fAd14726482e061B8da827;
        //(0.01% = 100, 0.05% = 500, 0.3% = 3000, 1% = 10000)
        feePENDLEtoBase = 3000;

        pendleStaking = 0x6E799758CEE75DAe3d84e09D40dc416eCf713652; //https://docs.penpiexyz.io/smart-contracts --> Arbitrum --> PendleStaking
        GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;  
        
        // Set decimals
        decimals = asset.decimals();
        strategyFactory = setUpStrategyFactory();
        // Deploy strategy and set variables
        vm.prank(management);
        strategy = IStrategyInterface(strategyFactory.newPendleLPCompounder(address(asset), feePENDLEtoBase, base, feeBaseToTargetToken, targetToken, "Strategy"));
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

        function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_tradefactory() public {
        setFees(0, 0);
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
        console.log("assetBalance: ", strategy.balanceAsset());

        TradeFactoryDummy tradeFactoryDummy = new TradeFactoryDummy();
        vm.prank(GOV);
        strategy.setTradeFactory(address(tradeFactoryDummy), true);

        vm.prank(management);
        strategy.addReward(PENDLE, feePENDLEtoBase);

        address PNP = 0x7DEdBce5a2E31E4c75f87FeA60bF796C17718715;
        address SD = 0x30D20208d987713f46DFD34EF128Bb16C404D10f;
        vm.prank(management);
        strategy.addReward(PNP, feePENDLEtoBase); //PNP

        vm.prank(management);
        strategy.addReward(SD, feePENDLEtoBase); //SD

        // Earn Interest
        skip(12 days);

        console.log("PENDLE amount before claim: ", ERC20(PENDLE).balanceOf(address(strategy)));
        vm.prank(address(tradeFactoryDummy));
        strategy.claimRewards();
        console.log("PENDLE amount afterclaim: ", ERC20(PENDLE).balanceOf(address(strategy)));
        airdrop(ERC20(PENDLE), address(strategy), 10e18);
        airdrop(ERC20(PNP), address(strategy), 10e18);
        airdrop(ERC20(SD), address(strategy), 10e18);
        console.log("PENDLE amount after airdrop: ", ERC20(PENDLE).balanceOf(address(strategy)));
        console.log("PNP amount after airdrop: ", ERC20(PNP).balanceOf(address(strategy)));
        console.log("SD amount after airdrop: ", ERC20(SD).balanceOf(address(strategy)));
        vm.startPrank(address(tradeFactoryDummy));
        ERC20(PENDLE).transferFrom(address(strategy), address(tradeFactoryDummy), 10e18);
        ERC20(PNP).transferFrom(address(strategy), address(tradeFactoryDummy), 10e18);
        ERC20(SD).transferFrom(address(strategy), address(tradeFactoryDummy), 10e18);
        vm.stopPrank();
        console.log("PENDLE amount after transfer strategy: ", ERC20(PENDLE).balanceOf(address(strategy)));
        console.log("PENDLE amount after transfer tradefactory: ", ERC20(PENDLE).balanceOf(address(tradeFactoryDummy)));
        console.log("PNP amount after transfer strategy: ", ERC20(PNP).balanceOf(address(strategy)));
        console.log("PNP amount after transfer tradefactory: ", ERC20(PNP).balanceOf(address(tradeFactoryDummy)));
        console.log("SD amount after transfer strategy: ", ERC20(SD).balanceOf(address(strategy)));
        console.log("SD amount after transfer tradefactory: ", ERC20(SD).balanceOf(address(tradeFactoryDummy)));
        //airdrop(ERC20(targetToken), address(strategy), 10e18);
        airdrop(asset, address(strategy), 10e18);
        
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit);
        console.log("loss: ", loss);
        assertGt(profit, 0, "!profit");
        assertEq(loss, 0, "!loss");

        checkStrategyInvariants(strategy);

        skip(strategy.profitMaxUnlockTime());

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
        checkStrategyTotals(strategy, 0, 0, 0);
    }
}
