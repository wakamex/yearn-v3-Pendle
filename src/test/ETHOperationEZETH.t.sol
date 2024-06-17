// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ETHOperationEZETHTest is OperationTest {
    function setUp() public override {
        //super.setUp();
        uint256 mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);
        oracle = 0x66a1096C6366b2529274dF4f5D8247827fe4CEA8;
        asset = ERC20(0xbf5495Efe5DB9ce00f80364C8B423567e58d2110); //ezETH
        //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> PT-eETH-27JUN24 /SY-weETH Market --> asset
        market = ERC20(0xD8F12bCDE578c653014F27379a6114F67F0e445f); //PT-ezETH-26 Dec 2024

        GOV = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;

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
