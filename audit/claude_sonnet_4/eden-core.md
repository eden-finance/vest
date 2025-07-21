# Smart Contract Audit: EdenCore Contract

## Audit Overview

This audit focuses on the EdenCore contract, which serves as the main entry point for the Eden Finance investment protocol. The audit examines potential security vulnerabilities, code quality concerns, and provides recommendations for improvements.

## Severity Levels

- **Critical (C)**: Vulnerabilities that can lead to loss of funds, unauthorized access, or complete system compromise
- **High (H)**: Issues that could potentially lead to system failure or significant financial impact
- **Medium (M)**: Issues that could impact system functionality but have limited financial impact
- **Low (L)**: Minor issues, code quality concerns, or best practice recommendations
- **Informational (I)**: Suggestions for code improvement, documentation, or optimization

## Findings Summary

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| EC-01 | Insufficient validation in `investWithSwap` function | High | Closed |
| EC-02 | Tax collection vulnerability in LP token transfer | High | Closed |
| EC-03 | Missing slippage protection in swap operations | Medium | Closed |
| EC-04 | Potential reentrancy in investment functions | Medium | Closed |
| EC-05 | Centralized control over protocol parameters | Medium | Open |
| EC-06 | Missing input validation for pool creation | Medium | Closed |
| EC-07 | Emergency withdraw lacks event details | Low | Closed |
| EC-08 | Inconsistent error handling | Low | Open |
| EC-09 | Missing deadline validation in investments | Low | Open |
| EC-10 | Gas optimization opportunities | Informational | Closed |

## Detailed Findings

### [EC-01] Insufficient validation in `investWithSwap` function
**Severity**: High

**Description**:  
The `investWithSwap` function performs external calls to swap router and investment pool without proper validation of return values and state changes. The function assumes successful execution but doesn't validate intermediate states, which could lead to inconsistent contract state.

**Locations**:

- `EdenCore.sol:163-194` (`investWithSwap` function)
- Lines 179-181 (swap execution without proper validation)

**Recommendation**:  
Add comprehensive validation for swap operations and ensure atomic execution:

```solidity

function investWithSwap(InvestmentParams memory params)
    external
    whenNotPaused
    returns (uint256 tokenId, uint256 lpTokens)
{
    if (!isRegisteredPool[params.pool]) revert InvalidPool();
    if (!poolInfo[params.pool].isActive) revert PoolNotActive();
    if (params.deadline < block.timestamp) revert DeadlineExpired();
    
    // Validate token balances before operation
    uint256 initialBalance = IERC20(cNGN).balanceOf(address(this));
    
    // Transfer tokens from user
    IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
    
    // Validate swap will succeed before executing
    uint256 expectedOut = swapRouter.getAmountOut(params.tokenIn, cNGN, params.amountIn);
    if (expectedOut < params.minAmountOut) revert InsufficientLiquidity();
    
    IERC20(params.tokenIn).safeApprove(address(swapRouter), params.amountIn);
    
    uint256 amountOut = swapRouter.swapExactTokensForTokens(
        params.tokenIn, cNGN, params.amountIn, params.minAmountOut, params.deadline
    );
    
    // Verify the swap actually transferred the expected amount
    uint256 finalBalance = IERC20(cNGN).balanceOf(address(this));
    if (finalBalance != initialBalance + amountOut) revert SwapInconsistency();
    
    // Rest of the function...
}
```

### [EC-02] Tax collection vulnerability in LP token transfer

**Severity**: High

**Description**:  
The tax collection mechanism in both `invest` and `investWithSwap` functions has a critical flaw. The contract mints LP tokens to the user and then immediately reduces them by the tax amount, but this reduction is done by subtraction rather than actual token burning, leading to incorrect token balances.

**Locations**:

- `EdenCore.sol:140-156` (tax collection in `invest`)
- `EdenCore.sol:162-196` (tax collection in `investWithSwap`)

**Recommendation**:  
Fix the tax collection mechanism to properly handle LP token minting and tax distribution:

