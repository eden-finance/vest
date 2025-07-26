# Smart Contract Audit: InvestmentPool Contract

## Audit Overview

This audit focuses on the InvestmentPool contract, which manages individual investment pools within the Eden Finance protocol. The contract handles user investments, withdrawals, LP token minting/burning, and pool-specific configurations. The audit examines potential security vulnerabilities, code quality concerns, and provides recommendations for improvements.

## Severity Levels

- **Critical (C)**: Vulnerabilities that can lead to loss of funds, unauthorized access, or complete system compromise
- **High (H)**: Issues that could potentially lead to system failure or significant financial impact
- **Medium (M)**: Issues that could impact system functionality but have limited financial impact
- **Low (L)**: Minor issues, code quality concerns, or best practice recommendations
- **Informational (I)**: Suggestions for code improvement, documentation, or optimization

## Findings Summary

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| IP-01 | Critical flaw in withdrawal logic - double spending vulnerability | Critical | Closed |
| IP-02 | LP token burn mechanism is fundamentally broken | Critical | Closed |
| IP-03 | Incorrect expected return calculation in withdrawal | High | Closed |
| IP-04 | Missing validation for LP token transfer in withdraw function | High | Closed |
| IP-05 | Potential division by zero in LP token calculation | High | Closed |
| IP-06 | Tax collection mechanism is flawed | Medium | Not Fixing |
| IP-07 | Missing input validation in initialization | Medium | Closed |
| IP-08 | Utilization calculation can cause division by zero | Medium | Closed |
| IP-09 | Missing access control for critical configuration updates | Low | Closed |
| IP-10 | Insufficient event data for investment tracking | Low | Closed |

## Detailed Findings

### [IP-01] Critical flaw in withdrawal logic - double spending vulnerability
**Severity**: Critical

**Description**:  
The withdrawal function has a critical flaw where it adds `investment.expectedReturn` to `withdrawAmount` but `withdrawAmount` starts at 0, meaning users only receive their expected returns and not their principal. However, the function also burns LP tokens that represent the principal, creating an accounting mismatch that could be exploited.

**Locations**:
- `InvestmentPool.sol:169-199` (`withdraw` function)
- `InvestmentPool.sol:178` (`withdrawAmount += investment.expectedReturn;`)

**Recommendation**:  
Fix the withdrawal logic to properly calculate and transfer both principal and returns:
```solidity
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
    require(lpAmount >= investment.lpTokens, "Insufficient LP tokens");

    investment.isWithdrawn = true;
    
    // Calculate total withdrawal: principal + expected return
    withdrawAmount = investment.amount + investment.expectedReturn;
    totalWithdrawn += withdrawAmount;

    // Transfer LP tokens from investor to pool before burning
    IERC20(lpToken).safeTransferFrom(investor, address(this), investment.lpTokens);
    
    // Burn LP tokens
    ILPToken(lpToken).burn(address(this), investment.lpTokens);

    // Burn NFT
    INFTPositionManager(nftManager).burnPosition(tokenId);

    // Check pool has sufficient balance
    require(IERC20(cNGN).balanceOf(address(this)) >= withdrawAmount, "Insufficient pool balance");

    // Transfer funds from pool to investor
    IERC20(cNGN).safeTransfer(investor, withdrawAmount);

    emit InvestmentWithdrawn(investmentId, investor, withdrawAmount);
}
```

### [IP-02] LP token burn mechanism is fundamentally broken
**Severity**: Critical

**Description**:  
The withdraw function attempts to burn LP tokens from `address(this)` (the pool contract), but the LP tokens are held by the investor, not the pool. The line `ILPToken(lpToken).burn(address(this), requiredLPTokens);` will fail because the pool doesn't have the LP tokens to burn.

**Locations**:
- `InvestmentPool.sol:183` (`ILPToken(lpToken).burn(address(this), requiredLPTokens);`)
- `InvestmentPool.sol:165-168` (EdenCore transfers LP tokens from user to pool before calling withdraw)

**Recommendation**:  
Fix the LP token burn mechanism to properly handle the transfer and burn:
```solidity
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
    require(lpAmount >= requiredLPTokens, "Insufficient LP tokens");

    investment.isWithdrawn = true;
    
    withdrawAmount = investment.amount + investment.expectedReturn;
    totalWithdrawn += withdrawAmount;

    // The LP tokens should already be transferred to this contract by EdenCore
    // Verify we have the LP tokens before burning
    require(IERC20(lpToken).balanceOf(address(this)) >= requiredLPTokens, "LP tokens not received");
    
    // Burn LP tokens from this contract
    ILPToken(lpToken).burn(address(this), requiredLPTokens);

    // Burn NFT
    INFTPositionManager(nftManager).burnPosition(tokenId);

    // Check pool has sufficient balance for withdrawal
    require(IERC20(cNGN).balanceOf(address(this)) >= withdrawAmount, "Insufficient pool balance");

    // Transfer funds to investor
    IERC20(cNGN).safeTransfer(investor, withdrawAmount);

    emit InvestmentWithdrawn(investmentId, investor, withdrawAmount);
}
```

