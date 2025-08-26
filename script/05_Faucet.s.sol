// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/misc/Faucet.sol";

/**
 * @title Deploy EdenVest Faucet System
 * @notice Deploys faucet contract and creates test tokens
 */
contract DeployFaucetScript is Script {
    // Token Configuration
    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialSupply;
        uint256 faucetAmount;
        uint256 cooldown;
        uint256 dailyLimit;
    }

    // Deployed addresses
    address payable public faucet;
    address public cNGN;
    address public USDC;
    address public USDT;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        console.log("=== EdenVest Faucet Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Timestamp:", block.timestamp);

        // Step 1: Deploy the faucet contract
        console.log("\n Deploying EdenVestFaucet...");
        faucet = deployFaucet();
        console.log(" Faucet deployed at:", faucet);

        // Step 2: Deploy tokens through the faucet
        console.log("\n Deploying tokens through faucet...");

        // Deploy cNGN
        cNGN = deployToken(
            TokenConfig({
                name: "Compliant Nigerian Naira",
                symbol: "cNGN",
                decimals: 18,
                initialSupply: 1_000_000_000, // 1 billion
                faucetAmount: 10_000 * 1e18, // 10,000 tokens
                cooldown: 2 hours,
                dailyLimit: 3
            })
        );
        console.log(" cNGN deployed at:", cNGN);

        // Deploy USDC
        USDC = deployToken(
            TokenConfig({
                name: "USD Coin",
                symbol: "USDC",
                decimals: 18,
                initialSupply: 1_000_000_000, // 1 billion
                faucetAmount: 10_000 * 1e18, // 10,000 tokens
                cooldown: 2 hours,
                dailyLimit: 3
            })
        );
        console.log(" USDC deployed at:", USDC);

        // Deploy USDT
        USDT = deployToken(
            TokenConfig({
                name: "Tether USD",
                symbol: "USDT",
                decimals: 18,
                initialSupply: 1_000_000_000, // 1 billion
                faucetAmount: 10_000 * 1e18, // 10,000 tokens
                cooldown: 2 hours,
                dailyLimit: 3
            })
        );
        console.log(" USDT deployed at:", USDT);

        // Step 3: Configure native token faucet
        console.log("\n Configuring native token faucet...");
        configureNativeFaucet();

        // Step 4: Fund the faucet with native tokens
        console.log("\n Funding faucet with native tokens...");
        // fundFaucetWithNative();

        // Step 5: Add initial whitelist (optional)
        console.log("\n Adding initial whitelist...");
        addInitialWhitelist();

        vm.stopBroadcast();

        // Save deployment addresses
        saveDeploymentAddresses();

        // Print deployment summary
        printDeploymentSummary();

        // Print verification commands
        printVerificationCommands();
    }

    function deployFaucet() internal returns (address payable) {
        EdenVestFaucet faucetContract = new EdenVestFaucet();
        return payable(address(faucetContract));
    }

    function deployToken(TokenConfig memory config) internal returns (address) {
        console.log(string.concat("  Deploying ", config.symbol, "..."));

        address tokenAddress = EdenVestFaucet(faucet).deployToken(
            config.name,
            config.symbol,
            config.decimals,
            config.initialSupply,
            config.faucetAmount,
            config.cooldown,
            config.dailyLimit
        );

        console.log(string.concat("  ", config.symbol, " configuration:"));
        console.log("    - Initial Supply:", config.initialSupply);
        console.log("    - Faucet Amount:", config.faucetAmount / 1e18);
        console.log("    - Cooldown:", config.cooldown / 3600, "hours");
        console.log("    - Daily Limit:", config.dailyLimit);

        return tokenAddress;
    }

    function configureNativeFaucet() internal {
        // Configure native token with reasonable limits
        EdenVestFaucet(faucet).configureNative(
            0.1 ether, // 0.1 native tokens per claim
            2 hours, // 2 hour cooldown
            3, // 3 claims per day
            true // enabled
        );
        console.log(" Native token faucet configured");
        console.log("  - Amount: 0.1 native tokens");
        console.log("  - Cooldown: 2 hours");
        console.log("  - Daily limit: 3 claims");
    }

    function fundFaucetWithNative() internal {
        uint256 fundingAmount = vm.envOr("FAUCET_NATIVE_FUNDING", uint256(1 ether));

        if (address(faucet).balance < fundingAmount) {
            (bool success,) = faucet.call{value: fundingAmount}("");
            require(success, "Failed to fund faucet with native tokens");
            console.log(" Funded faucet with", fundingAmount / 1e18, "native tokens");
        } else {
            console.log("  Faucet already has sufficient native balance");
        }
    }

    function addInitialWhitelist() internal {
        address admin = vm.envOr("ADMIN_ADDRESS", address(0));
        if (admin == address(0)) {
            admin = vm.addr(vm.envUint("PRIVATE_KEY"));
        }

        // Add admin to whitelist
        EdenVestFaucet(faucet).addToWhitelist(admin);
        console.log(" Added admin to whitelist:", admin);

        // Add additional addresses if provided
        address[] memory additionalAddresses = getAdditionalWhitelistAddresses();
        if (additionalAddresses.length > 0) {
            EdenVestFaucet(faucet).addMultipleToWhitelist(additionalAddresses);
            console.log(" Added", additionalAddresses.length, "additional addresses to whitelist");
        }
    }

    function getAdditionalWhitelistAddresses() internal returns (address[] memory) {
        // You can add more addresses here or read from environment
        string memory whitelist = vm.envOr("FAUCET_WHITELIST", string(""));

        if (bytes(whitelist).length == 0) {
            return new address[](0);
        }

        // Parse comma-separated addresses (simplified - you may want more robust parsing)
        // For now, return empty array - implement parsing if needed
        return new address[](0);
    }

    function saveDeploymentAddresses() internal {
        string memory json = "faucet_deployment";

        vm.serializeAddress(json, "faucet", faucet);
        vm.serializeAddress(json, "cNGN", cNGN);
        vm.serializeAddress(json, "USDC", USDC);
        string memory output = vm.serializeAddress(json, "USDT", USDT);

        string memory filename = string.concat("deployments/faucet_", vm.toString(block.chainid), ".json");
        vm.writeJson(output, filename);

        console.log("\n Deployment addresses saved to:", filename);
    }

    function printDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Faucet Contract:", faucet);
        console.log("\nDeployed Tokens:");
        console.log("  cNGN:", cNGN);
        console.log("  USDC:", USDC);
        console.log("  USDT:", USDT);

        console.log("\n Token Balances in Faucet:");
        console.log("  cNGN:", IERC20(cNGN).balanceOf(faucet) / 1e18);
        console.log("  USDC:", IERC20(USDC).balanceOf(faucet) / 1e18);
        console.log("  USDT:", IERC20(USDT).balanceOf(faucet) / 1e18);
        console.log("  Native:", address(faucet).balance / 1e18);
    }

    function printVerificationCommands() internal {
        console.log("\n=== VERIFICATION COMMANDS ===");
        console.log("Save these commands to verify contracts on block explorer:\n");

        // Get common environment variables
        string memory rpcUrl = vm.envOr("RPC_URL", string("https://enugu-rpc.assetchain.org/"));
        string memory verifier = vm.envOr("VERIFIER", string("blockscout"));
        string memory verifierUrl = vm.envOr("VERIFIER_URL", string("https://scan-testnet.assetchain.org/api/"));

        // Faucet verification command
        console.log("# Verify Faucet Contract");
        console.log(
            string.concat(
                "forge verify-contract ",
                "--rpc-url ",
                rpcUrl,
                " ",
                "--verifier ",
                verifier,
                " ",
                "--verifier-url ",
                verifierUrl,
                " ",
                vm.toString(faucet),
                " ",
                "src/faucet/EdenVestFaucet.sol:EdenVestFaucet"
            )
        );

        console.log("\n# Verify cNGN Token");
        console.log(generateTokenVerificationCommand(cNGN, "Compliant Nigerian Naira", "cNGN"));

        console.log("\n# Verify USDC Token");
        console.log(generateTokenVerificationCommand(USDC, "USD Coin", "USDC"));

        console.log("\n# Verify USDT Token");
        console.log(generateTokenVerificationCommand(USDT, "Tether USD", "USDT"));
    }

    function generateTokenVerificationCommand(address token, string memory name, string memory symbol)
        internal
        
        returns (string memory)
    {
        string memory rpcUrl = vm.envOr("RPC_URL", string("https://enugu-rpc.assetchain.org/"));
        string memory verifier = vm.envOr("VERIFIER", string("blockscout"));
        string memory verifierUrl = vm.envOr("VERIFIER_URL", string("https://scan-testnet.assetchain.org/api/"));

        bytes memory constructorArgs = abi.encode(name, symbol, uint8(18), uint256(1_000_000_000), faucet);

        return string.concat(
            "forge verify-contract ",
            "--rpc-url ",
            rpcUrl,
            " ",
            "--verifier ",
            verifier,
            " ",
            "--verifier-url ",
            verifierUrl,
            " ",
            "--constructor-args ",
            vm.toString(constructorArgs),
            " ",
            vm.toString(token),
            " ",
            "src/faucet/EdenVestFaucet.sol:FaucetToken"
        );
    }
}
