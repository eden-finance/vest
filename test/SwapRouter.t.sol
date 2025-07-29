// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import "./EdenVestTestBase.sol";
import "../src/vest/SwapRouter.sol";
import "./mocks/MockUniswapV3Router.sol";
import "./mocks/MockUniswapV3Quoter.sol";
import "./mocks/MockERC20.sol";

contract SwapRouterTest is EdenVestTestBase {
    SwapRouter public swapRouterSecure;
    MockUniswapV3Router public mockRouter;
    MockUniswapV3Quoter public mockQuoter;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    // Test constants
    uint256 constant QUOTE_AMOUNT = 1000e18;
    uint256 constant SWAP_AMOUNT = 500e18;
    uint24 constant DEFAULT_FEE = 3000;
    uint256 constant DEFAULT_SLIPPAGE = 300; // 3%
    uint256 public constant BASIS_POINTS = 10000;

    function setUp() public override {
        super.setUp();

        // Deploy mock contracts
        mockRouter = new MockUniswapV3Router();
        mockQuoter = new MockUniswapV3Quoter();

        // Deploy secure SwapRouter
        swapRouterSecure = new SwapRouter(address(mockRouter), address(mockQuoter), admin);

        // Deploy test tokens
        tokenA = new MockERC20("Token A", "TKNA", 18);
        tokenB = new MockERC20("Token B", "TKNB", 18);

        // Mint tokens to users
        tokenA.mint(user1, 100000e18);
        tokenA.mint(user2, 100000e18);
        tokenB.mint(address(mockRouter), 100000e18); // Router needs tokens to "swap"

        // Set up mock quoter response
        mockQuoter.setQuoteResponse(QUOTE_AMOUNT);

        // Label addresses
        vm.label(address(swapRouterSecure), "SwapRouterSecure");
        vm.label(address(mockRouter), "MockRouter");
        vm.label(address(mockQuoter), "MockQuoter");
        vm.label(address(tokenA), "TokenA");
        vm.label(address(tokenB), "TokenB");
    }

    // ============ INITIALIZATION TESTS ============

    function test_Initialize_Success() public {
        SwapRouter newRouter = new SwapRouter(address(mockRouter), address(mockQuoter), admin);

        assertEq(address(newRouter.uniswapRouter()), address(mockRouter), "Router not set correctly");
        assertEq(address(newRouter.quoter()), address(mockQuoter), "Quoter not set correctly");
        assertEq(newRouter.owner(), admin, "Owner not set correctly");
        assertEq(newRouter.defaultPoolFee(), 3000, "Default fee not set correctly");
        assertEq(newRouter.maxSlippageBasisPoints(), 300, "Max slippage not set correctly");
    }

    function test_RevertWhen_InitializeWithZeroRouter() public {
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.InvalidAddress.selector, address(0)));
        new SwapRouter(address(0), address(mockQuoter), admin);
    }

    function test_RevertWhen_InitializeWithZeroQuoter() public {
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.InvalidAddress.selector, address(0)));
        new SwapRouter(address(mockRouter), address(0), admin);
    }

    function test_RevertWhen_InitializeWithZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new SwapRouter(address(mockRouter), address(mockQuoter), address(0));
    }

    // ============ SWAP FUNCTIONALITY TESTS ============

    function test_SwapExactTokensForTokens_Success() public {
        uint256 amountIn = SWAP_AMOUNT;
        uint256 expectedOut = QUOTE_AMOUNT;
        uint256 minAmountOut = (expectedOut * 97) / 100; // 3% slippage tolerance
        uint256 deadline = block.timestamp + 300;

        // Set up mock router to return expected amount
        mockRouter.setSwapResponse(expectedOut);

        vm.startPrank(user1);
        tokenA.approve(address(swapRouterSecure), amountIn);

        uint256 balanceBefore = tokenB.balanceOf(user1);

        uint256 amountOut = swapRouterSecure.swapExactTokensForTokens(
            address(tokenA), address(tokenB), amountIn, minAmountOut, deadline
        );

        uint256 balanceAfter = tokenB.balanceOf(user1);
        vm.stopPrank();

        assertEq(amountOut, expectedOut, "Amount out should match expected");
        assertEq(balanceAfter - balanceBefore, expectedOut, "Balance change should match amount out");
        assertGe(amountOut, minAmountOut, "Amount out should meet minimum requirement");
    }

    function test_RevertWhen_SwapWithZeroAmount() public {
        uint256 deadline = block.timestamp + 300;

        vm.prank(user1);
        uint256 amountOut = swapRouterSecure.swapExactTokensForTokens(
            address(tokenA),
            address(tokenB),
            0, // Zero amount
            0,
            deadline
        );

        assertEq(amountOut, 0, "Should return 0 for zero amount input");
    }

    function test_RevertWhen_SwapWithExpiredDeadline() public {
        uint256 amountIn = SWAP_AMOUNT;
        uint256 minAmountOut = 1;
        uint256 deadline = block.timestamp - 1; // Expired deadline

        vm.startPrank(user1);
        tokenA.approve(address(swapRouterSecure), amountIn);

        vm.expectRevert("Deadline expired");
        swapRouterSecure.swapExactTokensForTokens(address(tokenA), address(tokenB), amountIn, minAmountOut, deadline);
        vm.stopPrank();
    }

    function test_RevertWhen_SwapWithInvalidTokens() public {
        uint256 amountIn = SWAP_AMOUNT;
        uint256 minAmountOut = 1;
        uint256 deadline = block.timestamp + 300;

        vm.startPrank(user1);

        // Test zero address tokenIn
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.InvalidAddress.selector, address(0)));
        swapRouterSecure.swapExactTokensForTokens(address(0), address(tokenB), amountIn, minAmountOut, deadline);

        // Test zero address tokenOut
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.InvalidAddress.selector, address(tokenA)));
        swapRouterSecure.swapExactTokensForTokens(address(tokenA), address(0), amountIn, minAmountOut, deadline);

        // Test same token addresses
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.InvalidAddress.selector, address(tokenA)));
        swapRouterSecure.swapExactTokensForTokens(address(tokenA), address(tokenA), amountIn, minAmountOut, deadline);

        vm.stopPrank();
    }

    function test_SwapWithSlippageProtection() public {
        uint256 amountIn = SWAP_AMOUNT;
        uint256 expectedOut = QUOTE_AMOUNT;
        uint256 tooLowMinAmount = (expectedOut * 90) / 100; // 10% slippage (too high)
        uint256 deadline = block.timestamp + 300;

        vm.startPrank(user1);
        tokenA.approve(address(swapRouterSecure), amountIn);

        // Should revert due to slippage protection (10% > 3% max)
        vm.expectRevert(
            abi.encodeWithSelector(
                SwapRouter.SlippageProtectionTooLow.selector,
                tooLowMinAmount,
                (expectedOut * 97) / 100 // 3% max slippage
            )
        );
        swapRouterSecure.swapExactTokensForTokens(address(tokenA), address(tokenB), amountIn, tooLowMinAmount, deadline);
        vm.stopPrank();
    }

    function test_SwapWithNoLiquidity() public {
        uint256 amountIn = SWAP_AMOUNT;
        uint256 minAmountOut = 1;
        uint256 deadline = block.timestamp + 300;

        // Set quoter to return 0 (no liquidity)
        mockQuoter.setQuoteResponse(0);

        vm.startPrank(user1);
        tokenA.approve(address(swapRouterSecure), amountIn);

        vm.expectRevert(SwapRouter.NoLiquidityAvailable.selector);
        swapRouterSecure.swapExactTokensForTokens(address(tokenA), address(tokenB), amountIn, minAmountOut, deadline);
        vm.stopPrank();
    }

    // ============ QUOTE FUNCTIONALITY TESTS ============

    function test_GetAmountOut_Success() public {
        uint256 amountIn = SWAP_AMOUNT;
        uint256 expectedOut = QUOTE_AMOUNT;

        vm.prank(user1);
        uint256 amountOut = swapRouterSecure.getAmountOut(address(tokenA), address(tokenB), amountIn);

        assertEq(amountOut, expectedOut, "Quote should match expected amount");
    }

    function test_GetAmountOut_WithRateLimit() public {
        uint256 amountIn = SWAP_AMOUNT;

        vm.startPrank(user1);

        // First quote should succeed
        swapRouterSecure.getAmountOut(address(tokenA), address(tokenB), amountIn);

        // Second quote immediately should fail due to rate limit
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.RateLimitExceeded.selector, 1));
        swapRouterSecure.getAmountOut(address(tokenA), address(tokenB), amountIn);

        // After waiting, should succeed again
        vm.warp(block.timestamp + 2);
        swapRouterSecure.getAmountOut(address(tokenA), address(tokenB), amountIn);

        vm.stopPrank();
    }

    function test_GetAmountOutWithDetails_Success() public {
        uint256 amountIn = SWAP_AMOUNT;

        vm.prank(user1);
        (uint256 amountOut, uint160 sqrtPrice, uint32 ticksCrossed, uint256 gasEstimate) =
            swapRouterSecure.getAmountOutWithDetails(address(tokenA), address(tokenB), amountIn);

        assertEq(amountOut, QUOTE_AMOUNT, "Amount out should match expected");
        assertGt(sqrtPrice, 0, "Sqrt price should be set");
        assertGt(gasEstimate, 0, "Gas estimate should be set");
    }

    function test_GetAmountOut_ZeroAmount() public {
        vm.prank(user1);
        uint256 amountOut = swapRouterSecure.getAmountOut(address(tokenA), address(tokenB), 0);
        assertEq(amountOut, 0, "Should return 0 for zero input");
    }

    // ============ ADMIN FUNCTIONALITY TESTS ============

    function test_SetPoolFee_Success() public {
        uint24 newFee = 500; // 0.05%

        vm.prank(admin);
        swapRouterSecure.setPoolFee(address(tokenA), address(tokenB), newFee);

        assertEq(swapRouterSecure.getPoolFee(address(tokenA), address(tokenB)), newFee, "Pool fee should be updated");
        assertEq(
            swapRouterSecure.getPoolFee(address(tokenB), address(tokenA)), newFee, "Pool fee should be bidirectional"
        );
    }

    function test_RevertWhen_SetInvalidPoolFee() public {
        uint24 invalidFee = 1234;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.InvalidFee.selector, invalidFee));
        swapRouterSecure.setPoolFee(address(tokenA), address(tokenB), invalidFee);
    }

    function test_RevertWhen_NonOwnerSetsPoolFee() public {
    vm.prank(user1);
    
    vm.expectRevert(
        abi.encodeWithSelector(
            Ownable.OwnableUnauthorizedAccount.selector, 
            user1 
        )
    );
    
    swapRouterSecure.setPoolFee(address(tokenA), address(tokenB), 500);
}



    function test_SetDefaultPoolFee_Success() public {
        uint24 newFee = 10000; // 1%

        vm.prank(admin);
        swapRouterSecure.setDefaultPoolFee(newFee);

        assertEq(swapRouterSecure.defaultPoolFee(), newFee, "Default pool fee should be updated");
    }

    function test_SetMaxSlippage_Success() public {
        uint256 newSlippage = 200; // 2%

        vm.prank(admin);
        swapRouterSecure.setMaxSlippage(newSlippage);

        assertEq(swapRouterSecure.maxSlippageBasisPoints(), newSlippage, "Max slippage should be updated");
    }

    function test_RevertWhen_SetSlippageTooHigh() public {
        uint256 tooHighSlippage = 500; // 5% > 3% max

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.InvalidSlippageValue.selector, tooHighSlippage));
        swapRouterSecure.setMaxSlippage(tooHighSlippage);
    }

    function test_SetQuoteRateLimit_Success() public {
        uint256 newLimit = 5; // 5 seconds

        vm.prank(admin);
        swapRouterSecure.setQuoteRateLimit(newLimit);

        assertEq(swapRouterSecure.quoteRateLimit(), newLimit, "Quote rate limit should be updated");
    }

    function test_RemovePoolFee_Success() public {
        // First set a custom fee
        vm.prank(admin);
        swapRouterSecure.setPoolFee(address(tokenA), address(tokenB), 500);

        // Then remove it
        vm.prank(admin);
        swapRouterSecure.removePoolFee(address(tokenA), address(tokenB));

        // Should revert to default fee
        assertEq(
            swapRouterSecure.getPoolFee(address(tokenA), address(tokenB)),
            swapRouterSecure.defaultPoolFee(),
            "Should revert to default fee"
        );
    }


    // ============ PAUSE FUNCTIONALITY TESTS ============

    function test_Pause_Success() public {
        vm.prank(admin);
        swapRouterSecure.pause();

        assertTrue(swapRouterSecure.paused(), "Contract should be paused");
    }

    function test_RevertWhen_SwapWhilePaused() public {
        vm.prank(admin);
        swapRouterSecure.pause();

        vm.startPrank(user1);
        tokenA.approve(address(swapRouterSecure), SWAP_AMOUNT);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        swapRouterSecure.swapExactTokensForTokens(
            address(tokenA), address(tokenB), SWAP_AMOUNT, 1, block.timestamp + 300
        );
        vm.stopPrank();
    }

    function test_Unpause_Success() public {
        vm.startPrank(admin);
        swapRouterSecure.pause();
        swapRouterSecure.unpause();
        vm.stopPrank();

        assertFalse(swapRouterSecure.paused(), "Contract should be unpaused");
    }

    // ============ EMERGENCY RECOVERY TESTS ============

    function test_EmergencyTokenRecovery_Success() public {
        uint256 recoveryAmount = 1000e18;

        // Send tokens to contract (simulating stuck tokens)
        tokenA.mint(address(swapRouterSecure), recoveryAmount);

        uint256 treasuryBalanceBefore = tokenA.balanceOf(treasury);

        vm.prank(admin);
        swapRouterSecure.emergencyTokenRecovery(address(tokenA), recoveryAmount, treasury);

        uint256 treasuryBalanceAfter = tokenA.balanceOf(treasury);

        assertEq(
            treasuryBalanceAfter - treasuryBalanceBefore, recoveryAmount, "Treasury should receive recovered tokens"
        );
    }

    function test_RevertWhen_EmergencyRecoveryToZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SwapRouter.InvalidAddress.selector, address(0)));
        swapRouterSecure.emergencyTokenRecovery(address(tokenA), 1000e18, address(0));
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_IsRateLimited_Success() public {
        // Initially not rate limited
        assertFalse(swapRouterSecure.isRateLimited(user1), "Should not be rate limited initially");

        // After a quote, should be rate limited
        vm.prank(user1);
        swapRouterSecure.getAmountOut(address(tokenA), address(tokenB), SWAP_AMOUNT);

        assertTrue(swapRouterSecure.isRateLimited(user1), "Should be rate limited after quote");

        // After waiting, should not be rate limited
        vm.warp(block.timestamp + 2);
        assertFalse(swapRouterSecure.isRateLimited(user1), "Should not be rate limited after waiting");
    }

    function test_GetTimeUntilNextQuote_Success() public {
        // Initially should be 0
        assertEq(swapRouterSecure.getTimeUntilNextQuote(user1), 0, "Should be 0 initially");

        // After a quote, should show remaining time
        vm.prank(user1);
        swapRouterSecure.getAmountOut(address(tokenA), address(tokenB), SWAP_AMOUNT);

        assertEq(swapRouterSecure.getTimeUntilNextQuote(user1), 1, "Should show 1 second remaining");

        // After waiting, should be 0 again
        vm.warp(block.timestamp + 2);
        assertEq(swapRouterSecure.getTimeUntilNextQuote(user1), 0, "Should be 0 after waiting");
    }

    // ============ EVENT EMISSION TESTS ============

    function test_SwapExecuted_EventEmission() public {
        uint256 amountIn = SWAP_AMOUNT;
        uint256 expectedOut = QUOTE_AMOUNT;
        uint256 minAmountOut = (expectedOut * 97) / 100;
        uint256 deadline = block.timestamp + 300;

        mockRouter.setSwapResponse(expectedOut);

        vm.startPrank(user1);
        tokenA.approve(address(swapRouterSecure), amountIn);

        vm.expectEmit(true, true, false, true);
        emit SwapExecuted(address(tokenA), address(tokenB), amountIn, expectedOut);

        swapRouterSecure.swapExactTokensForTokens(address(tokenA), address(tokenB), amountIn, minAmountOut, deadline);
        vm.stopPrank();
    }

    function test_QuoteRequested_EventEmission() public {
        uint256 amountIn = SWAP_AMOUNT;
        uint256 expectedOut = QUOTE_AMOUNT;

        vm.expectEmit(true, true, false, true);
        emit QuoteRequested(address(tokenA), address(tokenB), amountIn, expectedOut);

        vm.prank(user1);
        swapRouterSecure.getAmountOut(address(tokenA), address(tokenB), amountIn);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_SwapAmounts(uint96 amountIn) public {
        vm.assume(amountIn > 0);
        vm.assume(amountIn <= 10000e18); // Reasonable upper bound

        uint256 expectedOut = (amountIn * QUOTE_AMOUNT) / SWAP_AMOUNT; // Proportional quote
        mockQuoter.setQuoteResponse(expectedOut);
        mockRouter.setSwapResponse(expectedOut);

        uint256 minAmountOut = (expectedOut * 97) / 100; // 3% slippage
        uint256 deadline = block.timestamp + 300;

        // Ensure user has enough tokens
        tokenA.mint(user1, amountIn);

        vm.startPrank(user1);
        tokenA.approve(address(swapRouterSecure), amountIn);

        if (expectedOut > 0) {
            uint256 amountOut = swapRouterSecure.swapExactTokensForTokens(
                address(tokenA), address(tokenB), amountIn, minAmountOut, deadline
            );

            assertEq(amountOut, expectedOut, "Amount out should match expected");
            assertGe(amountOut, minAmountOut, "Amount out should meet minimum");
        }
        vm.stopPrank();
    }

   function testFuzz_PoolFees(uint8 feeIndex) public {
    uint24 fee = [uint24(500), 3000, 10000][feeIndex % 3];

    vm.prank(admin);
    swapRouterSecure.setPoolFee(address(tokenA), address(tokenB), fee);

    assertEq(
        swapRouterSecure.getPoolFee(address(tokenA), address(tokenB)),
        fee,
        "Pool fee should be set correctly"
    );
}


    function testFuzz_SlippageValues(uint96 slippage) public {
        vm.assume(slippage <= 300); // Max 3%

        vm.prank(admin);
        swapRouterSecure.setMaxSlippage(slippage);

        assertEq(swapRouterSecure.maxSlippageBasisPoints(), slippage, "Slippage should be set correctly");
    }

    // ============ HELPER EVENTS ============

    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event QuoteRequested(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
}