### [IP-03] Incorrect expected return calculation in withdrawal
**Severity**: High

**Description**:  
The withdrawal function only pays out `investment.expectedReturn` but this doesn't include the principal amount. Users should receive their principal plus returns, but the current logic only pays returns, effectively causing users to lose their initial investment.

**Locations**:
- `InvestmentPool.sol:178` (`withdrawAmount += investment.expectedReturn;`)

**Recommendation**:  
Include both principal and returns in withdrawal calculation (already addressed in IP-01 fix).

### [IP-04] Missing validation for LP token transfer in withdraw function
**Severity**: High

**Description**:  
The withdraw function assumes that EdenCore has already transferred the LP tokens to the pool, but doesn't validate this assumption. This could lead to failed withdrawals or inconsistent state.

**Locations**:
- `InvestmentPool.sol:169-199` (`withdraw` function)

**Recommendation**:  
Add explicit validation that LP tokens have been received:
```solidity
function withdraw(address investor, uint256 tokenId, uint256 lpAmount)
    external
    override
    onlyEdenCore
    nonReentrant
    returns (uint256 withdrawAmount)
{
    // ... existing validation ...

    uint256 requiredLPTokens = investment.lpTokens;
    require(lpAmount >= requiredLPTokens, "Insufficient LP tokens");

    // Verify this contract has received the LP tokens
    uint256 poolLPBalance = IERC20(lpToken).balanceOf(address(this));
    require(poolLPBalance >= requiredLPTokens, "LP tokens not transferred to pool");

    // ... rest of function ...
}
```

### [IP-05] Potential division by zero in LP token calculation
**Severity**: High

**Description**:  
The `_calculateLPTokens` function divides by `totalDeposited` when `totalSupply > 0`, but `totalDeposited` could be zero if all previous investments were withdrawn, leading to division by zero.

**Locations**:
- `InvestmentPool.sol:286-294` (`_calculateLPTokens` function)
- `InvestmentPool.sol:293` (`return (amount * totalSupply) / totalDeposited;`)

**Recommendation**:  
Add protection against division by zero:
```solidity
function _calculateLPTokens(uint256 amount) internal view returns (uint256) {
    uint256 totalSupply = IERC20(lpToken).totalSupply();

    if (totalSupply == 0) {
        // First deposit
        return amount;
    } else {
        // Check for edge case where total supply exists but no deposits recorded
        if (totalDeposited == 0) {
            // This shouldn't happen in normal operation, but handle gracefully
            return amount; // Treat as first deposit
        }
        
        // Proportional to pool share
        return (amount * totalSupply) / totalDeposited;
    }
}
```

### [IP-06] Tax collection mechanism is flawed
**Severity**: Medium

**Description**:  
The contract mints LP tokens directly to the tax collector, but this creates an imbalance in the LP token economics. The tax collector receives LP tokens without contributing principal, which dilutes the value for actual investors.

**Locations**:
- `InvestmentPool.sol:127-129` (tax calculation and minting)
- `InvestmentPool.sol:145-146` (minting LP tokens to tax collector)

**Recommendation**:  
Implement a proper tax collection mechanism that doesn't distort LP token economics:
```solidity
function invest(address investor, uint256 amount, string memory title)
    external
    override
    onlyEdenCore
    nonReentrant
    whenNotPaused
    returns (uint256 tokenId, uint256 userLPTokens, uint256 taxAmount)
{
    // ... existing validation ...

    // Calculate LP tokens for the full amount first
    uint256 totalLPTokens = _calculateLPTokens(amount);
    
    // Calculate tax on the investment amount, not LP tokens
    uint256 poolTaxRate = poolConfig.taxRate;
    uint256 effectiveTaxRate = poolTaxRate > 0 ? poolTaxRate : IEdenCore(edenCore).globalTaxRate();
    
    // Tax should be on the cNGN amount, not LP tokens
    taxAmount = (amount * effectiveTaxRate) / BASIS_POINTS;
    uint256 netAmount = amount - taxAmount;
    
    // Recalculate LP tokens for net amount
    userLPTokens = _calculateLPTokens(netAmount);
    
    // Update total deposited with net amount
    totalDeposited += netAmount;
    
    // Mint LP tokens only to user
    ILPToken(lpToken).mint(investor, userLPTokens);
    
    // Transfer net amount to multisig
    IERC20(cNGN).safeTransferFrom(edenCore, poolMultisig, netAmount);
    
    // Transfer tax amount to tax collector (as cNGN, not LP tokens)
    IERC20(cNGN).safeTransferFrom(edenCore, taxCollector, taxAmount);
    
    // ... rest of function ...
}
```

### [IP-07] Missing input validation in initialization
**Severity**: Medium

**Description**:  
The initialize function lacks comprehensive validation of input parameters, which could lead to pools being created with invalid configurations.

**Locations**:
- `InvestmentPool.sol:62-93` (`initialize` function)

