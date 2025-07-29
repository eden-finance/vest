# Smart Contract Audit: SwapRouter Contract

## Audit Overview

This audit focuses on the SwapRouter contract which handles token swaps via Uniswap V3 integration for the Eden Finance protocol. The contract serves as an intermediary between the protocol and Uniswap V3, providing quote functionality and swap execution with enhanced error handling.

## Severity Levels

- **Critical (C)**: Vulnerabilities that can lead to loss of funds, unauthorized access, or complete system compromise
- **High (H)**: Issues that could potentially lead to system failure or significant financial impact
- **Medium (M)**: Issues that could impact system functionality but have limited financial impact
- **Low (L)**: Minor issues, code quality concerns, or best practice recommendations
- **Informational (I)**: Suggestions for code improvement, documentation, or optimization

## Findings Summary

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| SR-01 | Missing reentrancy protection on swap functions | High | Closed |
| SR-02 | Lack of slippage protection validation | High | Closed |
| SR-03 | Potential for stuck tokens due to failed approvals | Medium | Closed |
| SR-04 | Missing access control for critical functions | Medium | Closed |
| SR-05 | Insufficient validation of Uniswap router responses | Medium | Closed |
| SR-06 | Gas limit vulnerability in quoter calls | Medium | Closed |
| SR-07 | Missing emergency withdrawal mechanism | Low | Closed |
| SR-08 | Inefficient approval pattern | Low | Closed |
| SR-09 | Missing maximum slippage protection | Low | Closed |
| SR-10 | Lack of pause functionality during emergencies | Medium | Closed |

## Detailed Findings

### [SR-01] Missing reentrancy protection on swap functions
**Severity**: High

**Description**:  
The `swapExactTokensForTokens` function makes external calls to Uniswap contracts without reentrancy protection. Malicious tokens could potentially exploit this through reentrancy attacks during transfer callbacks.

**Locations**:
- `SwapRouter.sol:78-119` (`swapExactTokensForTokens` function)

**Recommendation**:  
Add reentrancy protection to all functions that make external calls:
```solidity
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SwapRouter is IEdenSwapRouter.ISwapRouter, Ownable, ReentrancyGuard {
    
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external override nonReentrant returns (uint256 amountOut) {
        // Function implementation
    }
}
```

### [SR-02] Lack of slippage protection validation
**Severity**: High

**Description**:  
The contract doesn't validate that `amountOutMinimum` is reasonable compared to the quoted amount. Users could accidentally set very low slippage protection, leading to significant losses during volatile market conditions.

**Locations**:
- `SwapRouter.sol:78-119` (`swapExactTokensForTokens` function)

**Recommendation**:  
Add slippage validation against quoted amounts:
```solidity
uint256 public maxSlippageBasisPoints = 1000; // 10% max slippage
uint256 public constant BASIS_POINTS = 10000;

function swapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    uint256 deadline
) external override nonReentrant returns (uint256 amountOut) {
    if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidAddress(tokenIn);
    if (amountIn == 0) return 0;
    if (deadline < block.timestamp) revert("Deadline expired");

    // Get quote and validate slippage protection
    uint256 quotedAmount = _getQuoteInternal(tokenIn, tokenOut, amountIn);
    if (quotedAmount == 0) revert("No liquidity available");
    
    uint256 minAcceptableAmount = (quotedAmount * (BASIS_POINTS - maxSlippageBasisPoints)) / BASIS_POINTS;
    if (amountOutMinimum < minAcceptableAmount) {
        revert("Slippage protection too low");
    }

    // Rest of function...
}

function setMaxSlippage(uint256 _maxSlippageBasisPoints) external onlyOwner {
    require(_maxSlippageBasisPoints <= 2000, "Max slippage too high"); // Max 20%
    maxSlippageBasisPoints = _maxSlippageBasisPoints;
}
```

### [SR-03] Potential for stuck tokens due to failed approvals
**Severity**: Medium

**Description**:  
If the approval to Uniswap router fails or the swap fails after approval, tokens could remain in the contract. The contract doesn't have mechanisms to recover these stuck tokens.

**Locations**:
- `SwapRouter.sol:85-86` (token approval and potential failure points)

