// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

interface IGamma {
    function getDepositAmount(address pos, address token, uint _deposit) external view returns (uint amountStart, uint amountEnd);
    function deposit(uint deposit0, uint deposit1, address to, address pos, uint[4] memory minIn) external returns (uint shares);
}