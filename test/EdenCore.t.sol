// test/EdenCore.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/console.sol";

import "./EdenVestTestBase.sol";
import "../src/vest/interfaces/IInvestmentPool.sol";

contract EdenCoreTest is EdenVestTestBase {
    address public pool;
    address public lpToken;

    function setUp() public override {
        super.setUp();

        // Create a default pool
        vm.prank(admin);
        pool = edenCore.createPool(defaultPoolParams);
        (,, address _lpToken,,) = edenCore.poolInfo(pool);

        lpToken = _lpToken;

        // Authorize pool in NFT manager
        vm.prank(admin);
        nftManager.authorizePool(pool, true);
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public {
        EdenCore newCore = new EdenCore();
        newCore.initialize(address(cNGN), treasury, admin, 250);

        assertEq(newCore.cNGN(), address(cNGN), "cNGN not set");
        assertEq(newCore.protocolTreasury(), treasury, "Treasury not set");
        assertEq(newCore.globalTaxRate(), 250, "Tax rate not set");
        assertTrue(newCore.hasRole(newCore.ADMIN_ROLE(), admin), "Admin role not granted");
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        EdenCore newCore = new EdenCore();

        vm.expectRevert(EdenCore.InvalidAddress.selector);
        newCore.initialize(address(0), treasury, admin, 250);

        vm.expectRevert(EdenCore.InvalidAddress.selector);
        newCore.initialize(address(cNGN), address(0), admin, 250);
    }

    function test_RevertWhen_InitializeWithHighTaxRate() public {
        EdenCore newCore = new EdenCore();

        vm.expectRevert(EdenCore.InvalidTaxRate.selector);
        newCore.initialize(address(cNGN), treasury, admin, 1001); // > 10%
    }

    function test_AdminHasRole() public {
        EdenCore newCore = new EdenCore();
        newCore.initialize(address(cNGN), treasury, admin, 250);

        assertTrue(newCore.hasRole(newCore.EMERGENCY_ROLE(), admin), "Emergency role not granted");
        assertTrue(newCore.hasRole(newCore.POOL_CREATOR_ROLE(), admin), "Pool creator role not granted");
    }

    // ============ Pool Creation Tests ============

    function test_CreatePool_Success() public {
        vm.prank(admin);
        address newPool = edenCore.createPool(defaultPoolParams);

        assertTrue(edenCore.isRegisteredPool(newPool), "Pool not registered");

        (string memory name, address admin,,, bool isActive) = edenCore.poolInfo(newPool);
        assertEq(name, "Test Pool", "Pool name mismatch");
        assertEq(admin, admin, "Pool admin mismatch");
        assertTrue(isActive, "Pool not active");

        uint256 poolCount = edenCore.getAllPools().length;
        bool poolFound = false;

        for (uint256 i = 0; i < poolCount; i++) {
            address pool_ = edenCore.allPools(i);
            if (pool_ == newPool) {
                poolFound = true;
            }
        }
        assertTrue(poolFound, "Pool not found");
    }

    function test_RevertWhen_CreatePoolWithoutRole() public {
        vm.prank(user1);
        vm.expectRevert();
        edenCore.createPool(defaultPoolParams);
    }

    // ============ Investment Tests ============

    function test_Invest_Success() public {
        uint256 investAmount = 10000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), investAmount);

        (uint256 tokenId, uint256 lpTokens) = edenCore.invest(pool, investAmount, "Test Investment");
        vm.stopPrank();

        assertTrue(tokenId > 0, "Invalid token ID");
        assertTrue(lpTokens > 0, "No LP tokens received");

        uint256 taxRate = 250; //2.5%

        // Check LP token balance (after tax)
        uint256 expectedLpTokens = investAmount - (investAmount * taxRate / 10000);
        assertEq(IERC20(lpToken).balanceOf(user1), expectedLpTokens, "LP token balance mismatch");
    }

    function test_RevertWhen_InvestInInvalidPool() public {
        vm.startPrank(user1);
        cNGN.approve(address(edenCore), 10000e18);

        vm.expectRevert(EdenCore.InvalidPool.selector);
        edenCore.invest(address(0x999), 10000e18, "Test");
        vm.stopPrank();
    }

    function test_RevertWhen_InvestInInactivePool() public {
        // Deactivate pool
        vm.prank(admin);
        edenCore.setPoolActive(pool, false);

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), 10000e18);

        vm.expectRevert(EdenCore.PoolNotActive.selector);
        edenCore.invest(pool, 10000e18, "Test");
        vm.stopPrank();
    }

    function test_RevertWhen_InvestWhilePaused() public {
        vm.prank(admin);
        edenCore.pause();

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), 10000e18);

        vm.expectRevert("EnforcedPause()");
        edenCore.invest(pool, 10000e18, "Test");
        vm.stopPrank();
    }

    // ============ Withdrawal Tests ============

    function test_Withdraw_Success() public {
        // First invest
        uint256 investAmount = 10_000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), investAmount);
        (uint256 tokenId, uint256 lpTokens) = edenCore.invest(pool, investAmount, "Test Investment");
        vm.stopPrank();

        // Transfer funds back to pool for withdrawal
        vm.prank(multisig);

        cNGN.transfer(pool, investAmount + 1500e18); // principal + 15% returns

        // Warp time to maturity
        vm.warp(block.timestamp + 31 days);

        // Withdraw
        vm.startPrank(user1);
        IERC20(lpToken).approve(address(edenCore), lpTokens);

        uint256 balanceBefore = cNGN.balanceOf(user1);
        uint256 withdrawAmount = edenCore.withdraw(pool, tokenId, lpTokens);
        uint256 balanceAfter = cNGN.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, withdrawAmount, "Withdrawal amount mismatch");
        vm.stopPrank();
    }

    // ============ Tax Collection Tests ============

    function test_TaxCollection_Success() public {
        uint256 investAmount = 10000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), investAmount);
        edenCore.invest(pool, investAmount, "Test Investment");
        vm.stopPrank();

        // Check tax collected
        uint256 expectedTax = investAmount * 250 / 10000; // 2.5%
        assertEq(taxCollector.tokenTaxBalance(lpToken), expectedTax, "Tax not collected correctly");
    }

    // ============ Admin Function Tests ============

    function test_SetGlobalTaxRate_Success() public {
        vm.prank(admin);
        edenCore.setGlobalTaxRate(500); // 5%

        assertEq(edenCore.globalTaxRate(), 500, "Tax rate not updated");
    }

    function test_RevertWhen_SetTaxRateTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(EdenCore.InvalidTaxRate.selector);
        edenCore.setGlobalTaxRate(1001); // > 10%
    }

    function test_SetProtocolTreasury_Success() public {
        address newTreasury = address(0x999);

        vm.prank(admin);
        edenCore.setProtocolTreasury(newTreasury);

        assertEq(edenCore.protocolTreasury(), newTreasury, "Treasury not updated");
    }

    function test_EmergencyWithdraw_Success() public {
        // Send some tokens to EdenCore
        cNGN.mint(address(edenCore), 10000e18);

        uint256 balanceBefore = cNGN.balanceOf(treasury);

        vm.prank(admin);
        edenCore.emergencyWithdraw(address(cNGN), 10000e18);

        uint256 balanceAfter = cNGN.balanceOf(treasury);
        assertEq(balanceAfter - balanceBefore, 10000e18, "Emergency withdrawal failed");
    }

    // ============ View Function Tests ============

    function test_GetAllPools() public view {
        address[] memory pools = edenCore.getAllPools();
        assertEq(pools.length, 1, "Pool count mismatch");
        assertEq(pools[0], pool, "Pool address mismatch");
    }

    function test_GetActivePools() public {
        // Create another pool
        vm.prank(admin);
        address pool2 = edenCore.createPool(defaultPoolParams);

        // Deactivate first pool
        vm.prank(admin);
        edenCore.setPoolActive(pool, false);

        address[] memory activePools = edenCore.getActivePools();
        assertEq(activePools.length, 1, "Active pool count mismatch");
        assertEq(activePools[0], pool2, "Active pool address mismatch");
    }
}
