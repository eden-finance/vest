// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {    PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IInvestmentPool.sol";
import "./interfaces/ITaxCollector.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/INFTPositionManager.sol";
/**
 * @title EdenVestCore
 * @notice Main entry point for Eden Finance investment protocol
 * @dev Manages pools, investments, and protocol configuration
 */

contract EdenVestCore is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

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
    address public edenAdmin;

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

    struct WithdrawAndSwapParams {
        address pool;
        uint256 tokenId;
        uint256 lpTokenAmount;
        address tokenOut;
        uint256 minAmountOut;
        uint256 deadline; // 0 means "no deadline"
        uint256 maxSlippageBps; // 0 => default 100 bps; cap for sanity
    }

    // ============ EVENTS ============
    event InvestmentMade(
        address indexed pool, address indexed investor, uint256 tokenId, uint256 amount, uint256 lpTokens
    );
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event EmergencyWithdraw(address token, uint256 amount, address treasury, string reason, address admin);
    event WithdrawnAndSwapped(
        address indexed pool,
        address indexed investor,
        uint256 indexed tokenId,
        uint256 amountInCNGN,
        address tokenOut,
        uint256 amountOut
    );

    // ============ ERRORS ============
    error InvalidPool();
    error InvalidAmount();
    error PoolNotActive();
    error InvalidTaxRate();
    error InvalidAddress();
    error TransferFailed();
    error InsufficientLiquidity();
    error SwapFailed();
    error DeadlineExpired();
    error SwapInconsistency();
    error InvalidLockDuration();
    error InvalidRate();
    error InvalidPoolName();
    error InsufficientBalance();
    error MinAmountOutZero();
    error InvalidSlippage();
    error InvalidToken();

    // ============ MODIFIERS ============
    modifier onlyAdminContract() {
        require(msg.sender == edenAdmin, "Only EdenAdmin");
        _;
    }

    constructor(){
        _disableInitializers();
    }

    function initialize(address _cNGN, address _treasury, address _admin, uint256 _taxRate) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

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

    // ============ ADMIN SETTER FUNCTIONS ============

    function setEdenAdmin(address _edenAdmin) external onlyRole(ADMIN_ROLE) {
        if (_edenAdmin == address(0)) revert InvalidAddress();
        edenAdmin = _edenAdmin;
        _grantRole(ADMIN_ROLE, _edenAdmin);
    }

    // ============ ADMIN FUNCTION ============

    function setGlobalTaxRateInternal(uint256 _rate) external onlyAdminContract {
        uint256 oldRate = globalTaxRate;
        globalTaxRate = _rate;
        emit TaxRateUpdated(oldRate, _rate);
    }

    function setProtocolTreasuryInternal(address _treasury) external onlyAdminContract {
        address oldTreasury = protocolTreasury;
        protocolTreasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    function emergencyWithdrawInternal(address token, uint256 amount, string memory reason)
        external
        onlyAdminContract
    {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();

        IERC20(token).transfer(protocolTreasury, amount);
        emit EmergencyWithdraw(token, amount, protocolTreasury, reason, msg.sender);
    }

    function pauseProtocol() external onlyAdminContract {
        _pause();
    }

    function unpauseProtocol() external onlyAdminContract {
        _unpause();
    }

    // ============ CORE FUNCTIONS ============

    function createPool(IPoolFactory.PoolParams memory poolParams)
        external
        onlyRole(POOL_CREATOR_ROLE)
        returns (address pool)
    {
        if (bytes(poolParams.name).length == 0) revert InvalidPoolName();
        if (poolParams.admin == address(0)) revert InvalidAddress();
        if (poolParams.poolMultisig == address(0)) revert InvalidAddress();
        if (poolParams.minInvestment == 0) revert InvalidAmount();
        if (poolParams.maxInvestment < poolParams.minInvestment) revert InvalidAmount();
        if (poolParams.lockDuration < 1 days) revert InvalidLockDuration();
        if (poolParams.expectedRate > 10000) revert InvalidRate();
        if (poolParams.taxRate > MAX_TAX_RATE) revert InvalidTaxRate();

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
    }

    /**
     * @notice Check cNGN allowance for a user to spend on EdenCore
     * @param user The user address to check allowance for
     * @return allowance The current allowance amount
     */
    function checkCNGNAllowance(address user) external view returns (uint256 allowance) {
        return IERC20(cNGN).allowance(user, address(this));
    }

    function invest(address pool, uint256 amount, string memory title, uint256 deadline)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 tokenId, uint256 lpTokens)
    {
        if (!isRegisteredPool[pool]) revert InvalidPool();
        if (!poolInfo[pool].isActive) revert PoolNotActive();
        if (deadline != 0 && deadline < block.timestamp) revert DeadlineExpired();

        IERC20(cNGN).transferFrom(msg.sender, address(this), amount);
        IERC20(cNGN).approve(pool, amount);

        uint256 taxLpTokens;

        (tokenId, lpTokens, taxLpTokens) = IInvestmentPool(pool).invest(msg.sender, amount, title);

        address lpToken = IInvestmentPool(pool).lpToken();

        ITaxCollector(taxCollector).collectTax(lpToken, pool, taxLpTokens);

        emit InvestmentMade(pool, msg.sender, tokenId, amount, lpTokens);
    }

    function investWithSwap(InvestmentParams memory params)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 tokenId, uint256 lpTokens)
    {
        if (!isRegisteredPool[params.pool]) revert InvalidPool();
        if (!poolInfo[params.pool].isActive) revert PoolNotActive();
        if (params.deadline < block.timestamp) revert DeadlineExpired();

        uint256 initialBalance = IERC20(cNGN).balanceOf(address(this));

        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        uint256 expectedOut = swapRouter.getAmountOut(params.tokenIn, cNGN, params.amountIn);

        uint256 maxSlippageBasisPoints = 100;
        uint256 adjustedMinOut = (expectedOut * (BASIS_POINTS - maxSlippageBasisPoints)) / BASIS_POINTS;

        if (adjustedMinOut < params.minAmountOut) revert InsufficientLiquidity();

        IERC20(params.tokenIn).approve(address(swapRouter), params.amountIn);
        uint256 effectiveMinOut = adjustedMinOut > params.minAmountOut ? adjustedMinOut : params.minAmountOut;

        uint256 amountOut =
            swapRouter.swapExactTokensForTokens(params.tokenIn, cNGN, params.amountIn, effectiveMinOut, params.deadline);

        if (amountOut == 0) revert SwapFailed();
        uint256 finalBalance = IERC20(cNGN).balanceOf(address(this));
        if (finalBalance != initialBalance + amountOut) revert SwapInconsistency();

        IERC20(cNGN).approve(params.pool, amountOut);
        (tokenId, lpTokens,) = IInvestmentPool(params.pool).invest(msg.sender, amountOut, params.title);

        emit InvestmentMade(params.pool, msg.sender, tokenId, amountOut, lpTokens);
    }

    function withdrawAndSwap(WithdrawAndSwapParams calldata p)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 amountOut)
    {
        address _pool = p.pool;
        if (!isRegisteredPool[_pool]) revert InvalidPool();
        if (p.tokenOut == address(0)) revert InvalidToken();
        if (p.deadline != 0 && p.deadline < block.timestamp) revert DeadlineExpired();

        address _lpToken = poolInfo[_pool].lpToken;
        IERC20(_lpToken).safeTransferFrom(msg.sender, _pool, p.lpTokenAmount);

        IERC20 _cngn = IERC20(cNGN);
        uint256 cngnBefore = _cngn.balanceOf(address(this));
        IInvestmentPool(_pool).withdraw(address(this), p.tokenId, p.lpTokenAmount);
        uint256 amountInCNGN = _cngn.balanceOf(address(this)) - cngnBefore;
        if (amountInCNGN == 0) revert InsufficientLiquidity();

        if (p.tokenOut == cNGN) {
            _cngn.safeTransfer(msg.sender, amountInCNGN);
            emit WithdrawnAndSwapped(_pool, msg.sender, p.tokenId, amountInCNGN, cNGN, amountInCNGN);
            return amountInCNGN;
        }

        if (p.minAmountOut == 0) revert MinAmountOutZero();

        uint256 slippageBps = p.maxSlippageBps == 0 ? 100 : p.maxSlippageBps;
        if (slippageBps > 300) revert InvalidSlippage();

        uint256 expectedOut = swapRouter.getAmountOut(cNGN, p.tokenOut, amountInCNGN);
        if (expectedOut == 0) revert InsufficientLiquidity();

        uint256 adjustedMinOut = (expectedOut * (BASIS_POINTS - slippageBps)) / BASIS_POINTS;
        uint256 effectiveMinOut = adjustedMinOut > p.minAmountOut ? adjustedMinOut : p.minAmountOut;

        _cngn.forceApprove(address(swapRouter), amountInCNGN);

        IERC20 _out = IERC20(p.tokenOut);
        uint256 outBefore = _out.balanceOf(address(this));

        swapRouter.swapExactTokensForTokens(cNGN, p.tokenOut, amountInCNGN, effectiveMinOut, p.deadline);

        amountOut = _out.balanceOf(address(this)) - outBefore;
        if (amountOut < effectiveMinOut) revert SwapFailed();

        _out.safeTransfer(msg.sender, amountOut);

        emit WithdrawnAndSwapped(_pool, msg.sender, p.tokenId, amountInCNGN, p.tokenOut, amountOut);
    }

    function withdraw(address pool, uint256 tokenId, uint256 lpTokenAmount)
        external
        nonReentrant
        returns (uint256 withdrawAmount)
    {
        if (!isRegisteredPool[pool]) revert InvalidPool();

        address lpToken = poolInfo[pool].lpToken;
        IERC20(lpToken).transferFrom(msg.sender, pool, lpTokenAmount);

        withdrawAmount = IInvestmentPool(pool).withdraw(msg.sender, tokenId, lpTokenAmount);
    }

    // ============ VIEW FUNCTIONS ============

    function getAllPools() external view returns (address[] memory) {
        return allPools;
    }

    function getActivePools() external view returns (address[] memory) {
        address[] memory allPoolsMemory = allPools;
        uint256 activeCount = 0;

        for (uint256 i = 0; i < allPoolsMemory.length; i++) {
            if (poolInfo[allPoolsMemory[i]].isActive) activeCount++;
        }

        address[] memory activePools = new address[](activeCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allPoolsMemory.length; i++) {
            if (poolInfo[allPoolsMemory[i]].isActive) {
                activePools[index++] = allPoolsMemory[i];
            }
        }

        return activePools;
    }

    function checkSwapLiquidity(address tokenIn, uint256 amountIn)
        external
        returns (uint256 expectedOut, bool hasLiquidity)
    {
        expectedOut = swapRouter.getAmountOut(tokenIn, cNGN, amountIn);
        hasLiquidity = expectedOut > 0;
    }

    // ============ ADMIN SETTER FUNCTIONS ============

    function setPoolFactory(address _factory) external onlyRole(ADMIN_ROLE) {
        if (_factory == address(0)) revert InvalidAddress();
        poolFactory = IPoolFactory(_factory);
    }

    function setTaxCollector(address _collector) external onlyRole(ADMIN_ROLE) {
        if (_collector == address(0)) revert InvalidAddress();
        taxCollector = ITaxCollector(_collector);
    }

    function setSwapRouter(address _router) external onlyRole(ADMIN_ROLE) {
        if (_router == address(0)) revert InvalidAddress();
        swapRouter = ISwapRouter(_router);
    }

    function setNFTManager(address _manager) external onlyRole(ADMIN_ROLE) {
        if (_manager == address(0)) revert InvalidAddress();
        nftManager = INFTPositionManager(_manager);
    }

    function setPoolActive(address pool, bool active) external onlyRole(ADMIN_ROLE) {
        if (!isRegisteredPool[pool]) revert InvalidPool();
        poolInfo[pool].isActive = active;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
