// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {EdenPoolNFT} from "src/EdenPoolNFT.sol";

contract DeployEdenPoolNFT is Script {
    function run() external returns (EdenPoolNFT nft) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        nft = new EdenPoolNFT();
        vm.stopBroadcast();

        console2.log("EdenPoolNFT deployed at:", address(nft));
    }
}
