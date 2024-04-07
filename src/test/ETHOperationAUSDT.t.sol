// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ETHOperationAUSDTTest is OperationTest {
    function setUp() public override {
        //super.setUp();
        uint256 mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);

        //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> aUSDT Pool26 Sep 2024  --> asset
        asset = ERC20(0xb8FBF5cC2826c1C9909f59DD11633b494f46FBfe); //aUSDT Pool26 Sep 2024 
        //targetToken from asset --> readTokens --> SY --> getTokensIn --> targetToken
        targetToken = 0xdAC17F958D2ee523a2206206994597C13D831ec7; //USDT
        //(0.01% = 100, 0.05% = 500, 0.3% = 3000, 1% = 10000)
        feeBaseToTargetToken = 500;

        //PENDLE -3000-> WETH -500-> USDC -500-> crvUSD


        //ARB rewards:
        //additionalReward1 = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        //feeAdditionalReward1toBase = 500;

        //PNP rewards:
        //additionalReward2 = 0x2Ac2B254Bc18cD4999f64773a966E4f4869c34Ee;
        //feeAdditionalReward2toBase = 10000;
        
        //chain specific:
        base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //WETH
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

        vm.prank(management);
        strategy.setRouterParams(0, type(uint256).max, 256, 1e16);
        
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
}