**Recommendation**:  
Add emergency token recovery and better approval handling:
```solidity
event TokensRecovered(address indexed token, uint256 amount, address indexed to);

function swapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    uint256 deadline
) external override nonReentrant returns (uint256 amountOut) {
    // ... validation ...

    uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));
    
    // Transfer tokens from user
    IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    
    // Verify transfer succeeded
    uint256 balanceAfter = IERC20(tokenIn).balanceOf(address(this));
    require(balanceAfter >= balanceBefore + amountIn, "Transfer failed");
    
    // Approve router to spend tokens
    IERC20(tokenIn).forceApprove(address(uniswapRouter), amountIn);
    
    // Verify approval succeeded
    require(IERC20(tokenIn).allowance(address(this), address(uniswapRouter)) >= amountIn, "Approval failed");

    try uniswapRouter.exactInputSingle(params) returns (uint256 _amountOut) {
        amountOut = _amountOut;
        
        // Clear any remaining approval for security
        IERC20(tokenIn).forceApprove(address(uniswapRouter), 0);
        
        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
    } catch Error(string memory reason) {
        // Clear approval and refund tokens on failure
        IERC20(tokenIn).forceApprove(address(uniswapRouter), 0);
        IERC20(tokenIn).safeTransfer(msg.sender, amountIn);
        revert SwapFailed(reason);
    } catch {
        // Clear approval and refund tokens on failure
        IERC20(tokenIn).forceApprove(address(uniswapRouter), 0);
        IERC20(tokenIn).safeTransfer(msg.sender, amountIn);
        revert SwapFailed("Unknown error");
    }
}

function emergencyTokenRecovery(address token, uint256 amount, address to) external onlyOwner {
    require(to != address(0), "Invalid recipient");
    IERC20(token).safeTransfer(to, amount);
    emit TokensRecovered(token, amount, to);
}
```

### [SR-04] Missing access control for critical functions
**Severity**: Medium

**Description**:  
The quote functions `getAmountOut` and `getAmountOutWithDetails` are public and could be subject to DOS attacks or manipulation. They should have rate limiting or access control.

**Locations**:
- `SwapRouter.sol:121-149` (`getAmountOut` function)
- `SwapRouter.sol:161-191` (`getAmountOutWithDetails` function)

**Recommendation**:  
Add rate limiting and access control for quote functions:
```solidity
mapping(address => uint256) public lastQuoteTime;
uint256 public quoteRateLimit = 1; // 1 second between quotes per address

modifier rateLimit() {
    require(block.timestamp >= lastQuoteTime[msg.sender] + quoteRateLimit, "Rate limit exceeded");
    lastQuoteTime[msg.sender] = block.timestamp;
    _;
}

function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
    external
    override
    rateLimit
    returns (uint256 amountOut)
{
    // Function implementation
}

function setQuoteRateLimit(uint256 _rateLimit) external onlyOwner {
    require(_rateLimit <= 60, "Rate limit too high"); // Max 1 minute
    quoteRateLimit = _rateLimit;
}
```

### [SR-05] Insufficient validation of Uniswap router responses
**Severity**: Medium

**Description**:  
The contract doesn't validate that the Uniswap router actually transferred the expected amount of tokens. This could lead to accounting errors or loss of funds.

**Locations**:
- `SwapRouter.sol:105-115` (swap execution without output validation)

**Recommendation**:  
Add balance validation to ensure swap actually occurred:
```solidity
function swapExactTokensForTokens(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMinimum,
    uint256 deadline
) external override nonReentrant returns (uint256 amountOut) {
    // ... existing validation and setup ...

    // Record balance before swap
    uint256 recipientBalanceBefore = IERC20(tokenOut).balanceOf(msg.sender);
    
    try uniswapRouter.exactInputSingle(params) returns (uint256 _amountOut) {
        // Verify the actual balance change matches reported amount
        uint256 recipientBalanceAfter = IERC20(tokenOut).balanceOf(msg.sender);
        uint256 actualAmountOut = recipientBalanceAfter - recipientBalanceBefore;
        
        if (actualAmountOut != _amountOut) {
            revert("Amount mismatch");
        }
        
        if (actualAmountOut < amountOutMinimum) {
            revert InsufficientAmountOut(amountOutMinimum, actualAmountOut);
        }
        
        amountOut = actualAmountOut;
        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
    } catch {
        // Handle failures...
    }
}
```

### [SR-06] Gas limit vulnerability in quoter calls
**Severity**: Medium

**Description**:  
The quoter calls don't have gas limits, which could lead to out-of-gas errors or allow malicious tokens to consume excessive gas during quote operations.

**Locations**:
- `SwapRouter.sol:131-143` (quoter calls without gas limits)

