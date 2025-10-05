// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/ISwapRouter.sol" as IEdenSwapRouter;

interface IUniswapV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}

interface IUniswapV3QuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

/**
 * @title EdenSwapRouter
 * @notice Secure token swap router with comprehensive protection mechanisms
 * @dev Integrates with Uniswap V3 while providing additional security and validation layers
 */
contract EdenSwapRouter is IEdenSwapRouter.ISwapRouter, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ CONSTANTS ============
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant QUOTE_GAS_LIMIT = 6000000;
    uint256 public constant MAX_SLIPPAGE_BASIS_POINTS = 300;
    uint256 public constant MAX_FAILED_SWAPS = 5;
    uint256 public constant FAILURE_RESET_TIME = 1 hours;

    // ============ IMMUTABLE VARIABLES ============
    IUniswapV3SwapRouter public immutable uniswapRouter;
    IUniswapV3QuoterV2 public immutable quoter;

    // ============ STATE VARIABLES ============
    uint24 public defaultPoolFee = 3000;
    uint256 public maxSlippageBasisPoints = 300;
    uint256 public quoteRateLimit = 1;

    // ============ MAPPINGS ============
    mapping(address => mapping(address => uint24)) public poolFees;
    mapping(address => uint256) public lastQuoteTime;
    mapping(address => mapping(address => uint256)) public failedSwapCount;
    mapping(address => mapping(address => uint256)) public lastFailureTime;

    // ============ EVENTS ============
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event PoolFeeSet(address tokenA, address tokenB, uint24 fee);
    event DefaultPoolFeeSet(uint24 oldFee, uint24 newFee);
    event MaxSlippageSet(uint256 oldSlippage, uint256 newSlippage);
    event QuoteRequested(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event SlippageProtectionTriggered(uint256 expected, uint256 minimum, uint256 actual);
    event TokensRecovered(address indexed token, uint256 amount, address indexed to);
    event SwapFailureRecorded(address indexed tokenIn, address indexed tokenOut, uint256 failureCount);
    event QuoteRateLimitSet(uint256 oldLimit, uint256 newLimit);

    // ============ ERRORS ============
    error InvalidFee(uint24 fee);
    error InvalidAddress(address addr);
    error SwapFailed(string reason);
    error InsufficientAmountOut(uint256 expected, uint256 actual);
    error SlippageProtectionTooLow(uint256 minimum, uint256 required);
    error RateLimitExceeded(uint256 timeLeft);
    error TooManyFailures(address tokenIn, address tokenOut);
    error NoLiquidityAvailable();
    error InvalidSlippageValue(uint256 slippage);
    error AmountMismatch(uint256 expected, uint256 actual);

    // ============ MODIFIERS ============
    modifier rateLimit() {
        uint256 timeSinceLastQuote = block.timestamp - lastQuoteTime[msg.sender];
        if (timeSinceLastQuote < quoteRateLimit) {
            revert RateLimitExceeded(quoteRateLimit - timeSinceLastQuote);
        }
        lastQuoteTime[msg.sender] = block.timestamp;
        _;
    }

    modifier validTokenPair(address tokenIn, address tokenOut) {
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidAddress(tokenIn);
        if (tokenIn == tokenOut) revert InvalidAddress(tokenIn);
        _;
    }

    modifier notTooManyFailures(address tokenIn, address tokenOut) {
        if (block.timestamp >= lastFailureTime[tokenIn][tokenOut] + FAILURE_RESET_TIME) {
            failedSwapCount[tokenIn][tokenOut] = 0;
        }

        if (failedSwapCount[tokenIn][tokenOut] >= MAX_FAILED_SWAPS) {
            revert TooManyFailures(tokenIn, tokenOut);
        }
        _;
    }

    constructor(address _uniswapRouter, address _quoter, address _owner) Ownable(_owner) {
        if (_uniswapRouter == address(0)) revert InvalidAddress(_uniswapRouter);
        if (_quoter == address(0)) revert InvalidAddress(_quoter);
        if (_owner == address(0)) revert InvalidAddress(_owner);

        uniswapRouter = IUniswapV3SwapRouter(_uniswapRouter);
        quoter = IUniswapV3QuoterV2(_quoter);
    }

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external override nonReentrant whenNotPaused validTokenPair(tokenIn, tokenOut) returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        if (deadline < block.timestamp) revert("Deadline expired");

        uint256 quotedAmount = _getQuoteInternal(tokenIn, tokenOut, amountIn);
        if (quotedAmount == 0) revert NoLiquidityAvailable();

        _validateSlippageProtection(quotedAmount, amountOutMinimum);

        uint256 contractBalanceBefore = IERC20(tokenIn).balanceOf(address(this));
        uint256 recipientBalanceBefore = IERC20(tokenOut).balanceOf(msg.sender);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        uint256 contractBalanceAfter = IERC20(tokenIn).balanceOf(address(this));
        if (contractBalanceAfter < contractBalanceBefore + amountIn) {
            revert("Transfer failed");
        }

        _approveTokenIfNeeded(tokenIn, address(uniswapRouter), amountIn);

        uint24 fee = _getPoolFee(tokenIn, tokenOut);

        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: msg.sender,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        uint256 _amountOut = uniswapRouter.exactInputSingle(params);

        uint256 recipientBalanceAfter = IERC20(tokenOut).balanceOf(msg.sender);
        uint256 actualAmountOut = recipientBalanceAfter - recipientBalanceBefore;

        if (actualAmountOut != _amountOut) {
            revert AmountMismatch(_amountOut, actualAmountOut);
        }

        if (actualAmountOut < amountOutMinimum) {
            revert InsufficientAmountOut(amountOutMinimum, actualAmountOut);
        }

        amountOut = actualAmountOut;

        _clearApproval(tokenIn, address(uniswapRouter));

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
    }

    // ============ QUOTE FUNCTIONS ============
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
        external
        override
        rateLimit
        validTokenPair(tokenIn, tokenOut)
        returns (uint256 amountOut)
    {
        amountOut = _getQuoteInternal(tokenIn, tokenOut, amountIn);
        emit QuoteRequested(tokenIn, tokenOut, amountIn, amountOut);
    }

    function getAmountOutWithDetails(address tokenIn, address tokenOut, uint256 amountIn)
        external
        rateLimit
        validTokenPair(tokenIn, tokenOut)
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        if (amountIn == 0) return (0, 0, 0, 0);

        uint24 fee = _getPoolFee(tokenIn, tokenOut);

        IUniswapV3QuoterV2.QuoteExactInputSingleParams memory params = IUniswapV3QuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            fee: fee,
            sqrtPriceLimitX96: 0
        });

        try quoter.quoteExactInputSingle{gas: QUOTE_GAS_LIMIT}(params) returns (
            uint256 _amountOut, uint160 _sqrtPriceX96After, uint32 _initializedTicksCrossed, uint256 _gasEstimate
        ) {
            emit QuoteRequested(tokenIn, tokenOut, amountIn, _amountOut);
            return (_amountOut, _sqrtPriceX96After, _initializedTicksCrossed, _gasEstimate);
        } catch {
            return (0, 0, 0, 0);
        }
    }

    function setPoolFee(address tokenA, address tokenB, uint24 fee) external onlyOwner {
        if (fee != 500 && fee != 3000 && fee != 10000) revert InvalidFee(fee);

        poolFees[tokenA][tokenB] = fee;
        poolFees[tokenB][tokenA] = fee;

        emit PoolFeeSet(tokenA, tokenB, fee);
    }

    function setDefaultPoolFee(uint24 fee) external onlyOwner {
        if (fee != 500 && fee != 3000 && fee != 10000) revert InvalidFee(fee);

        uint24 oldFee = defaultPoolFee;
        defaultPoolFee = fee;

        emit DefaultPoolFeeSet(oldFee, fee);
    }

    function setMaxSlippage(uint256 _maxSlippageBasisPoints) external onlyOwner {
        if (_maxSlippageBasisPoints > MAX_SLIPPAGE_BASIS_POINTS) {
            revert InvalidSlippageValue(_maxSlippageBasisPoints);
        }

        uint256 oldSlippage = maxSlippageBasisPoints;
        maxSlippageBasisPoints = _maxSlippageBasisPoints;

        emit MaxSlippageSet(oldSlippage, _maxSlippageBasisPoints);
    }

    function setQuoteRateLimit(uint256 _rateLimit) external onlyOwner {
        if (_rateLimit > 60) revert("Rate limit too high");

        uint256 oldLimit = quoteRateLimit;
        quoteRateLimit = _rateLimit;

        emit QuoteRateLimitSet(oldLimit, _rateLimit);
    }

    function removePoolFee(address tokenA, address tokenB) external onlyOwner {
        delete poolFees[tokenA][tokenB];
        delete poolFees[tokenB][tokenA];

        emit PoolFeeSet(tokenA, tokenB, 0);
    }

    function resetFailureCount(address tokenIn, address tokenOut) external onlyOwner {
        failedSwapCount[tokenIn][tokenOut] = 0;
        lastFailureTime[tokenIn][tokenOut] = 0;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyTokenRecovery(address token, uint256 amount, address to) external onlyOwner {
        if (to == address(0)) revert InvalidAddress(to);
        IERC20(token).safeTransfer(to, amount);
        emit TokensRecovered(token, amount, to);
    }

    // ============ VIEW FUNCTIONS ============
    function getPoolFee(address tokenA, address tokenB) external view returns (uint24 fee) {
        return _getPoolFee(tokenA, tokenB);
    }

    function getFailureCount(address tokenIn, address tokenOut) external view returns (uint256) {
        if (block.timestamp >= lastFailureTime[tokenIn][tokenOut] + FAILURE_RESET_TIME) {
            return 0;
        }
        return failedSwapCount[tokenIn][tokenOut];
    }

    function isRateLimited(address user) external view returns (bool) {
        return block.timestamp < lastQuoteTime[user] + quoteRateLimit;
    }

    function getTimeUntilNextQuote(address user) external view returns (uint256) {
        uint256 nextQuoteTime = lastQuoteTime[user] + quoteRateLimit;
        if (block.timestamp >= nextQuoteTime) {
            return 0;
        }
        return nextQuoteTime - block.timestamp;
    }

    // ============ INTERNAL FUNCTIONS ============
    function _getQuoteInternal(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;

        uint24 fee = _getPoolFee(tokenIn, tokenOut);

        IUniswapV3QuoterV2.QuoteExactInputSingleParams memory params = IUniswapV3QuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            fee: fee,
            sqrtPriceLimitX96: 0
        });

        try quoter.quoteExactInputSingle{gas: QUOTE_GAS_LIMIT}(params) returns (
            uint256 _amountOut, uint160, uint32, uint256
        ) {
            amountOut = _amountOut;
        } catch {
            amountOut = 0;
        }
    }

    function _validateSlippageProtection(uint256 quotedAmount, uint256 amountOutMinimum) internal {
        uint256 minAcceptableAmount = (quotedAmount * (BASIS_POINTS - maxSlippageBasisPoints)) / BASIS_POINTS;
        if (amountOutMinimum < minAcceptableAmount) {
            emit SlippageProtectionTriggered(quotedAmount, amountOutMinimum, minAcceptableAmount);
            revert SlippageProtectionTooLow(amountOutMinimum, minAcceptableAmount);
        }
    }

    function _approveTokenIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20(token).allowance(address(this), spender);
        if (currentAllowance < amount) {
            if (currentAllowance > 0) {
                IERC20(token).forceApprove(spender, 0);
            }
            IERC20(token).forceApprove(spender, amount);
        }
    }

    function _clearApproval(address token, address spender) internal {
        IERC20(token).forceApprove(spender, 0);
    }

    function _refundTokens(address token, uint256 amount) internal {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 refundAmount = balance >= amount ? amount : balance;
        if (refundAmount > 0) {
            IERC20(token).safeTransfer(msg.sender, refundAmount);
        }
    }

    function _recordSwapFailure(address tokenIn, address tokenOut) internal {
        failedSwapCount[tokenIn][tokenOut]++;
        lastFailureTime[tokenIn][tokenOut] = block.timestamp;

        emit SwapFailureRecorded(tokenIn, tokenOut, failedSwapCount[tokenIn][tokenOut]);
    }

    function _getPoolFee(address tokenA, address tokenB) internal view returns (uint24) {
        uint24 fee = poolFees[tokenA][tokenB];
        return fee > 0 ? fee : defaultPoolFee;
    }
}
