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

    // ============ CUSTOM ERRORS ============
    error OnlyEdenCore();
    error DepositsPaused();
    error BelowMin();
    error AboveMax();
    error ExceedsCap();
    error InvalidOwner();
    error AlreadyWithdrawn();
    error NotMatured();
    error LPNotReceived();
    error InsufficientLiquidity();
    error ZeroAddress();
    error ZeroAmount();
    error BadTo();
    error DurationTooShort();
    error DurationTooLong();
    error MaxLessThanMin();
    error RateTooHigh();
    error TaxRateTooHigh();
    error InvalidName();
    error CannotSweepLPToken();

    // ============ STORAGE ============
    mapping(uint256 => Investment) public investments;
    mapping(address => uint256[]) public userInvestments;
    mapping(uint256 => uint256) public nftToInvestment;

    // ============ EVENTS ============
    event TokensSwept(address indexed token, uint256 amount, address indexed to, address indexed operator);
    event NativeSwept(uint256 amount, address indexed to, address indexed operator);
    event Redeemed(address indexed user, uint256 lpAmount, uint256 redeemAmount);

    // ============ MODIFIERS ============
    modifier onlyEdenCore() {
        if (msg.sender != edenCore) revert OnlyEdenCore();
        _;
    }

    // ============ INITIALIZER ============
    function initialize(InitParams memory params) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        if (params.lpToken == address(0)) revert ZeroAddress();
        if (params.cNGN == address(0)) revert ZeroAddress();
        if (params.poolMultisig == address(0)) revert ZeroAddress();
        if (params.nftManager == address(0)) revert ZeroAddress();
        if (params.edenCore == address(0)) revert ZeroAddress();
        if (params.admin == address(0)) revert ZeroAddress();

        if (params.lockDuration < MIN_LOCK_DURATION) revert DurationTooShort();
        if (params.lockDuration > MAX_LOCK_DURATION) revert DurationTooLong();
        if (params.minInvestment == 0) revert ZeroAmount();
        if (params.maxInvestment < params.minInvestment) revert MaxLessThanMin();
        if (params.expectedRate > 10000) revert RateTooHigh();
        if (params.taxRate > 1000) revert TaxRateTooHigh();
        if (bytes(params.name).length == 0) revert InvalidName();

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
        scaleFactor = lpDecimals >= cngnDecimals ? 10 ** (lpDecimals - cngnDecimals) : 1;

        _grantRole(DEFAULT_ADMIN_ROLE, params.admin);
        _grantRole(POOL_ADMIN_ROLE, params.admin);

        for (uint256 i = 0; i < params.multisigSigners.length; i++) {
            _grantRole(MULTISIG_ROLE, params.multisigSigners[i]);
        }
    }

    // ============ CORE ============
    /**
     * @notice Process investment
     */
    function invest(address investor, uint256 amount, string memory title)
        external
        override
        onlyEdenCore
        nonReentrant
        whenNotPaused
        returns (uint256 tokenId, uint256 userLPTokens, uint256 taxAmount)
    {
        if (!poolConfig.acceptingDeposits) revert DepositsPaused();
        if (amount < poolConfig.minInvestment) revert BelowMin();
        if (amount > poolConfig.maxInvestment) revert AboveMax();
        if (poolConfig.utilizationCap > 0 && totalDeposited + amount > poolConfig.utilizationCap) revert ExceedsCap();

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

    /**
     * @notice Emergency withdraw principal before maturity (no interest)
     *         Burns user LP and tax LP (if any), returns principal to investor.
     */
    function emergencyWithdraw(address investor, uint256 tokenId, uint256 lpAmount)
        external
        onlyEdenCore
        nonReentrant
        returns (uint256 principalPaid)
    {
        uint256 investmentId = nftToInvestment[tokenId];
        Investment storage inv = investments[investmentId];

        if (IERC721(nftManager).ownerOf(tokenId) != investor) revert InvalidOwner();
        if (inv.isWithdrawn) revert AlreadyWithdrawn();

        if (lpAmount != inv.userLpRequired) revert LPNotReceived(); // reuse error for brevity
        if (IERC20(lpToken).balanceOf(address(this)) < lpAmount) revert LPNotReceived();

        principalPaid = inv.amount;
        if (IERC20(cNGN).balanceOf(address(this)) < principalPaid) revert InsufficientLiquidity();

        ILPToken(lpToken).burn(address(this), lpAmount);

        if (!inv.taxWithdrawn && inv.taxLpRequired > 0) {
            address taxHolder = IEdenCore(edenCore).taxCollector();
            ILPToken(lpToken).burn(taxHolder, inv.taxLpRequired);
            inv.taxWithdrawn = true;
        }

        inv.isWithdrawn = true;

        totalDeposited -= inv.amount;
        totalWithdrawn += principalPaid;

        INFTPositionManager(nftManager).burnPosition(tokenId);

        IERC20(cNGN).safeTransfer(investor, principalPaid);

        emit EmergencyWithdrawn(investmentId, investor, principalPaid);
    }

    /**
     * @notice Report actual interest for a batch of investments
     */
    function reportActualInterestBatch(uint256[] calldata ids, uint256[] calldata interests)
        external
        onlyRole(POOL_ADMIN_ROLE)
    {
        if (ids.length != interests.length) revert BadTo(); // reuse small error
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
        if (block.timestamp < inv.maturityTime) revert NotMatured();
        if (inv.taxWithdrawn) revert AlreadyWithdrawn();

        uint256 taxLp = inv.taxLpRequired;
        if (taxLp == 0) revert ZeroAmount();

        uint256 interest = _interestFor(inv);
        uint256 taxShare = (interest * inv.taxLpRequired) / inv.totalLpForPosition;
        if (IERC20(cNGN).balanceOf(address(this)) < taxShare) revert InsufficientLiquidity();

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
        if (to == address(0)) revert BadTo();

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

    function withdraw(address investor, uint256 tokenId, uint256 lpAmount)
        external
        override
        onlyEdenCore
        nonReentrant
        returns (uint256 userPaid)
    {
        uint256 investmentId = nftToInvestment[tokenId];
        Investment storage inv = investments[investmentId];

        if (IERC721(nftManager).ownerOf(tokenId) != investor) revert InvalidOwner();
        if (inv.isWithdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < inv.maturityTime) revert NotMatured();

        if (lpAmount != inv.userLpRequired) revert LPNotReceived(); // reuse error
        if (IERC20(lpToken).balanceOf(address(this)) < lpAmount) revert LPNotReceived();

        uint256 interest = _interestFor(inv);
        uint256 userInterest = (interest * inv.userLpRequired) / inv.totalLpForPosition;
        uint256 userShare = inv.amount + userInterest;

        if (IERC20(cNGN).balanceOf(address(this)) < userShare) revert InsufficientLiquidity();

        ILPToken(lpToken).burn(address(this), lpAmount);

        inv.isWithdrawn = true;

        totalDeposited -= inv.amount;
        totalWithdrawn += userShare;

        INFTPositionManager(nftManager).burnPosition(tokenId);

        IERC20(cNGN).safeTransfer(investor, userShare);

        emit InvestmentWithdrawn(investmentId, investor, userShare);
        return userShare;
    }

    // ============ ADMIN ============
    function updatePoolConfig(PoolConfig memory config) external onlyRole(POOL_ADMIN_ROLE) {
        if (config.lockDuration < MIN_LOCK_DURATION) revert DurationTooShort();
        if (config.lockDuration > MAX_LOCK_DURATION) revert DurationTooLong();
        if (config.minInvestment == 0) revert ZeroAmount();
        if (config.maxInvestment < config.minInvestment) revert MaxLessThanMin();
        if (config.expectedRate > 10000) revert RateTooHigh();

        poolConfig = config;
        emit PoolConfigUpdated(config);
    }

    function updatePoolMultisig(address newMultisig) external onlyRole(POOL_ADMIN_ROLE) {
        if (newMultisig == address(0)) revert ZeroAddress();
        poolMultisig = newMultisig;
        emit PoolMultisigUpdated(newMultisig);
    }

    function setAcceptingDeposits(bool accepting) external onlyRole(POOL_ADMIN_ROLE) {
        bool oldState = poolConfig.acceptingDeposits;
        poolConfig.acceptingDeposits = accepting;
        if (oldState != accepting) {
            emit DepositsToggled(accepting, msg.sender);
        }
    }

    function pause() external onlyRole(POOL_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(POOL_ADMIN_ROLE) {
        _unpause();
    }

    // ============ VIEW ============
    function getPoolConfig() external view returns (PoolConfig memory) {
        return poolConfig;
    }

    function getInvestment(uint256 investmentId) external view returns (Investment memory) {
        return investments[investmentId];
    }

    function getUserInvestments(address user) external view returns (uint256[] memory) {
        return userInvestments[user];
    }

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

    // ============ INTERNAL ============
    function _calculateExpectedReturn(uint256 amount) internal view returns (uint256) {
        uint256 timeInSeconds = poolConfig.lockDuration;
        return (amount * poolConfig.expectedRate * timeInSeconds) / (BASIS_POINTS * 365 days);
    }

    function sweepERC20(address token, address to, uint256 amount) external onlyRole(POOL_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (token == lpToken) revert CannotSweepLPToken();

        IERC20(token).safeTransfer(to, amount);
        emit TokensSwept(token, amount, to, msg.sender);
    }

    function sweepNative(address payable to, uint256 amount) external onlyRole(POOL_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        (bool ok,) = to.call{value: amount}("");
        require(ok, "ETH transfer failed");
        emit NativeSwept(amount, to, msg.sender);
    }

    // ============ UUPS ============
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(POOL_ADMIN_ROLE) {}

    uint256[50] private __gap;
}