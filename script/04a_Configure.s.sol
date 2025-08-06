// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// Contract interfaces
import "../src/vest/EdenVestCore.sol";
import "../src/vest/PoolFactory.sol";
import "../src/vest/TaxCollector.sol";
import "../src/vest/InvestmentPool.sol";
import "../src/vest/LPToken.sol";

/**
 * @title Final Configuration
 * @notice Batch 4a: Configure all contracts to work together
 */
contract ConfigureScript is Script {
    function run() external {
        // Load all deployed addresses
        address edenCoreProxy = vm.envAddress("EDEN_CORE_PROXY");
        address edenAdmin = vm.envAddress("EDEN_ADMIN");
        address poolFactory = vm.envAddress("POOL_FACTORY");
        address taxCollector = vm.envAddress("TAX_COLLECTOR");
        address swapRouter = vm.envAddress("SWAP_ROUTER");
        address nftPositionManager = vm.envAddress("NFT_POSITION_MANAGER");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("=== EdenVest Batch 4: Final Configuration ===");

        // Configure EdenCore
        console.log("Configuring EdenVestCore...");
        EdenVestCore edenCore = EdenVestCore(edenCoreProxy);
        edenCore.setPoolFactory(poolFactory);
        edenCore.setTaxCollector(taxCollector);
        edenCore.setSwapRouter(swapRouter);
        edenCore.setNFTManager(nftPositionManager);
        edenCore.setEdenAdmin(edenAdmin);
        console.log("EdenVestCore configured");

        // Configure PoolFactory
        console.log("Configuring PoolFactory...");
        PoolFactory factory = PoolFactory(poolFactory);
        factory.setEdenCore(edenCoreProxy);
        factory.setTaxCollector(taxCollector);
        factory.setNFTManager(nftPositionManager);
        console.log("PoolFactory configured");

        // configure implementation contracts
        LPToken lptoken = new LPToken();
        InvestmentPool investmentPool = new InvestmentPool();

        factory.updateLPTokenImplementation(address(lptoken));
        factory.updatePoolImplementation(address(investmentPool));

        // Configure TaxCollector
        console.log("Configuring TaxCollector...");
        TaxCollector collector = TaxCollector(taxCollector);
        collector.setEdenCore(edenCoreProxy);
        console.log("TaxCollector configured");

        vm.stopBroadcast();

        // Final verification and summary
        _verifyAndSummarize();

        console.log("\n EdenVest Protocol Deployment COMPLETE!");
        console.log("Ready to create investment pools!");
    }

    function _verifyAndSummarize() internal view {
        console.log("\n=== FINAL DEPLOYMENT SUMMARY ===");
        console.log("EdenVestCore Proxy:", vm.envAddress("EDEN_CORE_PROXY"));
        console.log("EdenVestCore Implementation:", vm.envAddress("EDEN_CORE_IMPL"));
        console.log("EdenAdmin:", vm.envAddress("EDEN_ADMIN"));
        console.log("PoolFactory:", vm.envAddress("POOL_FACTORY"));
        console.log("TaxCollector:", vm.envAddress("TAX_COLLECTOR"));
        console.log("SwapRouter:", vm.envAddress("SWAP_ROUTER"));
        console.log("NFTPositionManager:", vm.envAddress("NFT_POSITION_MANAGER"));
        console.log("NFT Renderer:", vm.envAddress("NFT_RENDERER"));
        console.log("Pool Implementation:", vm.envAddress("POOL_IMPLEMENTATION"));
        console.log("LP Token Implementation:", vm.envAddress("LP_TOKEN_IMPLEMENTATION"));
    }
}
