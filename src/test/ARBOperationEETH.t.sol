// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ARBOperationEETHTest is OperationTest {
    function setUp() public override {
        //super.setUp();
        uint256 arbitrumFork = vm.createFork("arbitrum");
        vm.selectFork(arbitrumFork);
        oracle = 0x1Fd95db7B7C0067De8D45C0cb35D59796adfD187;
        asset = ERC20(0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe); //WEETH
        //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> PT-wstETH-26JUN25/SY-wstETH Market --> asset
        market = ERC20(0x952083cde7aaa11AB8449057F7de23A970AA8472); //PT-wstETH-26JUN25/SY-wstETH Market
        //redeemToken from asset --> readTokens --> SY --> getTokensIn --> redeemToken
        redeemToken = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe; //WEETH
        feeRedeemTokenToBase = 100;
        feeRedeemTokenToBase = 100;
        feeBaseToAsset = 100;

        //ARB rewards:
        additionalReward1 = 0x912CE59144191C1204E64559FE8253a0e49E6548;
        feeAdditionalReward1toBase = 500;

        //PNP rewards:
        additionalReward2 = 0x2Ac2B254Bc18cD4999f64773a966E4f4869c34Ee;
        feeAdditionalReward2toBase = 10000;
        
        //chain specific:
        base = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe;
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
