// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Core Contracts
import "../src/vest/EdenVestCore.sol";
import "../src/vest/TaxCollector.sol";
import "../src/vest/SwapRouter.sol";
import "../src/EdenPoolNFT.sol";

// Proxy imports
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Deploy Core Infrastructure
 * @notice Batch 1: Deploy lightweight core contracts
 */
contract DeployCoreScript is Script {
    struct DeploymentConfig {
        address cNGN;
        address treasury;
        address admin;
        uint256 globalTaxRate;
        address uniswapRouter;
        address uniswapQuoter;
    }

    function run() external {
        DeploymentConfig memory config = _getDeploymentConfig();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== EdenVest Batch 1: Core Infrastructure ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Chain ID:", block.chainid);

        // Deploy core infrastructure
        address nftRenderer = _deployEdenPoolNFT();
        address taxCollector = _deployTaxCollector(config);
        address swapRouter = _deploySwapRouter(config);

        // Deploy EdenCore (implementation only)
        address edenCoreImpl = _deployEdenCoreImplementation();

        vm.stopBroadcast();

        // Save addresses to environment file
        _saveAddresses(nftRenderer, taxCollector, swapRouter, edenCoreImpl);

        console.log("\n=== BATCH 1 COMPLETE ===");
        console.log("NFT Renderer:", nftRenderer);
        console.log("TaxCollector:", taxCollector);
        console.log("SwapRouter:", swapRouter);
        console.log("EdenCore Implementation:", edenCoreImpl);
        console.log("\n Run Batch 2 next: forge script script/02_DeployProxy.s.sol");
    }

    function _deployEdenPoolNFT() internal returns (address) {
        console.log("Deploying EdenPoolNFT...");
        EdenPoolNFT renderer = new EdenPoolNFT();
        console.log(" EdenPoolNFT deployed");
        return address(renderer);
    }

    function _deployTaxCollector(DeploymentConfig memory config) internal returns (address) {
        console.log("Deploying TaxCollector...");
        TaxCollector taxCollector = new TaxCollector(
            config.treasury,
            config.admin,
            address(0) // Will be set later
        );
        console.log(" TaxCollector deployed");
        return address(taxCollector);
    }

    function _deploySwapRouter(DeploymentConfig memory config) internal returns (address) {
        console.log("Deploying SwapRouter...");
        SwapRouter swapRouter = new SwapRouter(config.uniswapRouter, config.uniswapQuoter, config.admin);
        console.log(" SwapRouter deployed");
        return address(swapRouter);
    }

    function _deployEdenCoreImplementation() internal returns (address) {
        console.log("Deploying EdenVestCore Implementation...");
        EdenVestCore edenCoreImpl = new EdenVestCore();
        console.log(" EdenVestCore Implementation deployed");
        return address(edenCoreImpl);
    }

    function _getDeploymentConfig() internal view returns (DeploymentConfig memory) {
        address admin = vm.envAddress("ADMIN_ADDRESS");

        return DeploymentConfig({
            cNGN: vm.envOr("CNGN_ADDRESS", address(0x5CDDBeBAc2260CF00654887184d6BA31096fE0a5)),
            treasury: vm.envOr("TREASURY_ADDRESS", admin),
            admin: admin,
            globalTaxRate: 250,
            uniswapRouter: vm.envOr("UNISWAP_ROUTER", address(0x365C8Bd36a27128A230B1CE8f7027d7a9e5A8f82)),
            uniswapQuoter: vm.envOr("UNISWAP_QUOTER", address(0x740aC3204dB2AA93cd7D5a320e8374Ef63d24dbf))
        });
    }

    function _saveAddresses(address nftRenderer, address taxCollector, address swapRouter, address edenCoreImpl)
        internal
    {
        // Save to a simple format that can be read by next scripts
        console.log("\n=== SAVE THESE ADDRESSES FOR NEXT BATCH ===");
        console.log(string.concat("NFT_RENDERER=", vm.toString(nftRenderer)));
        console.log(string.concat("TAX_COLLECTOR=", vm.toString(taxCollector)));
        console.log(string.concat("SWAP_ROUTER=", vm.toString(swapRouter)));
        console.log(string.concat("EDEN_CORE_IMPL=", vm.toString(edenCoreImpl)));
    }
}
