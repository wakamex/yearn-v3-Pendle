// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ETHOperationSDAITest is OperationTest {
    function setUp() public override {
        //super.setUp();
        uint256 mainnetFork = vm.createFork("mainnet");
        vm.selectFork(mainnetFork);
        oracle = 0x66a1096C6366b2529274dF4f5D8247827fe4CEA8;
        asset = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F); //ezETH
        //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> PT-eETH-27JUN24 /SY-weETH Market --> asset
        market = ERC20(0x93a82F3873e5b4fF81902663C43286d662F6721C); //PT-ezETH-26 Dec 2024

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
