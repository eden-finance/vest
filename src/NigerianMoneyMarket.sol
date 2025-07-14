// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
 * @title Nigerian Money Market Investment Protocol
 * @dev A protocol for time-locked investments in Nigerian money markets using cNGN stablecoin
 * @notice Users deposit cNGN, receive non-transferable NFTs, and earn returns after lock period
 */
contract NigerianMoneyMarket is 
    Initializable,
    ERC721Upgradeable,
    ReentrancyGuard,
    AccessControl,
    Pausable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ ROLES ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MULTISIG_ROLE = keccak256("MULTISIG_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // ============ CONSTANTS ============
    uint256 public constant MIN_INVESTMENT = 1000e18; // 1000 cNGN minimum
    uint256 public constant MAX_INVESTMENT = 10_000_000e18; // 10M cNGN maximum
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant DEFAULT_LOCK_DURATION = 30 days;

    // ============ STRUCTS ============
    struct Investment {
        uint256 amount;           // Amount of cNGN deposited
        uint256 depositTime;      // When the investment was made
        uint256 lockDuration;     // Duration of the lock period
        uint256 maturityTime;     // When the investment matures
        uint256 expectedReturn;   // Expected return amount
        uint256 actualReturn;     // Actual return (set by multisig)
        bool isWithdrawn;         // Whether the investment has been withdrawn
        bool isMatured;           // Whether the investment has matured
        address investor;         // Address of the investor
    }

    struct MarketConfig {
        uint256 lockDuration;     // Current lock duration
        uint256 expectedRate;     // Expected annual return rate in basis points
        uint256 totalDeposited;   // Total amount currently deposited
        uint256 totalWithdrawn;   // Total amount withdrawn
        bool acceptingDeposits;   // Whether new deposits are accepted
    }

    // ============ STATE VARIABLES ============
    IERC20 public cNGN;
    uint256 public nextTokenId;
    MarketConfig public marketConfig;
    
    mapping(uint256 => Investment) public investments;
    mapping(address => uint256[]) public userInvestments;
    mapping(address => uint256) public userTotalInvested;
    
    // Multisig treasury management
    address[] public authorizedMultisigs;
    mapping(address => bool) public isAuthorizedMultisig;
    
    // ============ EVENTS ============
    event InvestmentCreated(
        uint256 indexed tokenId,
        address indexed investor,
        uint256 amount,
        uint256 maturityTime
    );
    
    event InvestmentWithdrawn(
        uint256 indexed tokenId,
        address indexed investor,
        uint256 principal,
        uint256 returns_
    );
    
    event InvestmentMatured(
        uint256 indexed tokenId,
        uint256 actualReturn
    );
    
    event FundsCollected(
        address indexed multisig,
        uint256 amount
    );
    
    event FundsReturned(
        address indexed multisig,
        uint256 amount
    );
    
    event MarketConfigUpdated(
        uint256 lockDuration,
        uint256 expectedRate,
        bool acceptingDeposits
    );
    
    event MultisigUpdated(
        address indexed multisig,
        bool authorized
    );

    // ============ ERRORS ============
    error InvalidAmount();
    error InvestmentNotMatured();
    error InvestmentAlreadyWithdrawn();
    error NotTokenOwner();
    error NotAuthorizedMultisig();
    error DepositsNotAccepted();
    error InvalidDuration();
    error InvalidRate();
    error InsufficientFunds();
    error TokenNotTransferable();

    // ============ INITIALIZATION ============
    function initialize(
        address _cNGN,
        address _admin,
        uint256 _expectedRate
    ) public initializer {
        __ERC721_init("Eden Finance Nigerian Money Market Position", "eCNGNP");
        __UUPSUpgradeable_init();
        
        cNGN = IERC20(_cNGN);
        nextTokenId = 1;
        
        marketConfig = MarketConfig({
            lockDuration: DEFAULT_LOCK_DURATION,
            expectedRate: _expectedRate,
            totalDeposited: 0,
            totalWithdrawn: 0,
            acceptingDeposits: true
        });
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    // ============ INVESTMENT FUNCTIONS ============
    
    /**
     * @dev Create a new investment position
     * @param amount Amount of cNGN to invest
     * @return tokenId The NFT token ID representing the investment
     */
    function invest(uint256 amount) external nonReentrant whenNotPaused returns (uint256) {
        if (!marketConfig.acceptingDeposits) revert DepositsNotAccepted();
        if (amount < MIN_INVESTMENT || amount > MAX_INVESTMENT) revert InvalidAmount();
        
        uint256 tokenId = nextTokenId++;
        uint256 maturityTime = block.timestamp + marketConfig.lockDuration;
        uint256 expectedReturn = _calculateExpectedReturn(amount);
        
        investments[tokenId] = Investment({
            amount: amount,
            depositTime: block.timestamp,
            lockDuration: marketConfig.lockDuration,
            maturityTime: maturityTime,
            expectedReturn: expectedReturn,
            actualReturn: 0,
            isWithdrawn: false,
            isMatured: false,
            investor: msg.sender
        });
        
        userInvestments[msg.sender].push(tokenId);
        userTotalInvested[msg.sender] += amount;
        marketConfig.totalDeposited += amount;
        
        _mint(msg.sender, tokenId);
        cNGN.safeTransferFrom(msg.sender, address(this), amount);
        
        emit InvestmentCreated(tokenId, msg.sender, amount, maturityTime);
        
        return tokenId;
    }
    
    /**
     * @dev Withdraw matured investment
     * @param tokenId The NFT token ID to withdraw
     */
    function withdraw(uint256 tokenId) external nonReentrant {
        Investment storage investment = investments[tokenId];
        
        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (investment.isWithdrawn) revert InvestmentAlreadyWithdrawn();
        if (block.timestamp < investment.maturityTime) revert InvestmentNotMatured();
        
        investment.isWithdrawn = true;
        
        uint256 totalAmount = investment.amount;
        if (investment.isMatured) {
            totalAmount += investment.actualReturn;
        } else {
            totalAmount += investment.expectedReturn;
        }
        
        marketConfig.totalWithdrawn += totalAmount;
        
        _burn(tokenId);
        cNGN.safeTransfer(msg.sender, totalAmount);
        
        emit InvestmentWithdrawn(tokenId, msg.sender, investment.amount, totalAmount - investment.amount);
    }

    // ============ MULTISIG FUNCTIONS ============
    
    /**
     * @dev Collect funds for investment (multisig only)
     * @param amount Amount to collect
     */
    function collectFunds(uint256 amount) external onlyRole(MULTISIG_ROLE) {
        if (amount > cNGN.balanceOf(address(this))) revert InsufficientFunds();
        
        cNGN.safeTransfer(msg.sender, amount);
        emit FundsCollected(msg.sender, amount);
    }
    
    /**
     * @dev Return funds with returns (multisig only)
     * @param amount Amount to return
     */
    function returnFunds(uint256 amount) external onlyRole(MULTISIG_ROLE) {
        cNGN.safeTransferFrom(msg.sender, address(this), amount);
        emit FundsReturned(msg.sender, amount);
    }
    
    /**
     * @dev Set actual returns for matured investments (multisig only)
     * @param tokenIds Array of token IDs to mature
     * @param actualReturns Array of actual return amounts
     */
    function setActualReturns(
        uint256[] calldata tokenIds,
        uint256[] calldata actualReturns
    ) external onlyRole(MULTISIG_ROLE) {
        require(tokenIds.length == actualReturns.length, "Array length mismatch");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            Investment storage investment = investments[tokenIds[i]];
            
            if (block.timestamp >= investment.maturityTime && !investment.isMatured) {
                investment.actualReturn = actualReturns[i];
                investment.isMatured = true;
                
                emit InvestmentMatured(tokenIds[i], actualReturns[i]);
            }
        }
    }

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Update market configuration
     * @param _lockDuration New lock duration
     * @param _expectedRate New expected rate
     * @param _acceptingDeposits Whether to accept new deposits
     */
    function updateMarketConfig(
        uint256 _lockDuration,
        uint256 _expectedRate,
        bool _acceptingDeposits
    ) external onlyRole(ADMIN_ROLE) {
        if (_lockDuration < 1 days || _lockDuration > 365 days) revert InvalidDuration();
        if (_expectedRate > 5000) revert InvalidRate(); // Max 50% APY
        
        marketConfig.lockDuration = _lockDuration;
        marketConfig.expectedRate = _expectedRate;
        marketConfig.acceptingDeposits = _acceptingDeposits;
        
        emit MarketConfigUpdated(_lockDuration, _expectedRate, _acceptingDeposits);
    }
    
    /**
     * @dev Add or remove authorized multisig
     * @param multisig Address of the multisig
     * @param authorized Whether to authorize or deauthorize
     */
    function updateMultisig(address multisig, bool authorized) external onlyRole(ADMIN_ROLE) {
        if (authorized) {
            if (!isAuthorizedMultisig[multisig]) {
                authorizedMultisigs.push(multisig);
                isAuthorizedMultisig[multisig] = true;
                _grantRole(MULTISIG_ROLE, multisig);
            }
        } else {
            if (isAuthorizedMultisig[multisig]) {
                isAuthorizedMultisig[multisig] = false;
                _revokeRole(MULTISIG_ROLE, multisig);
                
                // Remove from array
                for (uint256 i = 0; i < authorizedMultisigs.length; i++) {
                    if (authorizedMultisigs[i] == multisig) {
                        authorizedMultisigs[i] = authorizedMultisigs[authorizedMultisigs.length - 1];
                        authorizedMultisigs.pop();
                        break;
                    }
                }
            }
        }
        
        emit MultisigUpdated(multisig, authorized);
    }
    
    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Get investment details
     * @param tokenId The NFT token ID
     * @return investment The investment struct
     */
    function getInvestment(uint256 tokenId) external view returns (Investment memory) {
        return investments[tokenId];
    }
    
    /**
     * @dev Get user's investment token IDs
     * @param user Address of the user
     * @return tokenIds Array of token IDs owned by the user
     */
    function getUserInvestments(address user) external view returns (uint256[] memory) {
        return userInvestments[user];
    }
    
    /**
     * @dev Get total contract balance
     * @return balance Total cNGN balance
     */
    function getContractBalance() external view returns (uint256) {
        return cNGN.balanceOf(address(this));
    }
    
    /**
     * @dev Get authorized multisigs
     * @return multisigs Array of authorized multisig addresses
     */
    function getAuthorizedMultisigs() external view returns (address[] memory) {
        return authorizedMultisigs;
    }
    
    /**
     * @dev Check if investment is withdrawable
     * @param tokenId The NFT token ID
     * @return withdrawable Whether the investment can be withdrawn
     */
    function isWithdrawable(uint256 tokenId) external view returns (bool) {
        Investment memory investment = investments[tokenId];
        return !investment.isWithdrawn && block.timestamp >= investment.maturityTime;
    }

    // ============ CONTEXT OVERRIDES ============
    
    /**
     * @dev Override _msgSender to resolve conflict
     */
    function _msgSender() internal view override(Context, ContextUpgradeable) returns (address) {
        return super._msgSender();
    }
    
    /**
     * @dev Override _msgData to resolve conflict
     */
    function _msgData() internal view override(Context, ContextUpgradeable) returns (bytes calldata) {
        return super._msgData();
    }
    
    /**
     * @dev Override _contextSuffixLength to resolve conflict
     */
    function _contextSuffixLength() internal view override(Context, ContextUpgradeable) returns (uint256) {
        return super._contextSuffixLength();
    }

    // ============ INTERNAL FUNCTIONS ============
    
    /**
     * @dev Calculate expected return for an investment
     * @param amount Investment amount
     * @return expectedReturn Expected return amount
     */
    function _calculateExpectedReturn(uint256 amount) internal view returns (uint256) {
        // Simple interest calculation: (amount * rate * time) / (BASIS_POINTS * 365 days)
        uint256 timeInSeconds = marketConfig.lockDuration;
        return (amount * marketConfig.expectedRate * timeInSeconds) / (BASIS_POINTS * 365 days);
    }
    
     /**
     * @dev Override transfer functions to make tokens non-transferable
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        
        // Allow minting and burning but not transfers
        if (from != address(0) && to != address(0)) {
            revert TokenNotTransferable();
        }
        
        return super._update(to, tokenId, auth);
    }
    
    /**
     * @dev Required by UUPSUpgradeable
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
    
    /**
     * @dev Required by AccessControl
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}