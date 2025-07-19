// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IPoolFactory {
    struct PoolParams {
        string name;
        string symbol;
        address admin;
        address cNGN;
        address poolMultisig;
        address[] multisigSigners;
        uint256 lockDuration;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 utilizationCap;
        uint256 expectedRate;
        uint256 taxRate;
    }

    event PoolCreated(address indexed pool, string name, address admin, address lpToken);

    function createPool(PoolParams memory params) external returns (address pool);
}
