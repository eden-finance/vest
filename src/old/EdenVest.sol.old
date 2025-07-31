// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IPoolFactory.sol";
import "./interfaces/IInvestmentPool.sol";
import "./interfaces/ITaxCollector.sol";
import "./interfaces/ISwapRouter.sol";
import "./interfaces/INFTPositionManager.sol";

/**
 * @title EdenCore
 * @notice Main entry point for Eden Finance investment protocol
 * @dev Manages pools, investments, and protocol configuration with multisig controls
 */
contract EdenCore is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // ============ ROLES ============
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant POOL_CREATOR_ROLE = keccak256("POOL_CREATOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant MULTISIG_SIGNER_ROLE = keccak256("MULTISIG_SIGNER_ROLE");

    // ============ MULTISIG CONSTANTS ============
    uint256 public constant REQUIRED_SIGNATURES = 3; // Require 3 out of N signatures
    uint256 public constant PROPOSAL_EXPIRY = 3 days;

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

    // ============ MULTISIG STATE ============
    uint256 public nextProposalId = 1;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasSignedProposal;
    address[] public multisigSigners;
    mapping(address => bool) public isMultisigSigner;

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

    struct Proposal {
        uint256 id;
        ProposalType proposalType;
        address proposer;
        uint256 createdAt;
        uint256 expiresAt;
        bool executed;
        uint256 signatureCount;
        bytes data;
        string description;
    }

    enum ProposalType {
        PAUSE_PROTOCOL,
        UNPAUSE_PROTOCOL,
        SET_GLOBAL_TAX_RATE,
        SET_PROTOCOL_TREASURY,
        EMERGENCY_WITHDRAW,
        UPGRADE_CONTRACT,
        ADD_MULTISIG_SIGNER,
        REMOVE_MULTISIG_SIGNER
    }

    // ============ EVENTS ============
    event PoolCreated(address indexed pool, string name, address indexed admin, address lpToken);
    event InvestmentMade(
        address indexed pool, address indexed investor, uint256 tokenId, uint256 amount, uint256 lpTokens
    );
    event TaxRateUpdated(uint256 oldRate, uint256 newRate);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event EmergencyWithdraw(address token, uint256 amount, address treasury, string reason, address admin);

    // Multisig Events
    event ProposalCreated(
        uint256 indexed proposalId, ProposalType proposalType, address indexed proposer, string description
    );
    event ProposalSigned(uint256 indexed proposalId, address indexed signer, uint256 signatureCount);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event ProposalExpired(uint256 indexed proposalId);
    event MultisigSignerAdded(address indexed signer);
    event MultisigSignerRemoved(address indexed signer);

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

    // Multisig Errors
    error ProposalNotFound();
    error ProposalAlreadyExecuted();
    error AlreadySigned();
    error NotMultisigSigner();
    error InsufficientSignatures();
    error InvalidProposalType();
    error InvalidSignerCount();
    error EProposalExpired();

    // ============ MODIFIERS ============
    modifier onlyMultisigSigner() {
        if (!isMultisigSigner[msg.sender]) revert NotMultisigSigner();
        _;
    }

    modifier validProposal(uint256 proposalId) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        if (block.timestamp > proposal.expiresAt) revert EProposalExpired();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        _;
    }

    function initialize(
        address _cNGN,
        address _treasury,
        address _admin,
        uint256 _taxRate,
        address[] memory _multisigSigners
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        if (_cNGN == address(0) || _treasury == address(0)) revert InvalidAddress();
        if (_taxRate > MAX_TAX_RATE) revert InvalidTaxRate();
        if (_multisigSigners.length < REQUIRED_SIGNATURES) revert InvalidSignerCount();

        cNGN = _cNGN;
        protocolTreasury = _treasury;
        globalTaxRate = _taxRate;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(POOL_CREATOR_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);

        for (uint256 i = 0; i < _multisigSigners.length; i++) {
            if (_multisigSigners[i] == address(0)) revert InvalidAddress();
            multisigSigners.push(_multisigSigners[i]);
            isMultisigSigner[_multisigSigners[i]] = true;
            _grantRole(MULTISIG_SIGNER_ROLE, _multisigSigners[i]);
        }
    }

    /**
     * @notice Create a new proposal for critical operations
     * @param proposalType Type of proposal
     * @param data Encoded function call data
     * @param description Human readable description
     */
    function createProposal(ProposalType proposalType, bytes memory data, string memory description)
        internal
        onlyMultisigSigner
        returns (uint256 proposalId)
    {
        proposalId = nextProposalId++;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposalType: proposalType,
            proposer: msg.sender,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + PROPOSAL_EXPIRY,
            executed: false,
            signatureCount: 1,
            data: data,
            description: description
        });

        hasSignedProposal[proposalId][msg.sender] = true;

        emit ProposalCreated(proposalId, proposalType, msg.sender, description);
        emit ProposalSigned(proposalId, msg.sender, 1);
    }

    /**
     * @notice Sign a proposal
     * @param proposalId ID of the proposal to sign
     */
    function signProposal(uint256 proposalId) external onlyMultisigSigner validProposal(proposalId) {
        if (hasSignedProposal[proposalId][msg.sender]) revert AlreadySigned();

        hasSignedProposal[proposalId][msg.sender] = true;
        proposals[proposalId].signatureCount++;

        emit ProposalSigned(proposalId, msg.sender, proposals[proposalId].signatureCount);

        // Auto-execute if we have enough signatures
        if (proposals[proposalId].signatureCount >= REQUIRED_SIGNATURES) {
            _executeProposal(proposalId);
        }
    }

    /**
     * @notice Execute a proposal with sufficient signatures
     * @param proposalId ID of the proposal to execute
     */
    function executeProposal(uint256 proposalId) external onlyMultisigSigner validProposal(proposalId) {
        if (proposals[proposalId].signatureCount < REQUIRED_SIGNATURES) revert InsufficientSignatures();
        _executeProposal(proposalId);
    }

    /**
     * @dev Internal function to execute proposals
     */
    function _executeProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        if (proposal.proposalType == ProposalType.PAUSE_PROTOCOL) {
            _pause();
        } else if (proposal.proposalType == ProposalType.UNPAUSE_PROTOCOL) {
            _unpause();
        } else if (proposal.proposalType == ProposalType.SET_GLOBAL_TAX_RATE) {
            uint256 newRate = abi.decode(proposal.data, (uint256));
            _setGlobalTaxRateInternal(newRate);
        } else if (proposal.proposalType == ProposalType.SET_PROTOCOL_TREASURY) {
            address newTreasury = abi.decode(proposal.data, (address));
            _setProtocolTreasuryInternal(newTreasury);
        } else if (proposal.proposalType == ProposalType.EMERGENCY_WITHDRAW) {
            (address token, uint256 amount, string memory reason) =
                abi.decode(proposal.data, (address, uint256, string));
            _emergencyWithdrawInternal(token, amount, reason);
        } else if (proposal.proposalType == ProposalType.ADD_MULTISIG_SIGNER) {
            address newSigner = abi.decode(proposal.data, (address));
            _addMultisigSigner(newSigner);
        } else if (proposal.proposalType == ProposalType.REMOVE_MULTISIG_SIGNER) {
            address signerToRemove = abi.decode(proposal.data, (address));
            _removeMultisigSigner(signerToRemove);
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    /**
     * @notice Create proposal to pause protocol
     */
    function proposePauseProtocol(string memory reason) external onlyMultisigSigner returns (uint256) {
        return createProposal(ProposalType.PAUSE_PROTOCOL, "", string.concat("Pause Protocol: ", reason));
    }

    /**
     * @notice Create proposal to unpause protocol
     */
    function proposeUnpauseProtocol(string memory reason) external onlyMultisigSigner returns (uint256) {
        return createProposal(ProposalType.UNPAUSE_PROTOCOL, "", string.concat("Unpause Protocol: ", reason));
    }

    /**
     * @notice Create proposal to update global tax rate
     */
    function proposeSetGlobalTaxRate(uint256 newRate, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        if (newRate > MAX_TAX_RATE) revert InvalidTaxRate();

        return createProposal(
            ProposalType.SET_GLOBAL_TAX_RATE,
            abi.encode(newRate),
            string.concat("Set Global Tax Rate to ", _uint2str(newRate), " basis points: ", reason)
        );
    }

    /**
     * @notice Create proposal to update protocol treasury
     */
    function proposeSetProtocolTreasury(address newTreasury, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        if (newTreasury == address(0)) revert InvalidAddress();

        return createProposal(
            ProposalType.SET_PROTOCOL_TREASURY,
            abi.encode(newTreasury),
            string.concat("Set Protocol Treasury: ", reason)
        );
    }

    /**
     * @notice Create proposal for emergency withdrawal
     */
    function proposeEmergencyWithdraw(address token, uint256 amount, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        return createProposal(
            ProposalType.EMERGENCY_WITHDRAW,
            abi.encode(token, amount, reason),
            string.concat("Emergency Withdraw: ", reason)
        );
    }

    /**
     * @notice Create proposal to add multisig signer
     */
    function proposeAddMultisigSigner(address newSigner, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        if (newSigner == address(0)) revert InvalidAddress();
        if (isMultisigSigner[newSigner]) revert InvalidAddress(); // Already a signer

        return createProposal(
            ProposalType.ADD_MULTISIG_SIGNER, abi.encode(newSigner), string.concat("Add Multisig Signer: ", reason)
        );
    }

    /**
     * @notice Create proposal to remove multisig signer
     */
    function proposeRemoveMultisigSigner(address signerToRemove, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        if (!isMultisigSigner[signerToRemove]) revert InvalidAddress();
        if (multisigSigners.length <= REQUIRED_SIGNATURES) revert InvalidSignerCount(); // Can't go below minimum

        return createProposal(
            ProposalType.REMOVE_MULTISIG_SIGNER,
            abi.encode(signerToRemove),
            string.concat("Remove Multisig Signer: ", reason)
        );
    }

    // ============ INTERNAL MULTISIG EXECUTION FUNCTIONS ============

    function _setGlobalTaxRateInternal(uint256 _rate) internal {
        uint256 oldRate = globalTaxRate;
        globalTaxRate = _rate;
        emit TaxRateUpdated(oldRate, _rate);
    }

    function _setProtocolTreasuryInternal(address _treasury) internal {
        address oldTreasury = protocolTreasury;
        protocolTreasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    function _emergencyWithdrawInternal(address token, uint256 amount, string memory reason) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance();

        IERC20(token).transfer(protocolTreasury, amount);
        emit EmergencyWithdraw(token, amount, protocolTreasury, reason, msg.sender);
    }

    function _addMultisigSigner(address newSigner) internal {
        multisigSigners.push(newSigner);
        isMultisigSigner[newSigner] = true;
        _grantRole(MULTISIG_SIGNER_ROLE, newSigner);
        emit MultisigSignerAdded(newSigner);
    }

    function _removeMultisigSigner(address signerToRemove) internal {
        isMultisigSigner[signerToRemove] = false;
        _revokeRole(MULTISIG_SIGNER_ROLE, signerToRemove);

        // Remove from array
        for (uint256 i = 0; i < multisigSigners.length; i++) {
            if (multisigSigners[i] == signerToRemove) {
                multisigSigners[i] = multisigSigners[multisigSigners.length - 1];
                multisigSigners.pop();
                break;
            }
        }
        emit MultisigSignerRemoved(signerToRemove);
    }

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

        emit PoolCreated(pool, poolParams.name, poolParams.admin, poolInfo[pool].lpToken);
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

    // ============ MULTISIG VIEW FUNCTIONS ============

    /**
     * @notice Get proposal details
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /**
     * @notice Get all multisig signers
     */
    function getMultisigSigners() external view returns (address[] memory) {
        return multisigSigners;
    }

    /**
     * @notice Check if address has signed a proposal
     */
    function hasSignedProposalView(uint256 proposalId, address signer) external view returns (bool) {
        return hasSignedProposal[proposalId][signer];
    }

    /**
     * @notice Get signature count for a proposal
     */
    function getProposalSignatureCount(uint256 proposalId) external view returns (uint256) {
        return proposals[proposalId].signatureCount;
    }

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

    function _uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) return "0";

        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }

        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }

        str = string(bstr);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}
}
