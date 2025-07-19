// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ISwapRouter {
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);
}
