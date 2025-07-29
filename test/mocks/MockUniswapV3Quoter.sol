// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract MockUniswapV3Quoter {
    uint256 public quoteResponse;
    uint160 public sqrtPriceX96After = 1000000000000000000; // Some reasonable default
    uint32 public initializedTicksCrossed = 5;
    uint256 public gasEstimate = 150000;
    bool public shouldFail;

    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function setQuoteResponse(uint256 _response) external {
        quoteResponse = _response;
    }

    function setQuoteDetails(uint256 _amountOut, uint160 _sqrtPriceX96After, uint32 _ticksCrossed, uint256 _gasEstimate)
        external
    {
        quoteResponse = _amountOut;
        sqrtPriceX96After = _sqrtPriceX96After;
        initializedTicksCrossed = _ticksCrossed;
        gasEstimate = _gasEstimate;
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96AfterResult,
            uint32 initializedTicksCrossedResult,
            uint256 gasEstimateResult
        )
    {
        if (shouldFail) {
            revert("Mock quoter: quote failed");
        }

        // For zero input, return zero
        if (params.amountIn == 0) {
            return (0, sqrtPriceX96After, 0, gasEstimate);
        }

        return (quoteResponse, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }
}
