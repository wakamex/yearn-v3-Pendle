// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ARBOperationMPENDLETest is OperationTest {
    function setUp() public override {
        //super.setUp();
        uint256 arbitrumFork = vm.createFork("arbitrum");
        vm.selectFork(arbitrumFork);
        oracle = 0x9a9Fa8338dd5E5B2188006f1Cd2Ef26d921650C2;
        asset = ERC20(0xB688BA096b7Bb75d7841e47163Cd12D18B36A5bF); //ezETH
        //asset from https://docs.pendle.finance/Developers/Deployments/: Markets --> PT-eETH-27JUN24 /SY-weETH Market --> asset
        market = ERC20(0xf617792eA9Dceb2208F4C440258B21d2f3FdB9A3); //PT-ezETH-26 Dec 2024

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
