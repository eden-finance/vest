// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
    uint256 public constant MIN_LOCK_DURATION = 7 days;
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

    // ============ INITIALIZATION ============
    function initialize(InitParams memory params) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

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

        _grantRole(DEFAULT_ADMIN_ROLE, params.admin);
        _grantRole(POOL_ADMIN_ROLE, params.admin);

        // Grant multisig roles
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
     * @return totalLPTokens LP tokens minted
     */
    function invest(address investor, uint256 amount, string memory title)
        external
        override
        onlyEdenCore
        nonReentrant
        whenNotPaused
        returns (uint256 tokenId, uint256 totalLPTokens)
    {
        require(poolConfig.acceptingDeposits, "Deposits paused");
        require(amount >= poolConfig.minInvestment, "Below minimum");
        require(amount <= poolConfig.maxInvestment, "Exceeds maximum");

        if (poolConfig.utilizationCap > 0) {
            require(totalDeposited + amount <= poolConfig.utilizationCap, "Exceeds cap");
        }

        uint256 investmentId = nextInvestmentId++;
        uint256 maturityTime = block.timestamp + poolConfig.lockDuration;
        uint256 expectedReturn = _calculateExpectedReturn(amount);

        // Mint LP tokens
        totalLPTokens = _calculateLPTokens(amount);

        uint256 poolTaxRate = IInvestmentPool(address(this)).taxRate();
        IEdenCore edenCore_ = IEdenCore(edenCore);

        uint256 effectiveTaxRate = poolTaxRate > 0 ? poolTaxRate : edenCore_.globalTaxRate();

        uint256 taxAmount = (totalLPTokens * effectiveTaxRate) / BASIS_POINTS;
        uint256 userLPTokens = totalLPTokens - taxAmount;

        investments[investmentId] = Investment({
            investor: investor,
            amount: amount,
            title: title,
            depositTime: block.timestamp,
            maturityTime: maturityTime,
            expectedReturn: expectedReturn,
            isWithdrawn: false,
            lpTokens: userLPTokens
        });

        userInvestments[investor].push(investmentId);
        totalDeposited += amount;
        ILPToken(lpToken).mint(investor, userLPTokens);
        ILPToken(lpToken).mint(edenCore, taxAmount); // Send tax portion directly to EdenCore

        // Mint NFT
        tokenId =
            INFTPositionManager(nftManager).mintPosition(investor, address(this), investmentId, amount, maturityTime);

        nftToInvestment[tokenId] = investmentId;

        // Transfer funds to multisig
        IERC20(cNGN).safeTransferFrom(edenCore, poolMultisig, amount);

        emit InvestmentCreated(investmentId, investor, amount, totalLPTokens, tokenId);
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

        withdrawAmount += investment.expectedReturn;

        // Burn LP tokens
        ILPToken(lpToken).burn(address(this), requiredLPTokens);

        // Burn NFT
        INFTPositionManager(nftManager).burnPosition(tokenId);

        // Check pool has sufficient balance
        require(IERC20(cNGN).balanceOf(address(this)) >= withdrawAmount, "Insufficient pool balance");

        // Transfer funds from pool to investor
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
        poolConfig.acceptingDeposits = accepting;
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
        available = poolConfig.utilizationCap > 0 ? poolConfig.utilizationCap - totalDeposited : type(uint256).max;
        utilization = totalDeposited > 0 ? (totalDeposited * BASIS_POINTS) / poolConfig.utilizationCap : 0;
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
        uint256 totalSupply = IERC20(lpToken).totalSupply();

        if (totalSupply == 0) {
            // First deposit
            return amount;
        } else {
            // Proportional to pool share
            return (amount * totalSupply) / totalDeposited;
        }
    }
}
