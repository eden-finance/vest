// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../src/vest/EdenVestCore.sol";
import "../src/vest/interfaces/IPoolFactory.sol";
import "../src/vest/NFTPositionManager.sol";

contract CreatePool is Script {
    function run() external {
        // env
        address edenCoreProxy = vm.envAddress("EDEN_CORE_PROXY");
        address cNGN          = vm.envAddress("CNGN_ADDRESS");
        address poolMultisig  = vm.envAddress("POOL_MULTISIG");
        address nftManager    = vm.envAddress("NFT_POSITION_MANAGER");
        uint256 pk            = vm.envUint("PRIVATE_KEY");
        address deployer      = vm.addr(pk);

address[] memory multisigSigners = new address[](3);
        multisigSigners[0] = vm.envOr("MULTISIG_SIGNER_1", deployer);
        multisigSigners[1] = vm.envOr("MULTISIG_SIGNER_2", deployer);
        multisigSigners[2] = vm.envOr("MULTISIG_SIGNER_3", deployer);

        vm.startBroadcast(pk);

        console.log("=== EdenVest: Creating Pool ===");
        console.log("Deployer        :", deployer);
        console.log("EdenCore Proxy  :", edenCoreProxy);
        console.log("cNGN            :", cNGN);
        console.log("Pool Multisig   :", poolMultisig);
        console.log("NFT Manager     :", nftManager);

        IPoolFactory.PoolParams memory poolParams = IPoolFactory.PoolParams({
            name: "Chowdeck group of companies 2",
            symbol: "CWD",
            admin: deployer,
            cNGN: cNGN,
            poolMultisig: poolMultisig,
            multisigSigners: multisigSigners,
            lockDuration: 40 minutes,
            minInvestment: 10_000e18,
            maxInvestment: 100_000e18,
            utilizationCap: 1_000_000e18,
            expectedRate: 5000, // 10% in bps
            taxRate: 0
        });

        EdenVestCore core = EdenVestCore(edenCoreProxy);
        address pool = core.createPool(poolParams);

        // Authorize pool in NFTPositionManager (caller must have DEFAULT_ADMIN_ROLE there)
        NFTPositionManager(nftManager).authorizePool(pool, true);

        vm.stopBroadcast();

        console.log("=== Pool Created Successfully ===");
        console.log("Pool Address    :", pool);
        console.log("Pool Name       :", poolParams.name);
        console.log("Lock (days)     :", poolParams.lockDuration / 1 days);
        console.log("Expected APY bps:", poolParams.expectedRate);
        console.log("Utilization Cap :", poolParams.utilizationCap / 1e18, "cNGN");
    }
}