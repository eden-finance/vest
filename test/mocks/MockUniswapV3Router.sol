// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./MockERC20.sol";

// ============ MOCK UNISWAP V3 ROUTER ============
contract MockUniswapV3Router {
    using SafeERC20 for IERC20;

    uint256 public swapResponse;
    bool public shouldFail;
    string public failureReason = "Mock swap failed";

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

    function setSwapResponse(uint256 _response) external {
        swapResponse = _response;
    }

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function setFailureReason(string memory _reason) external {
        failureReason = _reason;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        if (shouldFail) {
            revert(failureReason);
        }

        // Simulate token transfer
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);

        // Check if we have enough output tokens
        uint256 balance = IERC20(params.tokenOut).balanceOf(address(this));
        require(balance >= swapResponse, "Mock router: insufficient output token balance");

        // Transfer output tokens to recipient
        IERC20(params.tokenOut).safeTransfer(params.recipient, swapResponse);

        return swapResponse;
    }

    // Function to fund the mock router with tokens for testing
    function fundWithTokens(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}

contract MaliciousToken is MockERC20 {
    bool public shouldFailTransfer;
    bool public shouldReentrancy;
    address public targetContract;

    constructor() MockERC20("Malicious Token", "MAL", 18) {}

    function setFailTransfer(bool _shouldFail) external {
        shouldFailTransfer = _shouldFail;
    }

    function setReentrancy(bool _shouldReentrancy, address _target) external {
        shouldReentrancy = _shouldReentrancy;
        targetContract = _target;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFailTransfer) {
            revert("Malicious token: transferFrom failed");
        }

        console.log("shouldReentrancy", shouldReentrancy);
        console.log("targetContract", targetContract);

        if (shouldReentrancy && targetContract != address(0)) {
            (bool success,) = targetContract.call(
                abi.encodeWithSignature(
                    "swapExactTokensForTokens(address,address,uint256,uint256,uint256)",
                    address(this),
                    to,
                    amount,
                    0,
                    block.timestamp + 300
                )
            );
            // Continue with normal transfer regardless of reentrancy result
        }

        return super.transferFrom(from, to, amount);
    }
}

contract MockTaxCollector {
    mapping(address => uint256) public tokenTaxBalance;

    function collectTax(address token, uint256 amount, address pool) external {
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
        tokenTaxBalance[token] += amount;
    }

    function getTokenTaxBalance(address token) external view returns (uint256) {
        return tokenTaxBalance[token];
    }
}
