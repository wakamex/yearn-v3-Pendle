// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IMasterPenpie { 
    function multiclaimSpecPNP(address[] calldata _stakingTokens, address[][] calldata _rewardTokens, bool _withPNP) external;
}