```solidity

function invest(address pool, uint256 amount, string memory title)
    external
    whenNotPaused
    returns (uint256 tokenId, uint256 lpTokens)
{
    if (!isRegisteredPool[pool]) revert InvalidPool();
    if (!poolInfo[pool].isActive) revert PoolNotActive();

    // Transfer cNGN to this contract and approve the pool
    IERC20(cNGN).safeTransferFrom(msg.sender, address(this), amount);
    IERC20(cNGN).safeApprove(pool, amount);

    (tokenId, lpTokens) = IInvestmentPool(pool).invest(msg.sender, amount, title);

    // Calculate tax on the LP tokens received
    uint256 taxAmount = _collectTax(pool, lpTokens);
    
    // The pool should mint LP tokens directly to user minus tax amount
    // rather than minting full amount and then subtracting
    
    emit InvestmentMade(pool, msg.sender, tokenId, amount, lpTokens - taxAmount);
}

function _collectTax(address pool, uint256 lpAmount) internal returns (uint256 taxAmount) {
    uint256 poolTaxRate = IInvestmentPool(pool).taxRate();
    uint256 effectiveTaxRate = poolTaxRate > 0 ? poolTaxRate : globalTaxRate;

    if (effectiveTaxRate > 0 && address(taxCollector) != address(0)) {
        taxAmount = (lpAmount * effectiveTaxRate) / BASIS_POINTS;
        address lpToken = poolInfo[pool].lpToken;

        // Transfer LP tokens from pool to tax collector instead of this contract
        IInvestmentPool(pool).transferTaxTokens(lpToken, taxAmount, address(taxCollector));
        
        taxCollector.collectTax(lpToken, taxAmount, pool);
    }
}
```

### [EC-03] Missing slippage protection in swap operations
**Severity**: Medium

**Description**:  
The `investWithSwap` function doesn't implement proper slippage protection mechanisms. While it checks expected output before swapping, it doesn't account for price movements between the check and execution, potentially leading to unfavorable swaps for users.

**Locations**:
- `EdenCore.sol:143-149` (swap execution)

**Recommendation**:  
Implement proper slippage protection with time-based validation:
```solidity
function investWithSwap(InvestmentParams memory params)
    external
    whenNotPaused
    returns (uint256 tokenId, uint256 lpTokens)
{
    // Add deadline validation
    if (params.deadline < block.timestamp) revert DeadlineExpired();
    
    // Check liquidity and perform swap with additional slippage buffer
    uint256 expectedOut = swapRouter.getAmountOut(params.tokenIn, cNGN, params.amountIn);
    uint256 maxSlippageBasisPoints = 100; // 1% maximum slippage
    uint256 adjustedMinOut = (expectedOut * (BASIS_POINTS - maxSlippageBasisPoints)) / BASIS_POINTS;
    
    if (adjustedMinOut < params.minAmountOut) revert InsufficientLiquidity();
    
    // Use the higher of user's minimum or calculated minimum
    uint256 effectiveMinOut = adjustedMinOut > params.minAmountOut ? adjustedMinOut : params.minAmountOut;
    
    uint256 amountOut = swapRouter.swapExactTokensForTokens(
        params.tokenIn, cNGN, params.amountIn, effectiveMinOut, params.deadline
    );
    
    // Rest of the function...
}
```

### [EC-04] Potential reentrancy in investment functions
**Severity**: Medium

**Description**:  
The investment functions make external calls to pools and other contracts without proper reentrancy protection. While OpenZeppelin's `ReentrancyGuardUpgradeable` is imported, the contract doesn't use the `nonReentrant` modifier on critical functions.

**Locations**:
- `EdenCore.sol:87-111` (`invest` function)
- `EdenCore.sol:127-161` (`investWithSwap` function)
- `EdenCore.sol:169-177` (`withdraw` function)

