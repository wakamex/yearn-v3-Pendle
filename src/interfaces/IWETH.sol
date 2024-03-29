// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

interface IWETH {
    function withdraw(uint256) external;
    function deposit() external payable;
}
