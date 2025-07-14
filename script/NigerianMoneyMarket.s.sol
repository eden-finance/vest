// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NigerianMoneyMarket} from "src/NigerianMoneyMarket.sol";

/**
 * @title Deploy Script for Nigerian Money Market
 * @dev Deploys the upgradeable Nigerian Money Market contract
 */
contract DeployNigerianMoneyMarket is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("ADMIN_ADDRESS");
        address cNGNAddress = vm.envAddress("CNGN_ADDRESS");
        uint256 expectedRate = vm.envUint("EXPECTED_RATE"); // In basis points (e.g., 2000 = 20%)
        
        // Multisig configuration
        string memory multisigAddressesStr = vm.envString("MULTISIG_ADDRESSES"); // Comma-separated addresses
        uint256 multisigThreshold = vm.envUint("MULTISIG_THRESHOLD"); // Number of required signatures

        console.log("Deploying Nigerian Money Market...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Admin:", admin);
        console.log("cNGN Token:", cNGNAddress);
        console.log("Expected Rate:", expectedRate, "basis points");
        console.log("Multisig Threshold:", multisigThreshold);

        // Parse multisig addresses
        address[] memory multisigSigners = _parseAddresses(multisigAddressesStr);
        console.log("Multisig Signers Count:", multisigSigners.length);
        for (uint256 i = 0; i < multisigSigners.length; i++) {
            console.log("Signer", i, ":", multisigSigners[i]);
        }

        // VALIDATION: Check all addresses are valid
        require(admin != address(0), "Admin address cannot be zero");
        require(cNGNAddress != address(0), "cNGN address cannot be zero");
        require(expectedRate > 0 && expectedRate <= 5000, "Invalid rate (max 50%)"); // Contract limit is 50%
        require(multisigSigners.length >= 2 && multisigSigners.length <= 10, "Invalid multisig signers count");
        require(multisigThreshold >= 2 && multisigThreshold <= multisigSigners.length, "Invalid multisig threshold");

        // Validate multisig addresses
        for (uint256 i = 0; i < multisigSigners.length; i++) {
            require(multisigSigners[i] != address(0), "Multisig signer cannot be zero address");
            // Check for duplicates
            for (uint256 j = i + 1; j < multisigSigners.length; j++) {
                require(multisigSigners[i] != multisigSigners[j], "Duplicate multisig signer");
            }
        }

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation contract
        NigerianMoneyMarket implementation = new NigerianMoneyMarket();
        console.log("Implementation deployed at:", address(implementation));

        // VALIDATION: Ensure implementation deployed successfully
        require(address(implementation) != address(0), "Implementation deployment failed");

        // Prepare initialization data with all required parameters
        bytes memory initData = abi.encodeWithSelector(
            NigerianMoneyMarket.initialize.selector,
            cNGNAddress,
            admin,
            expectedRate,
            multisigSigners,
            multisigThreshold
        );

        // Deploy proxy with error handling
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        console.log("Proxy deployed at:", address(proxy));
        require(address(proxy) != address(0), "Proxy deployment failed");

        // Cast proxy to contract interface
        NigerianMoneyMarket market = NigerianMoneyMarket(address(proxy));

        // SAFETY: Verify initialization worked before proceeding
        try market.hasRole(market.ADMIN_ROLE(), admin) returns (bool hasAdminRole) {
            require(hasAdminRole, "Admin role not properly assigned during initialization");
        } catch {
            revert("Failed to verify admin role - initialization may have failed");
        }

        // Verify multisig setup
        (address[] memory signers, uint256 threshold) = market.getMultisigConfig();
        require(signers.length == multisigSigners.length, "Multisig signers count mismatch");
        require(threshold == multisigThreshold, "Multisig threshold mismatch");

        // Verify each signer has MULTISIG_ROLE
        for (uint256 i = 0; i < signers.length; i++) {
            require(market.hasRole(market.MULTISIG_ROLE(), signers[i]), "Multisig role not properly assigned");
        }

        vm.stopBroadcast();

        // Verify deployment
        console.log("\n=== Deployment Verification ===");
        console.log("Contract Address:", address(market));
        console.log("cNGN Token:", address(market.cNGN()));
        console.log("Admin Role:", market.hasRole(market.ADMIN_ROLE(), admin));
        
        console.log("Multisig Configuration:");
        console.log("- Signers:", signers.length);
        console.log("- Threshold:", threshold);
        for (uint256 i = 0; i < signers.length; i++) {
            console.log("- Signer", i, ":", signers[i]);
        }

        // Get market configuration
        (uint256 lockDuration, uint256 currentRate, uint256 totalDeposited, uint256 totalWithdrawn, bool acceptingDeposits) = market.marketConfig();
        console.log("Market Configuration:");
        console.log("- Lock Duration:", lockDuration, "seconds");
        console.log("- Expected Rate:", currentRate, "basis points");
        console.log("- Accepting Deposits:", acceptingDeposits);

        // Output statistics separately
        console.log("Statistics:");
        console.log("- Total Deposited:", totalDeposited);
        console.log("- Total Withdrawn:", totalWithdrawn);

        console.log("\n=== Deployment Complete ===");
    }

    /**
     * @dev Parse comma-separated addresses string into array
     * @param addressesStr Comma-separated addresses
     * @return addresses Array of parsed addresses
     */
    function _parseAddresses(string memory addressesStr) internal pure returns (address[] memory) {
        bytes memory addressesBytes = bytes(addressesStr);
        uint256 count = 1;
        
        // Count commas to determine array size
        for (uint256 i = 0; i < addressesBytes.length; i++) {
            if (addressesBytes[i] == ',') {
                count++;
            }
        }
        
        address[] memory addresses = new address[](count);
        uint256 index = 0;
        uint256 start = 0;
        
        for (uint256 i = 0; i <= addressesBytes.length; i++) {
            if (i == addressesBytes.length || addressesBytes[i] == ',') {
                // Extract address substring
                bytes memory addressBytes = new bytes(i - start);
                for (uint256 j = 0; j < i - start; j++) {
                    addressBytes[j] = addressesBytes[start + j];
                }
                
                // Convert to address (this is a simplified parser)
                addresses[index] = _parseAddress(string(addressBytes));
                index++;
                start = i + 1;
            }
        }
        
        return addresses;
    }

    /**
     * @dev Parse a single address string
     * @param addressStr Address string
     * @return addr Parsed address
     */
    function _parseAddress(string memory addressStr) internal pure returns (address) {
        bytes memory addressBytes = bytes(addressStr);
        require(addressBytes.length == 42, "Invalid address length");
        require(addressBytes[0] == '0' && addressBytes[1] == 'x', "Invalid address format");
        
        uint256 result = 0;
        for (uint256 i = 2; i < 42; i++) {
            result *= 16;
            if (addressBytes[i] >= '0' && addressBytes[i] <= '9') {
                result += uint8(addressBytes[i]) - 48;
            } else if (addressBytes[i] >= 'a' && addressBytes[i] <= 'f') {
                result += uint8(addressBytes[i]) - 87;
            } else if (addressBytes[i] >= 'A' && addressBytes[i] <= 'F') {
                result += uint8(addressBytes[i]) - 55;
            } else {
                revert("Invalid address character");
            }
        }
        
        return address(uint160(result));
    }
}

