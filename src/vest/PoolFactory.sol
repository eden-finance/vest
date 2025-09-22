// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IInvestmentPool.sol";
import "./interfaces/ILPToken.sol";
import "./InvestmentPool.sol";
import "./LPToken.sol";

/**
 * @title PoolFactory
 * @notice Factory for creating investment pools with minimal gas costs
 * @dev Uses clone pattern for efficient deployment
 */
contract PoolFactory is IPoolFactory, Ownable {
    using Clones for address;

    // ============ STATE VARIABLES ============
    address public poolImplementation;
    address public lpTokenImplementation;
    address public edenCore;
    address public taxCollector;
    address public nftManager;

    mapping(address => bool) public isPool;
    address[] public allPools;

    // ============ MODIFIERS ============
    modifier onlyEdenCore() {
        require(msg.sender == edenCore, "Only Eden Core");
        _;
    }

    // ============ CONSTRUCTOR ============
    constructor(address _owner) Ownable(_owner) {}

    // ============ FACTORY FUNCTIONS ============

    /**
     * @notice Create a new investment pool
     * @param params Pool parameters
     * @return pool Address of created pool
     */
    function createPool(PoolParams memory params) external override onlyEdenCore returns (address pool) {
        // Validate parameters
        require(params.admin != address(0), "Invalid admin");
        require(params.poolMultisig != address(0), "Invalid multisig");
        require(params.multisigSigners.length >= 2, "Insufficient signers");
        require(params.lockDuration >= 1 seconds, "Duration too short");
        require(params.minInvestment > 0, "Invalid min investment");

        require(address(lpTokenImplementation) != address(0), "No LP token implementation");
        require(address(poolImplementation) != address(0), "No Pool implementation");

        address lpToken = lpTokenImplementation.clone();

        // Initialize LP token
        string memory lpTokenName = string.concat("Eden ", params.name, " LP");
        string memory lpTokenSymbol = string.concat("e", params.symbol, "LP");
        IInvestmentPool.InitParams memory initParams = IInvestmentPool.InitParams({
            name: params.name,
            lpToken: lpToken,
            cNGN: params.cNGN,
            poolMultisig: params.poolMultisig,
            nftManager: nftManager,
            edenCore: edenCore,
            admin: params.admin,
            multisigSigners: params.multisigSigners,
            lockDuration: params.lockDuration,
            minInvestment: params.minInvestment,
            maxInvestment: params.maxInvestment,
            utilizationCap: params.utilizationCap,
            expectedRate: params.expectedRate,
            taxRate: params.taxRate
        });

        bytes memory initCalldata = abi.encodeCall(InvestmentPool.initialize, (initParams));

        ERC1967Proxy proxy = new ERC1967Proxy(poolImplementation, initCalldata);
        pool = address(proxy);

        ILPToken(lpToken).initialize(lpTokenName, lpTokenSymbol, params.admin, pool);

        isPool[pool] = true;
        allPools.push(pool);

        emit PoolCreated(pool, params.name, params.admin, lpToken);
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Set Tax Collector address
     * @param _taxCollector Tax Collector contract address
     */
    function setTaxCollector(address _taxCollector) external onlyOwner {
        require(_taxCollector != address(0), "Invalid address");
        taxCollector = _taxCollector;
    }

    /**
     * @notice Set Eden Core address
     * @param _edenCore Eden Core contract address
     */
    function setEdenCore(address _edenCore) external onlyOwner {
        require(_edenCore != address(0), "Invalid address");
        edenCore = _edenCore;
    }

    /**
     * @notice Set NFT Manager address
     * @param _nftManager NFT Manager contract address
     */
    function setNFTManager(address _nftManager) external onlyOwner {
        require(_nftManager != address(0), "Invalid address");
        nftManager = _nftManager;
    }

    /**
     * @notice Update pool implementation
     * @param _implementation New implementation address
     */
    function updatePoolImplementation(address _implementation) external onlyOwner {
        require(_implementation != address(0), "Invalid address");
        poolImplementation = _implementation;
    }

    /**
     * @notice Update LP token implementation
     * @param _implementation New implementation address
     */
    function updateLPTokenImplementation(address _implementation) external onlyOwner {
        require(_implementation != address(0), "Invalid address");
        lpTokenImplementation = _implementation;
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get all pools
     * @return Array of pool addresses
     */
    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    /**
     * @notice Get pool count
     * @return Number of pools created
     */
    function getPoolCount() external view returns (uint256) {
        return allPools.length;
    }
}
