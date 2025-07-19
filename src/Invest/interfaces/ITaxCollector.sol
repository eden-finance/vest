// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ITaxCollector {
    function collectTax(address token, uint256 amount, address pool) external;
}
