// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/vest/PoolFactory.sol";
import "../src/vest/InvestmentPool.sol";
import "../src/vest/LPToken.sol";

/**
 * @title Deploy PoolFactory + Implementations
 * @notice Batch 3A: Deploy PoolFactory, InvestmentPool, LPToken and link them
 */
contract DeployPoolFactory is Script {
    function run() external {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== EdenVest Batch 3A: Deploying Factory + Implementations ===");

        // Step 1: Deploy Factory
        PoolFactory factory = new PoolFactory(admin);
        address poolFactory = address(factory);
        console.log("Deployed PoolFactory:", poolFactory);

        // Step 2: Deploy Implementations
        address poolImplementation = address(new InvestmentPool());
        address lpTokenImplementation = address(new LPToken());

        console.log("Deployed Pool Implementation:", poolImplementation);
        console.log("Deployed LP Token Implementation:", lpTokenImplementation);

        // Step 3: Set implementations on factory
        factory.updatePoolImplementation(poolImplementation);
        factory.updateLPTokenImplementation(lpTokenImplementation);

        vm.stopBroadcast();

        console.log("\n=== SAVE THESE ADDRESSES FOR NEXT BATCH ===");
        console.log(string.concat("export POOL_FACTORY=", vm.toString(poolFactory)));
        console.log(string.concat("export POOL_IMPLEMENTATION=", vm.toString(poolImplementation)));
        console.log(string.concat("export LP_TOKEN_IMPLEMENTATION=", vm.toString(lpTokenImplementation)));

        console.log("\n Batch 3A COMPLETE");
    }
}
