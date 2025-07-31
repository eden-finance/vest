// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ITaxCollector {
    function collectTax(address token, address pool, uint256 amount) external;
    function setEdenCore(address _edenCore) external;
}
