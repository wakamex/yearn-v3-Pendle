// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ARBOperationAUSDCTest is OperationTest {
    function setUp() public override {
        //super.setUp();
        uint256 arbitrumFork = vm.createFork("arbitrum");
        vm.selectFork(arbitrumFork);
        oracle = 0x1Fd95db7B7C0067De8D45C0cb35D59796adfD187;

        asset = ERC20(0xaf88d065e77c8cC2239327C5EDb3A432268e5831); //USDC
        //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> PT-aUSDC-27JUN24/SY-aUSDC Market --> asset
        market = ERC20(0xBa4A858d664Ddb052158168DB04AFA3cFF5CFCC8); //PT-aUSDC-27JUN24/SY-aUSDC Market
        //redeemToken from asset --> readTokens --> SY --> getTokensIn --> redeemToken
        redeemToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; //USDC
        //(0.01% = 100, 0.05% = 500, 0.3% = 3000, 1% = 10000)
        feeRedeemTokenToBase = 500;

        maxFuzzAmount = 1e6 * 1e6;
        minFuzzAmount = 1e6;
        
        //chain specific:
        base = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        PENDLE = 0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8;
        feePENDLEtoBase = 3000;

        pendleStaking = 0x6DB96BBEB081d2a85E0954C252f2c1dC108b3f81; //https://docs.penpiexyz.io/smart-contracts --> Arbitrum --> PendleStaking
        GOV = 0x6Ba1734209a53a6E63C39D4e36612cc856A34D56;  
        
        // Set decimals
        decimals = asset.decimals();
        strategyFactory = setUpStrategyFactory();
        // Deploy strategy and set variables
        vm.prank(management);
        strategy = IStrategyInterface(strategyFactory.newSingleSidedPTcore(address(asset), address(market), "Strategy"));
        setUpStrategy();
        factory = strategy.FACTORY();

        vm.prank(management);
        strategy.setRouterParams(0, type(uint256).max, 256, 1e16);

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
