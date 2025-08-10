// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "../src/vest/interfaces/ISwapRouter.sol";

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        returns (uint256 amountOut, uint160, uint32, uint256);
}

contract EdenSwapRouter_Integration is Test {
    // ===== Real deployed addresses on AssetChain =====
    address constant EDEN_SWAP_ROUTER = 0xAFb6ADa8C5b66eE46f475faD31Add0D5BCC5A745; // EdenSwapRouter
    address constant CNGN             = 0x5CDDBeBAc2260CF00654887184d6BA31096fE0a5; // cNGN
    address constant USDT             = 0x68dB7c3D77dbB0eD20DAE20CF5c8e6f215BA76FB; // USDT
    address constant QUOTER_V2        = 0x740aC3204dB2AA93cd7D5a320e8374Ef63d24dbf; // Uniswap V3 QuoterV2
    address constant CNGN_WHALE       = 0x54527B09Aeb2Be23F99958Db8f2f827daB863A28; // funded cNGN whale

    uint24 constant FEE_3000 = 3000;

    ISwapRouter router;
    IQuoterV2 quoter;
    address user;

    function setUp() public {
        // Fork AssetChain
        string memory rpc = vm.envString("RPC_URL");
        vm.createSelectFork(rpc);

        router = ISwapRouter(EDEN_SWAP_ROUTER);
        quoter = IQuoterV2(QUOTER_V2);

        // Choose a funded test user (could also just use vm.addr(...) but here we transfer to a known address)
        user = address(0x1234567890123456789012345678901234567890);

        // Fund user from whale
        vm.startPrank(CNGN_WHALE);
        IERC20(CNGN).transfer(user, 1_000e18);
        vm.stopPrank();
    }

    function test_swapExactTokensForTokens_real() public {
        uint256 amountIn = 100e18;

        // 1️⃣ Get real quote from Quoter
        (uint256 quotedOut,,,) = quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: CNGN,
                tokenOut: USDT,
                amountIn: amountIn,
                fee: FEE_3000,
                sqrtPriceLimitX96: 0
            })
        );
        assertGt(quotedOut, 0, "Quoter returned 0");
        uint256 minOut = (quotedOut * 97) / 100; // 3% slippage

        // 2️⃣ Approve router to spend CNGN
        vm.startPrank(user);
        IERC20(CNGN).approve(address(router), amountIn);

        // 3️⃣ Capture balances before
        uint256 beforeCngn = IERC20(CNGN).balanceOf(user);
        uint256 beforeUsdt = IERC20(USDT).balanceOf(user);

        // 4️⃣ Execute swap on deployed EdenSwapRouter
        uint256 outAmt = router.swapExactTokensForTokens(
            CNGN,
            USDT,
            amountIn,
            minOut,
            block.timestamp + 1200
        );

        // 5️⃣ Capture balances after
        uint256 afterCngn = IERC20(CNGN).balanceOf(user);
        uint256 afterUsdt = IERC20(USDT).balanceOf(user);
        vm.stopPrank();

        // 6️⃣ Assertions
        assertEq(beforeCngn - afterCngn, amountIn, "CNGN spent mismatch");
        assertEq(afterUsdt - beforeUsdt, outAmt, "USDT received mismatch");
        assertGt(outAmt, 0, "Output must be > 0");
    }
}