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
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

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
    UUPSUpgradeable,
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
    uint256 public constant MAX_LOCK_DURATION = 730 days;

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
    event Redeemed(address indexed user, uint256 lpAmount, uint256 redeemAmount);

    function initialize(InitParams memory params) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        require(params.lpToken != address(0), "Invalid LP token");
        require(params.cNGN != address(0), "Invalid cNGN");
        require(params.poolMultisig != address(0), "Invalid multisig");
        require(params.nftManager != address(0), "Invalid NFT manager");
        require(params.edenCore != address(0), "Invalid Eden Core");
        require(params.admin != address(0), "Invalid admin");

        require(params.lockDuration >= MIN_LOCK_DURATION, "Lock duration too short");
        require(params.lockDuration <= MAX_LOCK_DURATION, "Lock duration too long");
        require(params.minInvestment > 0, "Invalid min investment");
        require(params.maxInvestment >= params.minInvestment, "Invalid max investment");
        require(params.expectedRate <= 10000, "Expected rate too high");
        require(params.taxRate <= 1000, "Tax rate too high");
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

        if (lpDecimals >= cngnDecimals) {
            scaleFactor = 10 ** (lpDecimals - cngnDecimals);
        } else {
            scaleFactor = 1;
        }

        _grantRole(DEFAULT_ADMIN_ROLE, params.admin);
        _grantRole(POOL_ADMIN_ROLE, params.admin);

        for (uint256 i = 0; i < params.multisigSigners.length; i++) {
            _grantRole(MULTISIG_ROLE, params.multisigSigners[i]);
        }
    }
    /**
     * @notice Process investment
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

        IERC20(cNGN).safeTransferFrom(edenCore, poolMultisig, amount);

        uint256 investmentId = nextInvestmentId++;
        uint256 maturityTime = block.timestamp + poolConfig.lockDuration;
        uint256 interest = _calculateExpectedReturn(amount);
        uint256 grossReturn = amount + interest;

        uint256 amountScaled = amount * scaleFactor;
        uint256 poolTaxRate = IInvestmentPool(address(this)).taxRate();
        IEdenCore edenCore_ = IEdenCore(edenCore);
        uint256 taxBps = poolTaxRate > 0 ? poolTaxRate : edenCore_.globalTaxRate();

        uint256 taxLp = (amountScaled * taxBps) / BASIS_POINTS;
        uint256 userLp = amountScaled - taxLp;

        address taxCollector = edenCore_.taxCollector();

        investments[investmentId] = Investment({
            investor: investor,
            amount: amount,
            estimatedReturn: grossReturn,
            title: title,
            depositTime: block.timestamp,
            maturityTime: maturityTime,
            isWithdrawn: false,
            userLpRequired: userLp,
            taxWithdrawn: false,
            taxLpRequired: taxLp,
            actualReturn: 0,
            actualInterest: 0,
            totalLpForPosition: userLp + taxLp
        });
        userLPTokens = userLp;
        taxAmount = taxLp;

        userInvestments[investor].push(investmentId);
        totalDeposited += amount;

        ILPToken(lpToken).mint(investor, userLp);
        ILPToken(lpToken).mint(taxCollector, taxLp);

        tokenId = INFTPositionManager(nftManager).mintPosition(
            investor,
            address(this),
            investmentId,
            amount,
            maturityTime,
            grossReturn,
            poolConfig.expectedRate,
            block.timestamp
        );

        nftToInvestment[tokenId] = investmentId;

        emit InvestmentCreated(investmentId, investor, amount, userLPTokens, tokenId, grossReturn, maturityTime, title);
    }

    function reportActualInterestBatch(uint256[] calldata ids, uint256[] calldata interests)
        external
        onlyRole(POOL_ADMIN_ROLE)
    {
        require(ids.length == interests.length, "len mismatch");
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            Investment storage inv = investments[id];
            if (id >= nextInvestmentId) continue;
            if (block.timestamp < inv.maturityTime) continue;
            if (inv.actualInterest != 0) continue;
            inv.actualInterest = interests[i];
        }
    }

    function _interestFor(Investment storage inv) internal view returns (uint256) {
        if (inv.actualInterest > 0) {
            return inv.actualInterest;
        }
        uint256 aprBps = poolConfig.expectedRate;
        uint256 lockSeconds = inv.maturityTime - inv.depositTime;
        return (inv.amount * aprBps * lockSeconds) / (BASIS_POINTS * 365 days);
    }

    function collectTax(uint256 investmentId)
        external
        nonReentrant
        onlyRole(POOL_ADMIN_ROLE)
        returns (uint256 taxPaid)
    {
        Investment storage inv = investments[investmentId];
        require(block.timestamp >= inv.maturityTime, "Not matured");
        require(!inv.taxWithdrawn, "Tax already withdrawn");

        uint256 taxLp = inv.taxLpRequired;
        require(taxLp > 0, "No tax LP");

        uint256 interest = _interestFor(inv);
        uint256 taxShare = (interest * inv.taxLpRequired) / inv.totalLpForPosition;
        require(IERC20(cNGN).balanceOf(address(this)) >= taxShare, "Insufficient liquidity");

        ILPToken(lpToken).burn(IEdenCore(edenCore).taxCollector(), taxLp);

        inv.taxWithdrawn = true;

        IERC20(cNGN).safeTransfer(msg.sender, taxShare);

        emit Redeemed(msg.sender, taxLp, taxShare);
        return taxShare;
    }

    /// @notice Collect tax for many matured investments in one call
    function collectTaxBatch(uint256[] calldata ids, address to)
        external
        nonReentrant
        onlyRole(POOL_ADMIN_ROLE)
        returns (uint256 totalPaid, uint256 processed)
    {
        require(to != address(0), "bad to");

        address taxLpHolder = IEdenCore(edenCore).taxCollector();

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            if (id >= nextInvestmentId) continue;

            Investment storage inv = investments[id];
            if (inv.taxWithdrawn) continue;
            if (block.timestamp < inv.maturityTime) continue;

            uint256 taxLp = inv.taxLpRequired;
            if (taxLp == 0) {
                inv.taxWithdrawn = true;
                continue;
            }

            uint256 interest = _interestFor(inv);
            uint256 taxShare = (interest * taxLp) / inv.totalLpForPosition;
            if (IERC20(cNGN).balanceOf(address(this)) < taxShare) {
                break;
            }

            ILPToken(lpToken).burn(taxLpHolder, taxLp);

            inv.taxWithdrawn = true;
            totalPaid += taxShare;
            processed += 1;

            emit Redeemed(taxLpHolder, taxLp, taxShare);
        }

        if (totalPaid > 0) {
            IERC20(cNGN).safeTransfer(to, totalPaid);
        }
    }

    function pendingTaxClaims(uint256 offset, uint256 limit)
        external
        view
        returns (uint256[] memory ids, uint256[] memory taxLp, uint256[] memory taxShare)
    {
        uint256 n = nextInvestmentId;
        uint256 end = offset + limit;
        if (end > n) end = n;

        uint256 count;
        for (uint256 i = offset; i < end; i++) {
            Investment memory inv = investments[i];
            if (!inv.taxWithdrawn && block.timestamp >= inv.maturityTime && inv.taxLpRequired > 0) count++;
        }

        ids = new uint256[](count);
        taxLp = new uint256[](count);
        taxShare = new uint256[](count);

        uint256 k;
        for (uint256 i = offset; i < end; i++) {
            Investment memory inv = investments[i];
            if (!inv.taxWithdrawn && block.timestamp >= inv.maturityTime && inv.taxLpRequired > 0) {
                ids[k] = i;
                taxLp[k] = inv.taxLpRequired;
                uint256 interest = _interestFor(investments[i]);
                taxShare[k] = (interest * inv.taxLpRequired) / inv.totalLpForPosition;
                k++;
            }
        }
    }

    function withdraw(address investor, uint256 tokenId, uint256 lpAmount)
        external
        override
        onlyEdenCore
        nonReentrant
        returns (uint256 userPaid)
    {
        uint256 investmentId = nftToInvestment[tokenId];
        Investment storage inv = investments[investmentId];

        require(IERC721(nftManager).ownerOf(tokenId) == investor, "Not owner");
        require(!inv.isWithdrawn, "Already withdrawn");
        require(block.timestamp >= inv.maturityTime, "Not matured");

        require(lpAmount == inv.userLpRequired, "LP must equal position LP");
        require(IERC20(lpToken).balanceOf(address(this)) >= lpAmount, "LP not received");

        uint256 interest = _interestFor(inv);
        uint256 userInterest = (interest * inv.userLpRequired) / inv.totalLpForPosition;
        uint256 userShare = inv.amount + userInterest;

        require(IERC20(cNGN).balanceOf(address(this)) >= userShare, "Insufficient liquidity");

        ILPToken(lpToken).burn(address(this), lpAmount);

        inv.isWithdrawn = true;

        totalDeposited -= inv.amount;
        totalWithdrawn += userShare;

        INFTPositionManager(nftManager).burnPosition(tokenId);

        IERC20(cNGN).safeTransfer(investor, userShare);

        emit InvestmentWithdrawn(investmentId, investor, userShare);
        return userShare;
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

    function taxRate() external view override returns (uint256) {
        return poolConfig.taxRate;
    }

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
     * @notice Sweep arbitrary ERC20 tokens from the pool to a recipient
     * @dev For safety
     */
    function sweepERC20(address token, address to, uint256 amount) external onlyRole(POOL_ADMIN_ROLE) nonReentrant {
        require(to != address(0), "Invalid to");
        require(amount > 0, "Zero amount");
        require(token != lpToken, "Cannot sweep LP token");

        IERC20(token).safeTransfer(to, amount);
        emit TokensSwept(token, amount, to, msg.sender);
    }

    /**
     * @notice Sweep native RWA from the pool to a recipient
     */
    function sweepNative(address payable to, uint256 amount) external onlyRole(POOL_ADMIN_ROLE) nonReentrant {
        require(to != address(0), "Invalid to");
        require(amount > 0, "Zero amount");

        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");
        emit NativeSwept(amount, to, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(POOL_ADMIN_ROLE) {}

    // uint256[50] private __gap;
}
