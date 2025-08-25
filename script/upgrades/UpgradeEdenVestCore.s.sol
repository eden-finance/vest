// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import {EdenVestCore} from "../../src/vest/EdenVestCore.sol";

/// @notice Upgrades the EdenVestCore UUPS proxy to a newly deployed implementation.
/// ENV:
///   - EDEN_CORE_PROXY = 0x... (ERC1967Proxy address)
///   - PRIVATE_KEY     = <admin key with ADMIN_ROLE on the proxy>
contract UpgradeEdenVestCoreScript is Script {
    // EIP-1967 implementation slot: bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC;

    function _getImpl(address proxy) internal view returns (address impl) {
        bytes32 data = vm.load(proxy, _IMPLEMENTATION_SLOT);
        impl = address(uint160(uint256(data)));
    }

    function run() external {
        address proxy = vm.envAddress("EDEN_CORE_PROXY");
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address beforeImpl = _getImpl(proxy);
        console2.log("Proxy:               ", proxy);
        console2.log("Current implementation:", beforeImpl);

        vm.startBroadcast(pk);

        EdenVestCore newImpl = new EdenVestCore();
        console2.log("New implementation:  ", address(newImpl));

        // Optional post-upgrade call data (leave empty if not calling anything)
        bytes memory data = "";

        EdenVestCore(proxy).upgradeToAndCall(address(newImpl), data);

        vm.stopBroadcast();

        address afterImpl = _getImpl(proxy);
        console2.log("Upgraded implementation:", afterImpl);
        require(afterImpl == address(newImpl), "Upgrade failed: impl mismatch");
    }
}

// DEPLOY COMMAND
// forge verify-contract \
//   --rpc-url https://enugu-rpc.assetchain.org/ \
//   --verifier blockscout \
//   --verifier-url https://scan-testnet.assetchain.org/api/ \
//   --constructor-args "" \
//   0xa449f595f53aCD20C39EA55e65658a33AC4452F9 src/vest/EdenVestCore.sol:EdenVestCore
