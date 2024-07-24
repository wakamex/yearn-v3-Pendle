// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ARBOperationWSTETHTest is OperationTest {
    function setUp() public override {
        //super.setUp();
        uint256 arbitrumFork = vm.createFork("arbitrum");
        vm.selectFork(arbitrumFork);
        oracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        asset = ERC20(0x5979D7b546E38E414F7E9822514be443A4800529);
        //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> PT-wstETH-26JUN25/SY-wstETH Market --> asset
        market = ERC20(0x08a152834de126d2ef83D612ff36e4523FD0017F); //PT-wstETH-26JUN25/SY-wstETH Market
        //redeemToken from asset --> readTokens --> SY --> getTokensIn --> redeemToken
        redeemToken = 0x5979D7b546E38E414F7E9822514be443A4800529; //wstETH
        feeRedeemTokenToBase = 100;

        //chain specific:
        base = 0x5979D7b546E38E414F7E9822514be443A4800529;

        pendleStaking = 0x6DB96BBEB081d2a85E0954C252f2c1dC108b3f81; //https://docs.penpiexyz.io/smart-contracts --> Arbitrum --> PendleStaking
        GOV = 0x6Ba1734209a53a6E63C39D4e36612cc856A34D56;

        // Set decimals
        decimals = asset.decimals();
        strategyFactory = setUpStrategyFactory();
        // Deploy strategy and set variables
        vm.prank(management);
        strategy = IStrategyInterface(
            strategyFactory.newSingleSidedPTcore(
                address(asset),
                address(market),
                "Strategy"
            )
        );
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
