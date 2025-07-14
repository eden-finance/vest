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
        address multisigAddress = vm.envAddress("MULTISIG_ADDRESS");
        uint256 expectedRate = vm.envUint("EXPECTED_RATE"); // In basis points (e.g., 2000 = 20%)
        
        console.log("Deploying Nigerian Money Market...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Admin:", admin);
        console.log("cNGN Token:", cNGNAddress);
        console.log("Multisig:", multisigAddress);
        console.log("Expected Rate:", expectedRate, "basis points");
        
        // VALIDATION: Check all addresses are valid
        require(admin != address(0), "Admin address cannot be zero");
        require(cNGNAddress != address(0), "cNGN address cannot be zero");
        require(multisigAddress != address(0), "Multisig address cannot be zero");
        require(expectedRate > 0 && expectedRate <= 10000, "Invalid rate"); // Max 100%
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy implementation contract
        NigerianMoneyMarket implementation = new NigerianMoneyMarket();
        console.log("Implementation deployed at:", address(implementation));
        
        // VALIDATION: Ensure implementation deployed successfully
        require(address(implementation) != address(0), "Implementation deployment failed");
        
        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            NigerianMoneyMarket.initialize.selector,
            cNGNAddress,
            admin,
            expectedRate
        );
        
        // Deploy proxy with error handling
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        
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
        
        // Add multisig as authorized
        market.updateMultisig(multisigAddress, true);
        console.log("Multisig authorized:", multisigAddress);
        
        vm.stopBroadcast();
        
        // Verify deployment
        console.log("\n=== Deployment Verification ===");
        console.log("Contract Address:", address(market));
        console.log("cNGN Token:", address(market.cNGN()));
        console.log("Admin Role:", market.hasRole(market.ADMIN_ROLE(), admin));
        console.log("Multisig Role:", market.hasRole(market.MULTISIG_ROLE(), multisigAddress));
        
        (uint256 lockDuration, uint256 rate, , , bool accepting) = market.marketConfig();
        console.log("Lock Duration:", lockDuration, "seconds");
        console.log("Expected Rate:", rate, "basis points");
        console.log("Accepting Deposits:", accepting);
        
        console.log("\n=== Deployment Complete ===");
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
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            NigerianMoneyMarket.initialize.selector,
            address(cNGN),
            deployer, 
            2000 // 20% rate
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        
NigerianMoneyMarket market = NigerianMoneyMarket(address(proxy));
require(address(market.cNGN()) == address(cNGN), "cNGN address not set");
require(market.hasRole(market.ADMIN_ROLE(), deployer), "Admin role not set");

        console.log("Market deployed at:", address(market));
        require(address(market) != address(0), "Market deployment failed");
        
        // Setup multisig (using deployer for testing)
        market.updateMultisig(deployer, true);
        console.log("Deployer set as multisig for testing");
        
        vm.stopBroadcast();
        
        console.log("\n=== Testnet Deployment Complete ===");
        console.log("cNGN Token:", address(cNGN));
        console.log("Market Contract:", address(market));
        console.log("Admin/Multisig:", deployer);
        console.logBytes(initData); // Debug initialization data
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