// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core Contracts
import "../src/vest/EdenVestCore.sol";
import "../src/vest/EdenAdmin.sol";

// Proxy imports
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Deploy Proxy & Admin
 * @notice Batch 2: Deploy EdenCore proxy and EdenAdmin
 */
contract DeployProxyScript is Script {
    struct DeploymentConfig {
        address cNGN;
        address treasury;
        address admin;
        address[] multisigSigners;
        uint256 globalTaxRate;
    }

    function run() external {
        DeploymentConfig memory config = _getDeploymentConfig();

        // Get addresses from previous batch
        address edenCoreImpl = vm.envAddress("EDEN_CORE_IMPL");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== EdenVest Batch 2: Proxy & Admin ===");
        console.log("Using EdenCore Implementation:", edenCoreImpl);

        // Deploy EdenCore Proxy
        address edenCoreProxy = _deployEdenCoreProxy(edenCoreImpl, config);

        // Deploy EdenAdmin
        address edenAdmin = _deployEdenAdmin(edenCoreProxy, config);

        vm.stopBroadcast();

        // Save addresses
        _saveAddresses(edenCoreProxy, edenAdmin);

        console.log("\n=== BATCH 2 COMPLETE ===");
        console.log("EdenCore Proxy:", edenCoreProxy);
        console.log("EdenAdmin:", edenAdmin);
        console.log("\n Run Batch 3 next: forge script script/03_DeployFactory.s.sol");
    }

    function _deployEdenCoreProxy(address implementation, DeploymentConfig memory config) internal returns (address) {
        console.log("Deploying EdenCore Proxy...");

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            EdenVestCore.initialize.selector,
            config.cNGN,
            config.treasury,
            config.admin,
            config.globalTaxRate
        );

        // Deploy proxy
        ERC1967Proxy edenCoreProxy = new ERC1967Proxy(implementation, initData);

        console.log(" EdenCore Proxy deployed and initialized");
        return address(edenCoreProxy);
    }

    function _deployEdenAdmin(address edenCore, DeploymentConfig memory config) internal returns (address) {
        console.log("Deploying EdenAdmin...");

        EdenAdmin edenAdmin = new EdenAdmin(edenCore, config.admin, config.multisigSigners);

        console.log(" EdenAdmin deployed");
        return address(edenAdmin);
    }

    function _getDeploymentConfig() internal view returns (DeploymentConfig memory) {
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address[] memory signers = new address[](3);
        signers[0] = admin;
        signers[1] = vm.envOr("MULTISIG_SIGNER_2", admin);
        signers[2] = vm.envOr("MULTISIG_SIGNER_3", admin);

        return DeploymentConfig({
            cNGN: vm.envOr("CNGN_ADDRESS", address(0x1234567890123456789012345678901234567890)),
            treasury: vm.envOr("TREASURY_ADDRESS", admin),
            admin: admin,
            multisigSigners: signers,
            globalTaxRate: 250 // 2.5%
        });
    }

    function _saveAddresses(address edenCoreProxy, address edenAdmin) internal pure {
        console.log("\n=== BATCH 2 COMPLETE ===");
        console.log(string.concat("export EDEN_CORE_PROXY=", vm.toString(edenCoreProxy)));
        console.log(string.concat("export EDEN_ADMIN=", vm.toString(edenAdmin)));
    }
}
