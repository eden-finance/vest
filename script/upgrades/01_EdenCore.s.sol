// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {EdenVestCore} from "../../src/vest/EdenVestCore.sol";

import {DevOpsTools} from "../../lib/foundry-devops/src/DevOpsTools.sol";

contract UpgradeEdenVestCoreScript is Script {
    function run() external {
        address proxy = vm.envAddress("EDEN_CORE_PROXY");
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address sender = vm.addr(pk);

        // address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("ERC1967Proxy", block.chainid);

        // vm.startBroadcast(pk);
        // EdenVestCore newImpl = new EdenVestCore();
        // console2.log("New impl:", address(newImpl));

        // EdenVestCore(mostRecentlyDeployed).upgradeToAndCall(address(newImpl));
        // console2.log("Upgrade tx sent.");
        // vm.stopBroadcast();
    }
}
