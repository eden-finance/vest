// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/vest/NFTPositionManager.sol";

/**
 * @title Deploy NFTPositionManager
 * @notice Batch 3B: Deploy NFTPositionManager only
 */
contract DeployNFTPositionManager is Script {
    function run() external {
        address renderer = vm.envAddress("NFT_RENDERER");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== EdenVest Batch 3B: Deploying NFTPositionManager ===");
        NFTPositionManager manager = new NFTPositionManager(renderer, admin);
        address nftPositionManager = address(manager);

        vm.stopBroadcast();

        console.log("\n=== SAVE THIS ADDRESS FOR NEXT BATCH ===");
        console.log(string.concat("export NFT_POSITION_MANAGER=", vm.toString(nftPositionManager)));
        console.log("NFTPositionManager:", nftPositionManager);
    }
}
