// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {OperationTest} from "./Operation.t.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IMasterChef} from "../interfaces/IMasterChef.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract OperationWMATICMATIXTest is OperationTest {
    address public constant masterchef = 0x20ec0d06F447d550fC6edee42121bc8C1817b97D;
    function setUp() public override {
        //super.setUp();
        _setTokenAddrs();
        asset = ERC20(tokenAddrs["WMATIC-MATICX-LP"]);        
        address NATIVE = tokenAddrs["WMATIC"];
        uint256 PID = getPID(address(asset));
        // Set decimals
        decimals = asset.decimals();
        strategyFactory = setUpStrategyFactory();

        // Deploy strategy and set variables
        strategy = IStrategyInterface(strategyFactory.newGammaLPCompounder(address(asset), PID, NATIVE, "Strategy"));
        setUpStrategy();
        factory = strategy.FACTORY();

        //REWARDS:
        vm.prank(management);
        strategy.addReward(tokenAddrs["WMATIC"]);
        vm.prank(management);
        strategy.addReward(tokenAddrs["SD"]);
        vm.prank(management);
        route.push(tokenAddrs["USDC"]);
        strategy.setMidRouteRewardToNative(tokenAddrs["SD"], route);
    }

    function getPID(address _asset) public view returns (uint256 _PID) {
        uint256 length = IMasterChef(masterchef).poolLength();
        address tokenAddress;
        for (uint256 i; i < length; ++i) {
            tokenAddress = IMasterChef(masterchef).lpToken(i);
            if (tokenAddress == _asset) {
                _PID = i;
                break;
            }
        }
    }
}
