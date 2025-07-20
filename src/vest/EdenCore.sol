// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IPoolFactory.sol";
import "./interfaces/IInvestmentPool.sol";
import "./interfaces/ITaxCollector.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/INFTPositionManager.sol";

/**
 * @title EdenCore
 * @notice Main entry point for Eden Finance investment protocol
 * @dev Manages pools, investments, and protocol configuration
 */
contract EdenCore is Initializable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    // ============ ROLES ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant POOL_CREATOR_ROLE = keccak256("POOL_CREATOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // ============ STATE VARIABLES ============
    IPoolFactory public poolFactory;
    ITaxCollector public taxCollector;
    ISwapRouter public swapRouter;
    INFTPositionManager public nftManager;

    address public cNGN;
    address public protocolTreasury;

    mapping(address => bool) public isRegisteredPool;
    mapping(address => PoolInfo) public poolInfo;
    address[] public allPools;

    uint256 public globalTaxRate; // basis points
    uint256 public constant MAX_TAX_RATE = 1000; // 10%
    uint256 public constant BASIS_POINTS = 10000;

    // ============ STRUCTS ============
    struct PoolInfo {
        string name;
        address admin;
        address lpToken;
        uint256 createdAt;
        bool isActive;
    }

    struct InvestmentParams {
        address pool;
        address tokenIn;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        string title;
    }

    // ============ EVENTS ============
    event PoolCreated(address indexed pool, string name, address indexed admin, address lpToken);
    event InvestmentMade(
        address indexed pool, address indexed investor, uint256 tokenId, uint256 amount, uint256 lpTokens
    );
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event EmergencyWithdraw(address token, uint256 amount);

    // ============ ERRORS ============
    error InvalidPool();
    error InvalidAmount();
    error PoolNotActive();
    error InvalidTaxRate();
    error InvalidAddress();
    error TransferFailed();
    error InsufficientLiquidity();
    error SwapFailed();

    // ============ INITIALIZATION ============
    function initialize(address _cNGN, address _treasury, address _admin, uint256 _taxRate) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        if (_cNGN == address(0) || _treasury == address(0)) revert InvalidAddress();
        if (_taxRate > MAX_TAX_RATE) revert InvalidTaxRate();

        cNGN = _cNGN;
        protocolTreasury = _treasury;
        globalTaxRate = _taxRate;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(POOL_CREATOR_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);
    }

    // ============ POOL MANAGEMENT ============

    /**
     * @notice Create a new investment pool
     * @param poolParams Parameters for pool creation
     * @return pool Address of created pool
     */
    function createPool(IPoolFactory.PoolParams memory poolParams)
        external
        onlyRole(POOL_CREATOR_ROLE)
        returns (address pool)
    {
        pool = poolFactory.createPool(poolParams);

        isRegisteredPool[pool] = true;
        allPools.push(pool);

        poolInfo[pool] = PoolInfo({
            name: poolParams.name,
            admin: poolParams.admin,
            lpToken: IInvestmentPool(pool).lpToken(),
            createdAt: block.timestamp,
            isActive: true
        });

        emit PoolCreated(pool, poolParams.name, poolParams.admin, poolInfo[pool].lpToken);
    }

    // ============ INVESTMENT FUNCTIONS ============

    /**
     * @notice Invest in a pool with cNGN
     * @param pool Pool address to invest in
     * @param amount Amount of cNGN to invest
     * @param title Investment title/description
     */
    function invest(address pool, uint256 amount, string memory title)
        external
        whenNotPaused
        returns (uint256 tokenId, uint256 lpTokens)
    {
        if (!isRegisteredPool[pool]) revert InvalidPool();
        if (!poolInfo[pool].isActive) revert PoolNotActive();

        // transfer cNGN to this contract and approve the pool to spend cNGN
        IERC20(cNGN).transferFrom(msg.sender, address(this), amount);
        IERC20(cNGN).approve(pool, amount);

        (tokenId, lpTokens) = IInvestmentPool(pool).invest(msg.sender, amount, title);

        // Handle tax collection
        uint256 taxAmount = _collectTax(pool, lpTokens);
        lpTokens -= taxAmount;

        emit InvestmentMade(pool, msg.sender, tokenId, amount, lpTokens);
    }

    /**
     * @notice Invest with any token via swap
     * @param params Investment parameters including swap details
     */
    function investWithSwap(InvestmentParams memory params)
        external
        whenNotPaused
        returns (uint256 tokenId, uint256 lpTokens)
    {
        if (!isRegisteredPool[params.pool]) revert InvalidPool();
        if (!poolInfo[params.pool].isActive) revert PoolNotActive();

        // Transfer tokens from user
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Check liquidity and perform swap
        uint256 expectedOut = swapRouter.getAmountOut(params.tokenIn, cNGN, params.amountIn);
        if (expectedOut < params.minAmountOut) revert InsufficientLiquidity();

        IERC20(params.tokenIn).approve(address(swapRouter), params.amountIn);
        uint256 amountOut = swapRouter.swapExactTokensForTokens(
            params.tokenIn, cNGN, params.amountIn, params.minAmountOut, params.deadline
        );

        if (amountOut == 0) revert SwapFailed();

        // Invest the swapped cNGN
        IERC20(cNGN).approve(params.pool, amountOut);
        (tokenId, lpTokens) = IInvestmentPool(params.pool).invest(msg.sender, amountOut, params.title);

        // Handle tax collection
        uint256 taxAmount = _collectTax(params.pool, lpTokens);
        lpTokens -= taxAmount;

        emit InvestmentMade(params.pool, msg.sender, tokenId, amountOut, lpTokens);
    }

    /**
     * @notice Withdraw investment from pool
     * @param pool Pool address
     * @param tokenId NFT token ID
     * @param lpTokenAmount Amount of LP tokens to return
     */
    function withdraw(address pool, uint256 tokenId, uint256 lpTokenAmount) external returns (uint256 withdrawAmount) {
        if (!isRegisteredPool[pool]) revert InvalidPool();

        // Transfer LP tokens from user to pool
        address lpToken = poolInfo[pool].lpToken;
        IERC20(lpToken).transferFrom(msg.sender, pool, lpTokenAmount);

        // Process withdrawal
        withdrawAmount = IInvestmentPool(pool).withdraw(msg.sender, tokenId, lpTokenAmount);
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
     * @notice Get active pools
     * @return Array of active pool addresses
     */
    function getActivePools() external view returns (address[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (poolInfo[allPools[i]].isActive) activeCount++;
        }

        address[] memory activePools = new address[](activeCount);
        uint256 index = 0;
        for (uint256 i = 0; i < allPools.length; i++) {
            if (poolInfo[allPools[i]].isActive) {
                activePools[index++] = allPools[i];
            }
        }

        return activePools;
    }

    /**
     * @notice Check swap liquidity
     * @param tokenIn Input token address
     * @param amountIn Input amount
     * @return expectedOut Expected output amount
     * @return hasLiquidity Whether sufficient liquidity exists
     */
    function checkSwapLiquidity(address tokenIn, uint256 amountIn)
        external
        returns (uint256 expectedOut, bool hasLiquidity)
    {
        expectedOut = swapRouter.getAmountOut(tokenIn, cNGN, amountIn);
        hasLiquidity = expectedOut > 0;
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @notice Set pool factory contract
     * @param _factory Factory contract address
     */
    function setPoolFactory(address _factory) external onlyRole(ADMIN_ROLE) {
        if (_factory == address(0)) revert InvalidAddress();
        poolFactory = IPoolFactory(_factory);
    }

    /**
     * @notice Set tax collector contract
     * @param _collector Tax collector address
     */
    function setTaxCollector(address _collector) external onlyRole(ADMIN_ROLE) {
        if (_collector == address(0)) revert InvalidAddress();
        taxCollector = ITaxCollector(_collector);
    }

    /**
     * @notice Set swap router contract
     * @param _router Swap router address
     */
    function setSwapRouter(address _router) external onlyRole(ADMIN_ROLE) {
        if (_router == address(0)) revert InvalidAddress();
        swapRouter = ISwapRouter(_router);
    }

    /**
     * @notice Set NFT manager contract
     * @param _manager NFT manager address
     */
    function setNFTManager(address _manager) external onlyRole(ADMIN_ROLE) {
        if (_manager == address(0)) revert InvalidAddress();
        nftManager = INFTPositionManager(_manager);
    }

    /**
     * @notice Update global tax rate
     * @param _rate New tax rate in basis points
     */
    function setGlobalTaxRate(uint256 _rate) external onlyRole(ADMIN_ROLE) {
        if (_rate > MAX_TAX_RATE) revert InvalidTaxRate();
        uint256 oldRate = globalTaxRate;
        globalTaxRate = _rate;
        emit TaxRateUpdated(oldRate, _rate);
    }

    /**
     * @notice Update protocol treasury
     * @param _treasury New treasury address
     */
    function setProtocolTreasury(address _treasury) external onlyRole(ADMIN_ROLE) {
        if (_treasury == address(0)) revert InvalidAddress();
        address oldTreasury = protocolTreasury;
        protocolTreasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @notice Toggle pool active status
     * @param pool Pool address
     * @param active New status
     */
    function setPoolActive(address pool, bool active) external onlyRole(ADMIN_ROLE) {
        if (!isRegisteredPool[pool]) revert InvalidPool();
        poolInfo[pool].isActive = active;
    }

    /**
     * @notice Pause protocol
     */
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause protocol
     */
    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdraw tokens
     * @param token Token address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(EMERGENCY_ROLE) {
        IERC20(token).transfer(protocolTreasury, amount);
        emit EmergencyWithdraw(token, amount);
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Collect tax on LP tokens
     * @param pool Pool address
     * @param lpAmount LP token amount
     * @return taxAmount Tax collected
     */
    function _collectTax(address pool, uint256 lpAmount) internal returns (uint256 taxAmount) {
        uint256 poolTaxRate = IInvestmentPool(pool).taxRate();
        uint256 effectiveTaxRate = poolTaxRate > 0 ? poolTaxRate : globalTaxRate;

        if (effectiveTaxRate > 0 && address(taxCollector) != address(0)) {
            taxAmount = (lpAmount * effectiveTaxRate) / BASIS_POINTS;
            address lpToken = poolInfo[pool].lpToken;

            IERC20(lpToken).approve(address(taxCollector), taxAmount);

            taxCollector.collectTax(lpToken, taxAmount, pool);
        }
    }

    /**
     * @dev Authorize upgrade
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
