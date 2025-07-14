// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";

contract Simple {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }
}

contract SimpleDeploy is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Simple simple = new Simple();
        console.log("Simple deployed at:", address(simple));
        vm.stopBroadcast();
    }
}