**Recommendation**:  
Add comprehensive input validation:
```solidity
function initialize(InitParams memory params) public initializer {
    __AccessControl_init();
    __ReentrancyGuard_init();
    __Pausable_init();

    // Validate addresses
    require(params.lpToken != address(0), "Invalid LP token");
    require(params.cNGN != address(0), "Invalid cNGN");
    require(params.poolMultisig != address(0), "Invalid multisig");
    require(params.nftManager != address(0), "Invalid NFT manager");
    require(params.edenCore != address(0), "Invalid Eden Core");
    require(params.taxCollector != address(0), "Invalid tax collector");
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
    taxCollector = params.taxCollector;

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

    // Grant multisig roles with validation
    for (uint256 i = 0; i < params.multisigSigners.length; i++) {
        require(params.multisigSigners[i] != address(0), "Invalid multisig signer");
        _grantRole(MULTISIG_ROLE, params.multisigSigners[i]);
    }
}
```

### [IP-08] Utilization calculation can cause division by zero
**Severity**: Medium

**Description**:  
The utilization calculation in `getPoolStats` divides by `poolConfig.utilizationCap` without checking if it's zero, which could cause the function to revert.

**Locations**:
- `InvestmentPool.sol:247-252` (`getPoolStats` function)
- `InvestmentPool.sol:251` (`utilization = totalDeposited > 0 ? (totalDeposited * BASIS_POINTS) / poolConfig.utilizationCap : 0;`)

**Recommendation**:  
Add protection against division by zero:
```solidity
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
        utilization = 0; // No cap means 0% utilization
    }
}
```

### [IP-09] Missing access control for critical configuration updates
**Severity**: Low

**Description**:  
Some configuration updates like `setAcceptingDeposits` don't emit events, making it difficult to track when deposits are paused or resumed.

**Locations**:
- `InvestmentPool.sol:228-230` (`setAcceptingDeposits` function)

**Recommendation**:  
Add events for configuration changes:
```solidity
event DepositsToggled(bool accepting, address indexed admin);

function setAcceptingDeposits(bool accepting) external onlyRole(POOL_ADMIN_ROLE) {
    bool oldState = poolConfig.acceptingDeposits;
    poolConfig.acceptingDeposits = accepting;
    
    if (oldState != accepting) {
        emit DepositsToggled(accepting, msg.sender);
    }
}
```

### [IP-10] Insufficient event data for investment tracking
**Severity**: Low

**Description**:  
The `InvestmentCreated` event doesn't include all relevant investment data like expected return and maturity time, making it difficult to track investment details off-chain.

**Locations**:
- `InvestmentPool.sol:154` (`emit InvestmentCreated(investmentId, investor, amount, totalLPTokens, tokenId);`)

**Recommendation**:  
Enhance event data for better tracking:
```solidity
event InvestmentCreated(
    uint256 indexed investmentId,
    address indexed investor,
    uint256 amount,
    uint256 lpTokens,
    uint256 indexed tokenId,
    uint256 expectedReturn,
    uint256 maturityTime,
    string title
);

// Update the emit statement
emit InvestmentCreated(
    investmentId, 
    investor, 
    amount, 
    userLPTokens, 
    tokenId, 
    expectedReturn, 
    maturityTime, 
    title
);
```

## Additional Recommendations

### [IP-11] Improve withdrawal amount validation
**Severity**: Informational

**Description**:  
Add validation to ensure the pool has sufficient funds before marking investment as withdrawn:

```solidity
function withdraw(address investor, uint256 tokenId, uint256 lpAmount)
    external
    override
    onlyEdenCore
    nonReentrant
    returns (uint256 withdrawAmount)
{
    // ... existing validation ...

    withdrawAmount = investment.amount + investment.expectedReturn;
    
    // Check pool balance BEFORE marking as withdrawn
    require(IERC20(cNGN).balanceOf(address(this)) >= withdrawAmount, "Insufficient pool balance");
    
    investment.isWithdrawn = true;
    totalWithdrawn += withdrawAmount;
    
    // ... rest of function ...
}
```

### [IP-12] Add pause functionality for emergencies
**Severity**: Informational

**Description**:  
Consider adding emergency pause functionality that stops withdrawals as well as investments:

```solidity
function emergencyPause() external onlyRole(POOL_ADMIN_ROLE) {
    _pause();
    poolConfig.acceptingDeposits = false;
    emit EmergencyAction("POOL_EMERGENCY_PAUSED", address(this), 0);
}
```

## Conclusion

The InvestmentPool contract has several critical vulnerabilities that must be addressed before deployment. The most severe issues are:

1. **Critical withdrawal logic flaw** - Users don't receive their principal back
2. **Broken LP token burn mechanism** - Will cause withdrawal failures
3. **Incorrect return calculations** - Mathematical errors in payouts
4. **Division by zero vulnerabilities** - Can cause contract failures

The contract also has design issues around tax collection that could distort LP token economics. These issues should be addressed with comprehensive testing, particularly around the investment and withdrawal flows.

**Priority**: Address critical and high-severity issues immediately, as they can lead to loss of user funds and contract failures.