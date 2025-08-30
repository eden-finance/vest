// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/IInvestmentPool.sol";
import "./interfaces/ILPToken.sol";
import "./interfaces/IEdenCore.sol";
import "./interfaces/INFTPositionManager.sol";

/**
 * @title InvestmentPool
 * @notice Individual investment pool implementation
 * @dev Manages investments, withdrawals, and pool-specific configurations
 */
contract InvestmentPool is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IInvestmentPool
{
    using SafeERC20 for IERC20;

    // ============ ROLES ============
    bytes32 public constant POOL_ADMIN_ROLE = keccak256("POOL_ADMIN_ROLE");
    bytes32 public constant MULTISIG_ROLE = keccak256("MULTISIG_ROLE");

    // ============ CONSTANTS ============
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_LOCK_DURATION = 3 minutes;
    uint256 public constant MAX_LOCK_DURATION = 730 days; // 2 years

    // ============ STATE VARIABLES ============
    address public override lpToken;
    address public cNGN;
    address public poolMultisig;
    address public nftManager;
    address public edenCore;

    PoolConfig public poolConfig;
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public nextInvestmentId;

    uint8 public cngnDecimals;
    uint8 public lpDecimals;
    uint256 public scaleFactor;
    uint256 public totalDepositedScaled;

    mapping(uint256 => Investment) public investments;
    mapping(address => uint256[]) public userInvestments;
    mapping(uint256 => uint256) public nftToInvestment;

    // ============ MODIFIERS ============
    modifier onlyEdenCore() {
        require(msg.sender == edenCore, "Only Eden Core");
        _;
    }

    modifier validInvestment(uint256 investmentId) {
        require(investmentId < nextInvestmentId, "Invalid investment");
        _;
    }

    event TokensSwept(address indexed token, uint256 amount, address indexed to, address indexed operator);
    event NativeSwept(uint256 amount, address indexed to, address indexed operator);

    function initialize(InitParams memory params) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        require(params.lpToken != address(0), "Invalid LP token");
        require(params.cNGN != address(0), "Invalid cNGN");
        require(params.poolMultisig != address(0), "Invalid multisig");
        require(params.nftManager != address(0), "Invalid NFT manager");
        require(params.edenCore != address(0), "Invalid Eden Core");
        require(params.admin != address(0), "Invalid admin");

        // Validate configuration
        require(params.lockDuration >= MIN_LOCK_DURATION, "Lock duration too short");
        require(params.lockDuration <= MAX_LOCK_DURATION, "Lock duration too long");
        require(params.minInvestment > 0, "Invalid min investment");
        require(params.maxInvestment >= params.minInvestment, "Invalid max investment");
        require(params.expectedRate <= 10000, "Expected rate too high"); // Max 100% APY
        require(params.taxRate <= 1000, "Tax rate too high"); // Max 10%
        require(bytes(params.name).length > 0, "Invalid name");

        lpToken = params.lpToken;
        cNGN = params.cNGN;
        poolMultisig = params.poolMultisig;
        nftManager = params.nftManager;
        edenCore = params.edenCore;

        poolConfig = PoolConfig({
            name: params.name,
            lockDuration: params.lockDuration,
            minInvestment: params.minInvestment,
            maxInvestment: params.maxInvestment,
            utilizationCap: params.utilizationCap,
            expectedRate: params.expectedRate,
            taxRate: params.taxRate,
            acceptingDeposits: true
        });

        lpDecimals = IERC20Metadata(lpToken).decimals();
        cngnDecimals = IERC20Metadata(cNGN).decimals();

        scaleFactor = 10 ** (lpDecimals - cngnDecimals);

        _grantRole(DEFAULT_ADMIN_ROLE, params.admin);
        _grantRole(POOL_ADMIN_ROLE, params.admin);

        for (uint256 i = 0; i < params.multisigSigners.length; i++) {
            _grantRole(MULTISIG_ROLE, params.multisigSigners[i]);
        }
    }

    // ============ INVESTMENT FUNCTIONS ============

    /**
     * @notice Process investment (called by EdenCore)
     * @param investor Investor address
     * @param amount Investment amount
     * @param title Investment title
     * @return tokenId NFT token ID
     * @return userLPTokens LP tokens minted
     * @return taxAmount tokens minted for tax
     */
    function invest(address investor, uint256 amount, string memory title)
        external
        override
        onlyEdenCore
        nonReentrant
        whenNotPaused
        returns (uint256 tokenId, uint256 userLPTokens, uint256 taxAmount)
    {
        require(poolConfig.acceptingDeposits, "Deposits paused");
        require(amount >= poolConfig.minInvestment, "Below minimum");
        require(amount <= poolConfig.maxInvestment, "Exceeds maximum");

        if (poolConfig.utilizationCap > 0) {
            require(totalDeposited + amount <= poolConfig.utilizationCap, "Exceeds cap");
        }

        uint256 investmentId = nextInvestmentId++;
        uint256 maturityTime = block.timestamp + poolConfig.lockDuration;
        uint256 expectedInterest = _calculateExpectedReturn(amount);

        uint256 totalLPTokens;
        uint256 ts = IERC20(lpToken).totalSupply();
        uint256 amountScaled = amount * scaleFactor;

        if (ts == 0 || totalDepositedScaled == 0) {
            totalLPTokens = amountScaled;
        } else {
            totalLPTokens = (amountScaled * ts) / totalDepositedScaled;
        }

        uint256 poolTaxRate = IInvestmentPool(address(this)).taxRate();
        IEdenCore edenCore_ = IEdenCore(edenCore);

        uint256 effectiveTaxRate = poolTaxRate > 0 ? poolTaxRate : edenCore_.globalTaxRate();

        taxAmount = (totalLPTokens * effectiveTaxRate) / BASIS_POINTS;
        userLPTokens = totalLPTokens - taxAmount;
        address taxCollector = edenCore_.taxCollector();

        uint256 expectedReturn = expectedInterest + amount;

        investments[investmentId] = Investment({
            investor: investor,
            amount: amount,
            title: title,
            depositTime: block.timestamp,
            maturityTime: maturityTime,
            expectedReturn: expectedReturn,
            isWithdrawn: false,
            lpTokens: userLPTokens,
            actualReturn: 0
        });

        userInvestments[investor].push(investmentId);
        totalDeposited += amount;
        totalDepositedScaled += amountScaled;

        ILPToken(lpToken).mint(investor, userLPTokens);
        ILPToken(lpToken).mint(taxCollector, taxAmount);

        tokenId = INFTPositionManager(nftManager).mintPosition(
            investor,
            address(this),
            investmentId,
            amount,
            maturityTime,
            expectedReturn,
            poolConfig.expectedRate,
            block.timestamp
        );

        nftToInvestment[tokenId] = investmentId;

        // Transfer funds to multisig
        IERC20(cNGN).safeTransferFrom(edenCore, poolMultisig, amount);

        emit InvestmentCreated(
            investmentId, investor, amount, userLPTokens, tokenId, expectedReturn, maturityTime, title
        );
    }

    /**
     * @notice Process withdrawal
     * @param investor Investor address
     * @param tokenId NFT token ID
     * @param lpAmount LP tokens to burn
     * @return withdrawAmount Total withdrawal amount
     */
    function withdraw(address investor, uint256 tokenId, uint256 lpAmount)
        external
        override
        onlyEdenCore
        nonReentrant
        returns (uint256 withdrawAmount)
    {
        uint256 investmentId = nftToInvestment[tokenId];
        Investment storage investment = investments[investmentId];

        require(investment.investor == investor, "Not owner");
        require(!investment.isWithdrawn, "Already withdrawn");
        require(block.timestamp >= investment.maturityTime, "Not matured");
        require(IERC721(nftManager).ownerOf(tokenId) == investor, "NFT not owned");

        uint256 requiredLPTokens = investment.lpTokens;
        require(lpAmount >= investment.lpTokens, "Insufficient LP tokens");

        investment.isWithdrawn = true;

        uint256 expectedInterest = _calculateExpectedReturn(investment.amount);

        withdrawAmount += investment.amount + expectedInterest;
        totalDepositedScaled -= investment.amount * scaleFactor;
        totalDeposited -= investment.amount;

        require(IERC20(lpToken).balanceOf(address(this)) >= requiredLPTokens, "LP tokens not received");

        ILPToken(lpToken).burn(address(this), requiredLPTokens);

        INFTPositionManager(nftManager).burnPosition(tokenId);

        require(IERC20(cNGN).balanceOf(address(this)) >= withdrawAmount, "Insufficient pool balance");

        IERC20(cNGN).safeTransfer(investment.investor, withdrawAmount);

        emit InvestmentWithdrawn(investmentId, investor, withdrawAmount);
    }

    // ============ ADMIN FUNCTIONS ============
    /**
     * @notice Update pool configuration
     * @param config New configuration
     */
    function updatePoolConfig(PoolConfig memory config) external onlyRole(POOL_ADMIN_ROLE) {
        require(config.lockDuration >= MIN_LOCK_DURATION, "Duration too short");
        require(config.lockDuration <= MAX_LOCK_DURATION, "Duration too long");
        require(config.minInvestment > 0, "Invalid min investment");
        require(config.maxInvestment >= config.minInvestment, "Invalid max investment");
        require(config.expectedRate <= 10000, "Rate too high"); // Max 100% APY

        poolConfig = config;
        emit PoolConfigUpdated(config);
    }

    /**
     * @notice Update pool multisig
     * @param newMultisig New multisig address
     */
    function updatePoolMultisig(address newMultisig) external onlyRole(POOL_ADMIN_ROLE) {
        require(newMultisig != address(0), "Invalid address");
        poolMultisig = newMultisig;
        emit PoolMultisigUpdated(newMultisig);
    }

    /**
     * @notice Toggle accepting deposits
     * @param accepting Whether to accept deposits
     */
    function setAcceptingDeposits(bool accepting) external onlyRole(POOL_ADMIN_ROLE) {
        bool oldState = poolConfig.acceptingDeposits;
        poolConfig.acceptingDeposits = accepting;

        if (oldState != accepting) {
            emit DepositsToggled(accepting, msg.sender);
        }
    }

    /**
     * @notice Pause pool
     */
    function pause() external onlyRole(POOL_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause pool
     */
    function unpause() external onlyRole(POOL_ADMIN_ROLE) {
        _unpause();
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get pool configuration
     */
    function getPoolConfig() external view returns (PoolConfig memory) {
        return poolConfig;
    }

    /**
     * @notice Get investment details
     */
    function getInvestment(uint256 investmentId) external view returns (Investment memory) {
        return investments[investmentId];
    }

    /**
     * @notice Get user investments
     */
    function getUserInvestments(address user) external view returns (uint256[] memory) {
        return userInvestments[user];
    }

    /**
     * @notice Get pool statistics
     */
    function getPoolStats()
        external
        view
        returns (uint256 deposited, uint256 withdrawn, uint256 available, uint256 utilization)
    {
        deposited = totalDeposited;
        withdrawn = totalWithdrawn;

        if (poolConfig.utilizationCap > 0) {
            available = poolConfig.utilizationCap - totalDeposited;
            utilization = (totalDeposited * BASIS_POINTS) / poolConfig.utilizationCap;
        } else {
            available = type(uint256).max;
            utilization = 0;
        }
    }

    /**
     * @notice Get tax rate
     */
    function taxRate() external view override returns (uint256) {
        return poolConfig.taxRate;
    }

    /**
     * @notice Check if investment can be withdrawn
     */
    function isWithdrawable(uint256 tokenId) external view returns (bool) {
        uint256 investmentId = nftToInvestment[tokenId];
        Investment memory investment = investments[investmentId];

        return !investment.isWithdrawn && block.timestamp >= investment.maturityTime;
    }

    // ============ INTERNAL FUNCTIONS ============

    /**
     * @dev Calculate expected return
     */
    function _calculateExpectedReturn(uint256 amount) internal view returns (uint256) {
        uint256 timeInSeconds = poolConfig.lockDuration;
        return (amount * poolConfig.expectedRate * timeInSeconds) / (BASIS_POINTS * 365 days);
    }

    /**
     * @dev Calculate LP tokens to mint
     */
    function _calculateLPTokens(uint256 amount) internal view returns (uint256) {
        uint256 ts = IERC20(lpToken).totalSupply(); // 18 dp
        uint256 amountScaled = amount * scaleFactor; // 18 dp

        if (ts == 0 || totalDepositedScaled == 0) {
            return amountScaled;
        }
        return (amountScaled * ts) / totalDepositedScaled;
    }

    /**
     * @notice Sweep arbitrary ERC20 tokens from the pool to a recipient
     * @dev For safety:
     *      - Never sweep LP token
     *      - Sweeping cNGN only allowed while PAUSED
     */
    function sweepERC20(address token, address to, uint256 amount) external onlyRole(MULTISIG_ROLE) nonReentrant {
        require(to != address(0), "Invalid to");
        require(amount > 0, "Zero amount");
        require(token != lpToken, "Cannot sweep LP token");

        // Protect user funds: only allow cNGN sweep if pool is paused
        if (token == cNGN) {
            require(paused(), "Pause required to sweep cNGN");
        }

        IERC20(token).safeTransfer(to, amount);
        emit TokensSwept(token, amount, to, msg.sender);
    }

    /**
     * @notice Sweep native RWA from the pool to a recipient
     * @dev Only allowed while PAUSED to avoid impacting live operations
     */
    function sweepNative(address payable to, uint256 amount) external onlyRole(MULTISIG_ROLE) nonReentrant {
        require(to != address(0), "Invalid to");
        require(amount > 0, "Zero amount");
        require(paused(), "Pause required to sweep ETH");

        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");
        emit NativeSwept(amount, to, msg.sender);
    }
}