/**
 * @title Testnet Deploy Script
 * @dev Simplified script for testnet deployment with mock token
 */
contract DeployTestnet is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying to testnet...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock cNGN token for testing
        MockERC20 cNGN = new MockERC20("cNGN Stablecoin", "cNGN", 18);
        console.log("Mock cNGN deployed at:", address(cNGN));
        require(address(cNGN) != address(0), "Mock cNGN deployment failed");

        // Mint initial supply to deployer
        cNGN.mint(deployer, 1_000_000_000e18); // 1B cNGN
        console.log("Minted 1B cNGN to deployer");

        // Deploy implementation
        NigerianMoneyMarket implementation = new NigerianMoneyMarket();
        console.log("Implementation deployed at:", address(implementation));
        require(address(implementation) != address(0), "Implementation deployment failed");

        // Create multisig configuration for testnet (using deployer and a dummy address)
        address[] memory multisigSigners = new address[](2);
        multisigSigners[0] = deployer;
        multisigSigners[1] = address(0x1234567890123456789012345678901234567890); // Dummy address for testing
        uint256 multisigThreshold = 2;

        // Deploy proxy with correct initialization parameters
        bytes memory initData = abi.encodeWithSelector(
            NigerianMoneyMarket.initialize.selector,
            address(cNGN),
            deployer,
            2000, // 20% rate
            multisigSigners,
            multisigThreshold
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        NigerianMoneyMarket market = NigerianMoneyMarket(address(proxy));
        require(address(market.cNGN()) == address(cNGN), "cNGN address not set");
        require(market.hasRole(market.ADMIN_ROLE(), deployer), "Admin role not set");

        console.log("Market deployed at:", address(market));
        require(address(market) != address(0), "Market deployment failed");

        // Verify multisig setup
        (address[] memory signers, uint256 threshold) = market.getMultisigConfig();
        require(signers.length == 2, "Multisig signers not set correctly");
        require(threshold == 2, "Multisig threshold not set correctly");
        require(market.hasRole(market.MULTISIG_ROLE(), deployer), "Deployer should have multisig role");

        vm.stopBroadcast();

        console.log("\n=== Testnet Deployment Complete ===");
        console.log("cNGN Token:", address(cNGN));
        console.log("Market Contract:", address(market));
        console.log("Admin:", deployer);
        console.log("Multisig Signers:", signers.length);
        console.log("Multisig Threshold:", threshold);
        
        // Display market configuration
        (uint256 lockDuration, uint256 currentRate, , , bool acceptingDeposits) = market.marketConfig();
        console.log("Lock Duration:", lockDuration, "seconds");
        console.log("Expected Rate:", currentRate, "basis points");
        console.log("Accepting Deposits:", acceptingDeposits);

        // Output completion message
        console.log("Deployment complete.");
    }
}

// Improved Mock ERC20 for testnet deployment
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        require(to != address(0), "Cannot mint to zero address");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "Cannot transfer to zero address");
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(to != address(0), "Cannot transfer to zero address");
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}