**Recommendation**:  
Add reentrancy protection to all external-facing functions that involve state changes:
```solidity
function invest(address pool, uint256 amount, string memory title)
    external
    whenNotPaused
    nonReentrant  // Add this modifier
    returns (uint256 tokenId, uint256 lpTokens)
{
    // Function implementation
}

function investWithSwap(InvestmentParams memory params)
    external
    whenNotPaused
    nonReentrant  // Add this modifier
    returns (uint256 tokenId, uint256 lpTokens)
{
    // Function implementation
}

function withdraw(address pool, uint256 tokenId, uint256 lpTokenAmount) 
    external 
    nonReentrant  // Add this modifier
    returns (uint256 withdrawAmount) 
{
    // Function implementation
}
```

### [EC-05] Centralized control over protocol parameters
**Severity**: Medium

**Description**:  
The contract gives significant control to admin roles, including the ability to pause the entire protocol, change critical parameters, and emergency withdraw funds. This centralization poses risks if admin keys are compromised.

**Locations**:
- `EdenCore.sol:280-285` (`pause` function)
- `EdenCore.sol:295-299` (`emergencyWithdraw` function)
- `EdenCore.sol:245-250` (`setGlobalTaxRate` function)

**Recommendation**:  
Implement a timelock mechanism and multi-signature requirements for critical operations:
```solidity
// Add timelock for critical parameter changes
mapping(bytes32 => uint256) public pendingChanges;
uint256 public constant TIMELOCK_DELAY = 48 hours;

function proposeGlobalTaxRateChange(uint256 _rate) external onlyRole(ADMIN_ROLE) {
    if (_rate > MAX_TAX_RATE) revert InvalidTaxRate();
    bytes32 proposalId = keccak256(abi.encode("TAX_RATE", _rate, block.timestamp));
    pendingChanges[proposalId] = block.timestamp + TIMELOCK_DELAY;
    
    emit ParameterChangeProposed("TAX_RATE", _rate, block.timestamp + TIMELOCK_DELAY);
}

function executeGlobalTaxRateChange(uint256 _rate) external onlyRole(ADMIN_ROLE) {
    bytes32 proposalId = keccak256(abi.encode("TAX_RATE", _rate, block.timestamp - TIMELOCK_DELAY));
    
    if (pendingChanges[proposalId] == 0) revert ProposalNotFound();
    if (block.timestamp < pendingChanges[proposalId]) revert TimelockNotExpired();
    
    delete pendingChanges[proposalId];
    
    uint256 oldRate = globalTaxRate;
    globalTaxRate = _rate;
    emit TaxRateUpdated(oldRate, _rate);
}
```

### [EC-06] Missing input validation for pool creation
**Severity**: Medium

**Description**:  
The `createPool` function lacks comprehensive input validation for the pool parameters, which could lead to creation of pools with invalid configurations.

**Locations**:
- `EdenCore.sol:66-81` (`createPool` function)

**Recommendation**:  
Add comprehensive validation for pool creation parameters:
```solidity
function createPool(IPoolFactory.PoolParams memory poolParams)
    external
    onlyRole(POOL_CREATOR_ROLE)
    returns (address pool)
{
    // Validate pool parameters
    if (bytes(poolParams.name).length == 0) revert InvalidPoolName();
    if (poolParams.admin == address(0)) revert InvalidAddress();
    if (poolParams.poolMultisig == address(0)) revert InvalidAddress();
    if (poolParams.minInvestment == 0) revert InvalidAmount();
    if (poolParams.maxInvestment < poolParams.minInvestment) revert InvalidAmount();
    if (poolParams.lockDuration < 1 days) revert InvalidLockDuration();
    if (poolParams.expectedRate > 10000) revert InvalidRate(); // Max 100% APY
    if (poolParams.taxRate > MAX_TAX_RATE) revert InvalidTaxRate();
    
    pool = poolFactory.createPool(poolParams);
    
    // Rest of function...
}
```

### [EC-07] Emergency withdraw lacks event details
**Severity**: Low

**Description**:  
The `emergencyWithdraw` function doesn't provide sufficient details in its event emission, making it difficult to track what was withdrawn and why.