**Recommendation**:  
Add gas limits to quoter calls:
```solidity
uint256 public constant QUOTE_GAS_LIMIT = 300000; // 300k gas limit for quotes

function _getQuoteInternal(address tokenIn, address tokenOut, uint256 amountIn) 
    internal 
    returns (uint256 amountOut) 
{
    if (amountIn == 0) return 0;
    if (tokenIn == address(0) || tokenOut == address(0)) return 0;

    uint24 fee = _getPoolFee(tokenIn, tokenOut);

    IUniswapV3QuoterV2.QuoteExactInputSingleParams memory params = 
        IUniswapV3QuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            fee: fee,
            sqrtPriceLimitX96: 0
        });

    try quoter.quoteExactInputSingle{gas: QUOTE_GAS_LIMIT}(params) returns (
        uint256 _amountOut,
        uint160,
        uint32,
        uint256
    ) {
        amountOut = _amountOut;
    } catch {
        amountOut = 0;
    }
}
```

### [SR-07] Missing emergency withdrawal mechanism
**Severity**: Low

**Description**:  
While there's an `emergencyTokenRecovery` function in the recommendation, the current contract lacks this functionality, which could be needed if tokens get stuck.

**Locations**:
- Throughout the contract (missing emergency mechanisms)

**Recommendation**:  
Already addressed in SR-03 recommendation above.

### [SR-08] Inefficient approval pattern
**Severity**: Low

**Description**:  
The contract uses `forceApprove` which might not be the most gas-efficient pattern for all tokens. Some tokens charge fees for approvals.

**Locations**:
- `SwapRouter.sol:88` (approval pattern)

**Recommendation**:  
Optimize approval pattern:
```solidity
function _approveTokenIfNeeded(address token, address spender, uint256 amount) internal {
    uint256 currentAllowance = IERC20(token).allowance(address(this), spender);
    if (currentAllowance < amount) {
        if (currentAllowance > 0) {
            IERC20(token).forceApprove(spender, 0);
        }
        IERC20(token).forceApprove(spender, amount);
    }
}
```

### [SR-09] Missing maximum slippage protection
**Severity**: Low

**Description**:  
The contract doesn't enforce a maximum slippage limit, which could protect users from extremely unfavorable trades during high volatility.

**Locations**:
- `SwapRouter.sol:78-119` (`swapExactTokensForTokens` function)

**Recommendation**:  
Already addressed in SR-02 recommendation above.

### [SR-10] Lack of pause functionality during emergencies
**Severity**: Medium

**Description**:  
The contract lacks pause functionality that could be critical during security incidents or market emergencies.

**Locations**:
- Throughout the contract (missing pause functionality)

**Recommendation**:  
Add pause functionality:
```solidity
import "@openzeppelin/contracts/utils/Pausable.sol";

contract SwapRouter is IEdenSwapRouter.ISwapRouter, Ownable, ReentrancyGuard, Pausable {
    
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external override nonReentrant whenNotPaused returns (uint256 amountOut) {
        // Function implementation
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
}
```

## Additional Security Recommendations

### [SR-11] Add comprehensive event logging
**Severity**: Informational

```solidity
event QuoteRequested(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
event SlippageProtectionTriggered(uint256 expected, uint256 minimum, uint256 actual);
event EmergencyPaused(address indexed admin);
```

### [SR-12] Implement circuit breaker for failed swaps
**Severity**: Informational

```solidity
mapping(address => mapping(address => uint256)) public failedSwapCount;
uint256 public constant MAX_FAILED_SWAPS = 5;
uint256 public constant FAILURE_RESET_TIME = 1 hours;

function _recordSwapFailure(address tokenIn, address tokenOut) internal {
    failedSwapCount[tokenIn][tokenOut]++;
    if (failedSwapCount[tokenIn][tokenOut] >= MAX_FAILED_SWAPS) {
        // Temporarily disable this pair
    }
}
```

## Conclusion

The SwapRouter contract provides essential functionality for token swapping but has several security vulnerabilities that need immediate attention. The most critical issues are:

1. **Missing reentrancy protection** - Could lead to fund loss
2. **Insufficient slippage validation** - Users could face significant losses
3. **Lack of proper error handling** - Could result in stuck tokens
4. **Missing access controls** - Potential for DOS attacks

**Priority**: Address high-severity findings immediately, particularly reentrancy protection and slippage validation, before production deployment.

The contract should undergo another security review after implementing these fixes, with particular focus on integration testing with various token types and edge cases.