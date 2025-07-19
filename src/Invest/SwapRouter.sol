// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ISwapRouter.sol" as IEdenSwapRouter;

// Uniswap V3 Interface definitions
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

interface IUniswapV3Quoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

/**
 * @title SwapRouter
 * @notice Handles token swaps via Uniswap V3
 */
contract SwapRouter is IEdenSwapRouter.ISwapRouter, Ownable {
    using SafeERC20 for IERC20;

    IUniswapV3SwapRouter public immutable uniswapRouter;
    IUniswapV3Quoter public immutable quoter;
    uint24 public defaultPoolFee = 3000; // 0.3%

    mapping(address => mapping(address => uint24)) public poolFees;

    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event PoolFeeSet(address tokenA, address tokenB, uint24 fee);

    constructor(address _uniswapRouter, address _quoter, address _owner) Ownable(_owner) {
        uniswapRouter = IUniswapV3SwapRouter(_uniswapRouter);
        quoter = IUniswapV3Quoter(_quoter);
    }

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external override returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(uniswapRouter), amountIn);

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

        amountOut = uniswapRouter.exactInputSingle(params);

        emit SwapExecuted(tokenIn, tokenOut, amountIn, amountOut);
    }

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn)
        external
        override
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;

        uint24 fee = _getPoolFee(tokenIn, tokenOut);

        try quoter.quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn, 0) returns (uint256 _amountOut) {
            amountOut = _amountOut;
        } catch {
            amountOut = 0;
        }
    }

    function setPoolFee(address tokenA, address tokenB, uint24 fee) external onlyOwner {
        require(fee == 500 || fee == 3000 || fee == 10000, "Invalid fee");
        poolFees[tokenA][tokenB] = fee;
        poolFees[tokenB][tokenA] = fee;
        emit PoolFeeSet(tokenA, tokenB, fee);
    }

    function setDefaultPoolFee(uint24 fee) external onlyOwner {
        require(fee == 500 || fee == 3000 || fee == 10000, "Invalid fee");
        defaultPoolFee = fee;
    }

    function _getPoolFee(address tokenA, address tokenB) internal view returns (uint24) {
        uint24 fee = poolFees[tokenA][tokenB];
        return fee > 0 ? fee : defaultPoolFee;
    }
}