**Locations**:
- `EdenCore.sol:295-299` (`emergencyWithdraw` function)

**Recommendation**:  
Enhance the emergency withdraw function with better event logging:
```solidity
function emergencyWithdraw(address token, uint256 amount, string memory reason) 
    external 
    onlyRole(EMERGENCY_ROLE) 
{
    uint256 balance = IERC20(token).balanceOf(address(this));
    if (amount > balance) revert InsufficientBalance();
    
    IERC20(token).safeTransfer(protocolTreasury, amount);
    
    emit EmergencyWithdraw(token, amount, protocolTreasury, reason, msg.sender);
}
```

### [EC-08] Inconsistent error handling
**Severity**: Low

**Description**:  
The contract uses both custom errors and require statements inconsistently, and some error conditions are not properly handled.

**Locations**:
- Various locations throughout the contract

**Recommendation**:  
Standardize error handling by using custom errors consistently:
```solidity
// Define comprehensive custom errors
error PoolNotFound(address pool);
error InvestmentAmountTooLow(uint256 provided, uint256 minimum);
error InvestmentAmountTooHigh(uint256 provided, uint256 maximum);
error SwapDeadlineExpired(uint256 current, uint256 deadline);
error InsufficientSwapOutput(uint256 expected, uint256 actual);

// Use custom errors consistently throughout the contract
function invest(address pool, uint256 amount, string memory title)
    external
    whenNotPaused
    nonReentrant
    returns (uint256 tokenId, uint256 lpTokens)
{
    if (!isRegisteredPool[pool]) revert PoolNotFound(pool);
    if (!poolInfo[pool].isActive) revert PoolNotActive();
    if (amount == 0) revert InvalidAmount();
    
    // Rest of function...
}
```

### [EC-09] Missing deadline validation in investments
**Severity**: Low

**Description**:  
The regular `invest` function doesn't have deadline protection, unlike `investWithSwap`, which could lead to transactions being executed at unintended times.

**Locations**:
- `EdenCore.sol:159-175` (`invest` function)

**Recommendation**:  
Add deadline parameter to the invest function:
```solidity
function invest(address pool, uint256 amount, string memory title, uint256 deadline)
    external
    whenNotPaused
    nonReentrant
    returns (uint256 tokenId, uint256 lpTokens)
{
    if (deadline < block.timestamp) revert DeadlineExpired();
    
    // Rest of function...
}
```

### [EC-10] Gas optimization opportunities
**Severity**: Informational

**Description**:  
Several gas optimization opportunities exist in the contract, including redundant storage reads and inefficient loops.

**Locations**:
- `EdenCore.sol:256-274` (`getActivePools` function)

**Recommendation**:  
Optimize gas usage through caching and efficient data structures:
```solidity
// Cache frequently accessed storage variables
function getActivePools() external view returns (address[] memory) {
    address[] memory allPoolsMemory = allPools; // Cache in memory
    uint256 activeCount = 0;
    
    // First pass: count active pools
    for (uint256 i = 0; i < allPoolsMemory.length; i++) {
        if (poolInfo[allPoolsMemory[i]].isActive) activeCount++;
    }

    address[] memory activePools = new address[](activeCount);
    uint256 index = 0;
    
    // Second pass: populate array
    for (uint256 i = 0; i < allPoolsMemory.length; i++) {
        if (poolInfo[allPoolsMemory[i]].isActive) {
            activePools[index++] = allPoolsMemory[i];
        }
    }

    return activePools;
}
```

## Conclusion

The EdenCore contract serves as a critical component of the Eden Finance protocol, managing investments and protocol configuration. However, several security concerns need to be addressed, particularly around tax collection mechanisms, swap validation, and reentrancy protection.

The most critical issues are the insufficient validation in swap operations, the tax collection vulnerability, and missing slippage protection. These issues should be addressed before deploying to production.

Additionally, implementing proper reentrancy protection, reducing centralization risks through timelock mechanisms, and improving input validation would significantly enhance the contract's security and robustness.