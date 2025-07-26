// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IEdenCore {
    function globalTaxRate() external view returns (uint256);
    function taxCollector() external view returns (address);
}
