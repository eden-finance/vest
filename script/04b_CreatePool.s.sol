// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/vest/EdenVestCore.sol";
import "../src/vest/PoolFactory.sol";
import "../src/vest/TaxCollector.sol";
import "../src/vest/InvestmentPool.sol";
import "../src/vest/LPToken.sol";
import "../src/vest/interfaces/IPoolFactory.sol";

/**
 * @title Final Configuration
 * @notice Batch 4b: Create a pool
 */
contract CreatePool is Script {
    function run() external {
        address edenCoreProxy = vm.envAddress("EDEN_CORE_PROXY");
        address cNGN = vm.envAddress("CNGN_ADDRESS");

        address[] memory multisigSigners = new address[](3);
        address poolMultisig = vm.envAddress("POOL_MULTISIG");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        multisigSigners[0] = vm.envAddress("MULTISIG_SIGNER_1");
        multisigSigners[1] = vm.envAddress("MULTISIG_SIGNER_2");
        multisigSigners[2] = vm.envAddress("MULTISIG_SIGNER_3");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== EdenVest: Creating Pool ===");
        console.log("Pool Multisig:", poolMultisig);
        console.log("cNGN Address:", cNGN);
        console.log("Number of Multisig Signers:", multisigSigners.length);

        IPoolFactory.PoolParams memory poolParams = IPoolFactory.PoolParams({
            name: "Nigeria Money Market",
            symbol: "NMM",
            admin: vm.addr(deployerPrivateKey),
            cNGN: cNGN,
            poolMultisig: poolMultisig,
            multisigSigners: multisigSigners,
            lockDuration: 30 days,
            minInvestment: 1000e18, // 1,000 cNGN
            maxInvestment: 1000000e18, // 1,000,000 cNGN
            utilizationCap: 10000000e18, // 10,000,000 cNGN
            expectedRate: 2000, // 20% APY (in basis points)
            taxRate: 0 // No pool-specific tax, use global
        });

        EdenVestCore edenCore = EdenVestCore(edenCoreProxy);
        address pool = edenCore.createPool(poolParams);


        // TODO: authorize pool via nft position contract

        vm.stopBroadcast();

        console.log("=== Pool Created Successfully ===");
        console.log("Pool Address:", pool);
        console.log("Pool Name:", poolParams.name);
        console.log("Lock Duration:", poolParams.lockDuration / 1 days, "days");
        console.log("Expected APY:", poolParams.expectedRate / 100, "%");
        console.log("Utilization Cap:", poolParams.utilizationCap / 1e18, "cNGN");
    }
}
