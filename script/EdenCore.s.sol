// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/vest/EdenCore.sol";
import "../src/vest/PoolFactory.sol";
import "../src/vest/TaxCollector.sol";
import "../src/vest/SwapRouter.sol";
import "../src/vest/NFTPositionManager.sol";
import "../src/EdenPoolNFT.sol";

contract DeployEdenCoreScript is Script {
    // Configuration
    struct DeploymentConfig {
        address admin;
        address treasury;
        address cNGN;
        address uniswapRouter;
        address uniswapQuoter;
        uint256 globalTaxRate;
        // First pool config
        string poolName;
        string poolSymbol;
        address poolMultisig;
        address[] multisigSigners;
        uint256 lockDuration;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 utilizationCap;
        uint256 expectedRate;
        uint256 poolTaxRate;
    }

    function getConfig() public view returns (DeploymentConfig memory) {
        // Default configuration
        address[] memory signers = new address[](3);
        signers[0] = 0x54527B09Aeb2Be23F99958Db8f2f827daB863A28;
        signers[1] = 0x54527B09Aeb2Be23F99958Db8f2f827daB863A28;
        signers[2] = 0x54527B09Aeb2Be23F99958Db8f2f827daB863A28;

        return DeploymentConfig({
            admin: msg.sender,
            treasury: 0x54527B09Aeb2Be23F99958Db8f2f827daB863A28, // Replace
            cNGN: 0x5678901234567890123456789012345678901234, // Replace
            uniswapRouter: 0x365C8Bd36a27128A230B1CE8f7027d7a9e5A8f82, // Replace
            uniswapQuoter: 0x740aC3204dB2AA93cd7D5a320e8374Ef63d24dbf, // Replace
            globalTaxRate: 1000, // 2.0%
            poolName: "Nigerian Money Market",
            poolSymbol: "NMM",
            poolMultisig: 0x54527B09Aeb2Be23F99958Db8f2f827daB863A28, // Replace
            multisigSigners: signers,
            lockDuration: 30 days,
            minInvestment: 1000e18,
            maxInvestment: 10_000_000e18,
            utilizationCap: 100_000_000e18,
            expectedRate: 2100, // 21% APY
            poolTaxRate: 0 // Use global rate
        });
    }

    function run() external {
        DeploymentConfig memory config = getConfig();

        vm.startBroadcast();

        // 1. Deploy NFT Renderer
        EdenPoolNFT renderer = new EdenPoolNFT();
        console.log("EdenPoolNFT Renderer deployed at:", address(renderer));

        // 2. Deploy NFT Position Manager
        NFTPositionManager nftManager = new NFTPositionManager(address(renderer), config.admin);
        console.log("NFT Position Manager deployed at:", address(nftManager));

        // 3. Deploy Tax Collector
        TaxCollector taxCollector = new TaxCollector(config.treasury, config.admin);
        console.log("Tax Collector deployed at:", address(taxCollector));

        // 4. Deploy Swap Router
        SwapRouter swapRouter = new SwapRouter(config.uniswapRouter, config.uniswapQuoter, config.admin);
        console.log("Swap Router deployed at:", address(swapRouter));

        // 5. Deploy Pool Factory
        PoolFactory poolFactory = new PoolFactory(config.admin);
        console.log("Pool Factory deployed at:", address(poolFactory));

        // 6. Deploy Eden Core
        EdenCore edenCore = new EdenCore();
        console.log("Eden Core deployed at:", address(edenCore));

        // 7. Initialize Eden Core
        edenCore.initialize(config.cNGN, config.treasury, config.admin, config.globalTaxRate);

        // 8. Set contract connections
        poolFactory.setEdenCore(address(edenCore));
        poolFactory.setNFTManager(address(nftManager));

        edenCore.setPoolFactory(address(poolFactory));
        edenCore.setTaxCollector(address(taxCollector));
        edenCore.setSwapRouter(address(swapRouter));
        edenCore.setNFTManager(address(nftManager));

        // 9. Grant pool creator role
        edenCore.grantRole(edenCore.POOL_CREATOR_ROLE(), config.admin);
        edenCore.grantRole(edenCore.MINTER_ROLE(), config.admin);

        // 10. Create first pool (Nigerian Money Market)
        IPoolFactory.PoolParams memory poolParams = IPoolFactory.PoolParams({
            name: config.poolName,
            symbol: config.poolSymbol,
            admin: config.admin,
            cNGN: config.cNGN,
            poolMultisig: config.poolMultisig,
            multisigSigners: config.multisigSigners,
            lockDuration: config.lockDuration,
            minInvestment: config.minInvestment,
            maxInvestment: config.maxInvestment,
            utilizationCap: config.utilizationCap,
            expectedRate: config.expectedRate,
            taxRate: config.poolTaxRate
        });

        address firstPool = edenCore.createPool(poolParams);
        console.log("First Pool (Nigerian Money Market) created at:", firstPool);

        // 11. Authorize pool in NFT Manager
        nftManager.authorizePool(firstPool, true);

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("Eden Core:", address(edenCore));
        console.log("Pool Factory:", address(poolFactory));
        console.log("Tax Collector:", address(taxCollector));
        console.log("Swap Router:", address(swapRouter));
        console.log("NFT Manager:", address(nftManager));
        console.log("NFT Renderer:", address(renderer));
        console.log("First Pool:", firstPool);
        console.log("Admin:", config.admin);
        console.log("Treasury:", config.treasury);
    }
}
