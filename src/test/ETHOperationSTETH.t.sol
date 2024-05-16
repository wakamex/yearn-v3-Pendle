// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ETHOperationWSTETHTest is OperationTest {
    function setUp() public override {
        //super.setUp();
        uint256 mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);
        oracle = 0x66a1096C6366b2529274dF4f5D8247827fe4CEA8;
        asset = ERC20(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84); //STETH
        //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> PT-stETH-25DEC25/SY-stETH Market --> asset
        market = ERC20(0xC374f7eC85F8C7DE3207a10bB1978bA104bdA3B2); //PT-stETH-25DEC25/SY-stETH Market
        //redeemToken from asset --> readTokens --> SY --> getTokensIn --> redeemToken
        redeemToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; //STETH
        //(0.01% = 100, 0.05% = 500, 0.3% = 3000, 1% = 10000)
        feeRedeemTokenToBase = 100;

        //PENDLE -3000-> WETH -500-> USDC -500-> crvUSD


        //ARB rewards:
        //additionalReward1 = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        //feeAdditionalReward1toBase = 500;

        //PNP rewards:
        //additionalReward2 = 0x2Ac2B254Bc18cD4999f64773a966E4f4869c34Ee;
        //feeAdditionalReward2toBase = 10000;
        
        //chain specific:
        base = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; //WSTETH
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
        strategy = IStrategyInterface(strategyFactory.newSingleSidedPTcore(address(asset), address(market), "Strategy"));
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
}
