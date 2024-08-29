// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IMasterPenpie {
    function multiclaim(address[] calldata _stakingTokens) external;
}
