// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title FaucetToken
 * @dev Simple ERC20 token for faucet deployment
 */
contract FaucetToken is ERC20, Ownable {
    uint8 private _decimals;
    
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply,
        address owner
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(owner, initialSupply * 10**decimals_);
        _transferOwnership(owner);
    }
    
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}

/**
 * @title EdenVestFaucet
 * @dev Comprehensive faucet system for testnet tokens and native currency
 * @notice Supports both ERC20 tokens and native token distribution with rate limiting
 */
contract EdenVestFaucet is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    
    // ============ Events ============
    
    event TokenClaimed(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    
    event NativeClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    
    event TokenDeployed(
        address indexed token,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply
    );
    
    event TokenConfigured(
        address indexed token,
        uint256 amount,
        uint256 cooldown,
        uint256 dailyLimit,
        bool enabled
    );
    
    event NativeConfigured(
        uint256 amount,
        uint256 cooldown,
        uint256 dailyLimit,
        bool enabled
    );
    
    event FundsDeposited(
        address indexed token,
        uint256 amount,
        address indexed depositor
    );
    
    event FundsWithdrawn(
        address indexed token,
        uint256 amount,
        address indexed recipient
    );
    
    // ============ Structs ============
    
    struct TokenConfig {
        uint256 amount;          // Amount per claim
        uint256 cooldown;        // Cooldown period in seconds
        uint256 dailyLimit;      // Maximum claims per day per user
        bool enabled;            // Whether token is active
        bool exists;             // Whether config exists
    }
    
    struct UserClaim {
        uint256 lastClaimTime;   // Last claim timestamp
        uint256 dailyClaims;     // Claims made today
        uint256 lastResetDay;    // Last day counter was reset
    }
    
    // ============ State Variables ============
    
    // Native token configuration
    TokenConfig public nativeConfig;
    
    // Token configurations: token address => config
    mapping(address => TokenConfig) public tokenConfigs;
    
    // User claim tracking: user => token => claim data
    mapping(address => mapping(address => UserClaim)) public userClaims;
    
    // Native token claim tracking: user => claim data
    mapping(address => UserClaim) public nativeClaims;
    
    // Deployed faucet tokens
    address[] public deployedTokens;
    mapping(address => bool) public isDeployedToken;
    
    // Whitelisted addresses (bypass rate limits)
    mapping(address => bool) public whitelist;
    
    // Total claims tracking
    mapping(address => uint256) public totalClaims;
    uint256 public totalNativeClaims;
    
    // ============ Constants ============
    
    uint256 private constant SECONDS_PER_DAY = 86400;
    uint256 private constant MAX_DAILY_LIMIT = 100;
    uint256 private constant MAX_COOLDOWN = 24 hours;
    
    // ============ Constructor ============
    
    constructor() {
        // Default native token configuration
        nativeConfig = TokenConfig({
            amount: 0.0001 ether,           // 1 native token
            cooldown: 1 hours,         // 1 hour cooldown
            dailyLimit: 2,            // 10 claims per day
            enabled: true,
            exists: true
        });
    }
    
    // ============ Modifiers ============
    
    modifier validAddress(address addr) {
        require(addr != address(0), "Invalid address");
        _;
    }
    
    modifier tokenExists(address token) {
        require(tokenConfigs[token].exists, "Token not configured");
        _;
    }
    
    modifier tokenEnabled(address token) {
        require(tokenConfigs[token].enabled, "Token disabled");
        _;
    }
    
    // ============ Token Deployment ============
    
    /**
     * @dev Deploy a new faucet token
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals Token decimals
     * @param initialSupply Initial supply (before decimals)
     * @param amount Amount per claim (in wei)
     * @param cooldown Cooldown period in seconds
     * @param dailyLimit Daily claim limit per user
     */
    function deployToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 initialSupply,
        uint256 amount,
        uint256 cooldown,
        uint256 dailyLimit
    ) external onlyOwner returns (address) {
        require(bytes(name).length > 0, "Name required");
        require(bytes(symbol).length > 0, "Symbol required");
        require(decimals <= 18, "Max 18 decimals");
        require(initialSupply > 0, "Initial supply required");
        require(amount > 0, "Amount required");
        require(cooldown <= MAX_COOLDOWN, "Cooldown too high");
        require(dailyLimit > 0 && dailyLimit <= MAX_DAILY_LIMIT, "Invalid daily limit");
        
        // Deploy new token
        FaucetToken token = new FaucetToken(
            name,
            symbol,
            decimals,
            initialSupply,
            address(this)
        );
        
        address tokenAddress = address(token);
        
        // Configure token in faucet
        tokenConfigs[tokenAddress] = TokenConfig({
            amount: amount,
            cooldown: cooldown,
            dailyLimit: dailyLimit,
            enabled: true,
            exists: true
        });
        
        // Track deployed token
        deployedTokens.push(tokenAddress);
        isDeployedToken[tokenAddress] = true;
        
        emit TokenDeployed(tokenAddress, name, symbol, decimals, initialSupply);
        emit TokenConfigured(tokenAddress, amount, cooldown, dailyLimit, true);
        
        return tokenAddress;
    }
    
    // ============ Token Configuration ============
    
    /**
     * @dev Configure an existing ERC20 token for faucet
     */
    function configureToken(
        address token,
        uint256 amount,
        uint256 cooldown,
        uint256 dailyLimit,
        bool enabled
    ) external onlyOwner validAddress(token) {
        require(amount > 0, "Amount required");
        require(cooldown <= MAX_COOLDOWN, "Cooldown too high");
        require(dailyLimit > 0 && dailyLimit <= MAX_DAILY_LIMIT, "Invalid daily limit");
        
        tokenConfigs[token] = TokenConfig({
            amount: amount,
            cooldown: cooldown,
            dailyLimit: dailyLimit,
            enabled: enabled,
            exists: true
        });
        
        emit TokenConfigured(token, amount, cooldown, dailyLimit, enabled);
    }
    
    /**
     * @dev Configure native token parameters
     */
    function configureNative(
        uint256 amount,
        uint256 cooldown,
        uint256 dailyLimit,
        bool enabled
    ) external onlyOwner {
        require(amount > 0, "Amount required");
        require(cooldown <= MAX_COOLDOWN, "Cooldown too high");
        require(dailyLimit > 0 && dailyLimit <= MAX_DAILY_LIMIT, "Invalid daily limit");
        
        nativeConfig = TokenConfig({
            amount: amount,
            cooldown: cooldown,
            dailyLimit: dailyLimit,
            enabled: enabled,
            exists: true
        });
        
        emit NativeConfigured(amount, cooldown, dailyLimit, enabled);
    }
    
    /**
     * @dev Toggle token enabled status
     */
    function toggleToken(address token) external onlyOwner tokenExists(token) {
        tokenConfigs[token].enabled = !tokenConfigs[token].enabled;
        
        emit TokenConfigured(
            token,
            tokenConfigs[token].amount,
            tokenConfigs[token].cooldown,
            tokenConfigs[token].dailyLimit,
            tokenConfigs[token].enabled
        );
    }
    
    /**
     * @dev Toggle native token enabled status
     */
    function toggleNative() external onlyOwner {
        nativeConfig.enabled = !nativeConfig.enabled;
        
        emit NativeConfigured(
            nativeConfig.amount,
            nativeConfig.cooldown,
            nativeConfig.dailyLimit,
            nativeConfig.enabled
        );
    }
    
    // ============ Claiming Functions ============
    
    /**
     * @dev Claim ERC20 tokens from faucet
     */
    function claimTokens(address token) 
        external 
        nonReentrant 
        whenNotPaused 
        tokenExists(token) 
        tokenEnabled(token) 
    {
        TokenConfig memory config = tokenConfigs[token];
        UserClaim storage userClaim = userClaims[msg.sender][token];
        
        // Check rate limits
        _checkRateLimit(userClaim, config);
        
        // Update user claim data
        _updateUserClaim(userClaim, config);
        
        // Transfer tokens
        IERC20(token).transfer(msg.sender, config.amount);
        
        // Update stats
        totalClaims[token] = totalClaims[token].add(1);
        
        emit TokenClaimed(msg.sender, token, config.amount, block.timestamp);
    }
    
    /**
     * @dev Claim native tokens from faucet
     */
    function claimNative() external nonReentrant whenNotPaused {
        require(nativeConfig.enabled, "Native claims disabled");
        require(address(this).balance >= nativeConfig.amount, "Insufficient native balance");
        
        UserClaim storage userClaim = nativeClaims[msg.sender];
        
        // Check rate limits
        _checkRateLimit(userClaim, nativeConfig);
        
        // Update user claim data
        _updateUserClaim(userClaim, nativeConfig);
        
        // Transfer native tokens
        payable(msg.sender).transfer(nativeConfig.amount);
        
        // Update stats
        totalNativeClaims = totalNativeClaims.add(1);
        
        emit NativeClaimed(msg.sender, nativeConfig.amount, block.timestamp);
    }
    
    /**
     * @dev Batch claim multiple tokens
     */
    function claimMultiple(address[] calldata tokens) external {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenConfigs[tokens[i]].exists && tokenConfigs[tokens[i]].enabled) {
                this.claimTokens(tokens[i]);
            }
        }
    }
    
    // ============ Internal Functions ============
    
    function _checkRateLimit(UserClaim storage userClaim, TokenConfig memory config) internal view {
        if (whitelist[msg.sender]) return; // Bypass for whitelisted users
        
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        
        // Check cooldown
        require(
            block.timestamp >= userClaim.lastClaimTime.add(config.cooldown),
            "Cooldown not met"
        );
        
        // Check daily limit
        if (userClaim.lastResetDay == currentDay) {
            require(userClaim.dailyClaims < config.dailyLimit, "Daily limit exceeded");
        }
    }
    
    function _updateUserClaim(UserClaim storage userClaim, TokenConfig memory config) internal {
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        
        // Reset daily counter if new day
        if (userClaim.lastResetDay != currentDay) {
            userClaim.dailyClaims = 0;
            userClaim.lastResetDay = currentDay;
        }
        
        // Update claim data
        userClaim.lastClaimTime = block.timestamp;
        userClaim.dailyClaims = userClaim.dailyClaims.add(1);
    }
    
    // ============ Fund Management ============
    
    /**
     * @dev Deposit ERC20 tokens to faucet
     */
    function depositTokens(address token, uint256 amount) 
        external 
        validAddress(token) 
    {
        require(amount > 0, "Amount required");
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        emit FundsDeposited(token, amount, msg.sender);
    }
    
    /**
     * @dev Deposit native tokens to faucet
     */
    function depositNative() external payable {
        require(msg.value > 0, "Amount required");
        
        emit FundsDeposited(address(0), msg.value, msg.sender);
    }
    
    /**
     * @dev Withdraw ERC20 tokens from faucet (owner only)
     */
    function withdrawTokens(address token, uint256 amount, address recipient) 
        external 
        onlyOwner 
        validAddress(token) 
        validAddress(recipient) 
    {
        require(amount > 0, "Amount required");
        
        IERC20(token).transfer(recipient, amount);
        
        emit FundsWithdrawn(token, amount, recipient);
    }
    
    /**
     * @dev Withdraw native tokens from faucet (owner only)
     */
    function withdrawNative(uint256 amount, address payable recipient) 
        external 
        onlyOwner 
        validAddress(recipient) 
    {
        require(amount > 0, "Amount required");
        require(address(this).balance >= amount, "Insufficient balance");
        
        recipient.transfer(amount);
        
        emit FundsWithdrawn(address(0), amount, recipient);
    }
    
    // ============ Whitelist Management ============
    
    function addToWhitelist(address user) external onlyOwner validAddress(user) {
        whitelist[user] = true;
    }
    
    function removeFromWhitelist(address user) external onlyOwner validAddress(user) {
        whitelist[user] = false;
    }
    
    function addMultipleToWhitelist(address[] calldata users) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] != address(0)) {
                whitelist[users[i]] = true;
            }
        }
    }
    
    // ============ View Functions ============
    
    function getTokenConfig(address token) external view returns (TokenConfig memory) {
        return tokenConfigs[token];
    }
    
    function getUserClaim(address user, address token) external view returns (UserClaim memory) {
        return userClaims[user][token];
    }
    
    function getNativeClaim(address user) external view returns (UserClaim memory) {
        return nativeClaims[user];
    }
    
    function getDeployedTokens() external view returns (address[] memory) {
        return deployedTokens;
    }
    
    function getDeployedTokensCount() external view returns (uint256) {
        return deployedTokens.length;
    }
    
    function canClaim(address user, address token) external view returns (bool) {
        if (!tokenConfigs[token].exists || !tokenConfigs[token].enabled) {
            return false;
        }
        
        if (whitelist[user]) return true;
        
        TokenConfig memory config = tokenConfigs[token];
        UserClaim memory userClaim = userClaims[user][token];
        
        // Check cooldown
        if (block.timestamp < userClaim.lastClaimTime.add(config.cooldown)) {
            return false;
        }
        
        // Check daily limit
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        if (userClaim.lastResetDay == currentDay && userClaim.dailyClaims >= config.dailyLimit) {
            return false;
        }
        
        return true;
    }
    
    function canClaimNative(address user) external view returns (bool) {
        if (!nativeConfig.enabled) return false;
        if (address(this).balance < nativeConfig.amount) return false;
        if (whitelist[user]) return true;
        
        UserClaim memory userClaim = nativeClaims[user];
        
        // Check cooldown
        if (block.timestamp < userClaim.lastClaimTime.add(nativeConfig.cooldown)) {
            return false;
        }
        
        // Check daily limit
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        if (userClaim.lastResetDay == currentDay && userClaim.dailyClaims >= nativeConfig.dailyLimit) {
            return false;
        }
        
        return true;
    }
    
    function getTokenBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return IERC20(token).balanceOf(address(this));
    }
    
    function getNextClaimTime(address user, address token) external view returns (uint256) {
        if (whitelist[user]) return block.timestamp;
        
        UserClaim memory userClaim = userClaims[user][token];
        TokenConfig memory config = tokenConfigs[token];
        
        return userClaim.lastClaimTime.add(config.cooldown);
    }
    
    function getNextNativeClaimTime(address user) external view returns (uint256) {
        if (whitelist[user]) return block.timestamp;
        
        UserClaim memory userClaim = nativeClaims[user];
        return userClaim.lastClaimTime.add(nativeConfig.cooldown);
    }
    
    // ============ Emergency Functions ============
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============ Receive Function ============
    
    receive() external payable {
        emit FundsDeposited(address(0), msg.value, msg.sender);
    }
}