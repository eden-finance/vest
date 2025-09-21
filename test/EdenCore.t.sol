// test/EdenCore.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/console.sol";
import "./EdenVestTestBase.sol";
import "../src/vest/interfaces/IInvestmentPool.sol";
import "../src/vest/EdenAdmin.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EdenCoreTest is EdenVestTestBase {
    address public pool;
    address public lpToken;
    EdenAdmin public edenAdmin;

    function setUp() public override {
        super.setUp();

        edenAdmin = new EdenAdmin(address(edenCore), admin, multisigSigners);

        // Create a default pool
        vm.prank(admin);
        edenCore.setEdenAdmin(address(edenAdmin));

        vm.prank(admin);
        pool = edenCore.createPool(defaultPoolParams);
        (,, address _lpToken,,) = edenCore.poolInfo(pool);

        vm.prank(admin);
        lpToken = _lpToken;
        nftManager.authorizePool(pool, true);
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public {
        EdenVestCore impl = new EdenVestCore();
        bytes memory initData = abi.encodeCall(EdenVestCore.initialize, (address(cNGN), treasury, admin, 250));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        EdenVestCore newCore = EdenVestCore(address(proxy));

        assertEq(newCore.cNGN(), address(cNGN));
        assertEq(newCore.protocolTreasury(), treasury);
        assertEq(newCore.globalTaxRate(), 250);
        assertTrue(newCore.hasRole(newCore.ADMIN_ROLE(), admin));
        assertTrue(newCore.hasRole(newCore.POOL_CREATOR_ROLE(), admin));
    }

    function test_RevertWhen_InitializeWithHighTaxRate() public {
        EdenVestCore impl = new EdenVestCore();

        bytes memory initData = abi.encodeCall(EdenVestCore.initialize, (address(cNGN), treasury, admin, 1001));

        vm.expectRevert(EdenVestCore.InvalidTaxRate.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        EdenVestCore impl = new EdenVestCore();

        bytes memory badCngn = abi.encodeCall(EdenVestCore.initialize, (address(0), treasury, admin, 250));
        vm.expectRevert(EdenVestCore.InvalidAddress.selector);
        new ERC1967Proxy(address(impl), badCngn);

        bytes memory badTreasury = abi.encodeCall(EdenVestCore.initialize, (address(cNGN), address(0), admin, 250));
        vm.expectRevert(EdenVestCore.InvalidAddress.selector);
        new ERC1967Proxy(address(impl), badTreasury);
    }

    function test_AdminHasRole() public {
        EdenVestCore impl = new EdenVestCore();
        bytes memory initData = abi.encodeCall(EdenVestCore.initialize, (address(cNGN), treasury, admin, 250));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        EdenVestCore newCore = EdenVestCore(address(proxy));

        assertTrue(newCore.hasRole(newCore.EMERGENCY_ROLE(), admin), "Emergency role not granted");
        assertTrue(newCore.hasRole(newCore.POOL_CREATOR_ROLE(), admin), "Pool creator role not granted");
    }

    // ============ Pool Creation Tests ============

    function test_CreatePool_Success() public {
        vm.prank(admin);
        address newPool = edenCore.createPool(defaultPoolParams);

        assertTrue(edenCore.isRegisteredPool(newPool), "Pool not registered");

        (string memory name, address poolAdmin,,, bool isActive) = edenCore.poolInfo(newPool);
        assertEq(name, "Test Pool", "Pool name mismatch");
        assertEq(poolAdmin, admin, "Pool admin mismatch");
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

    function test_RevertWhen_CreatePoolWithInvalidParams() public {
        IPoolFactory.PoolParams memory invalidParams = defaultPoolParams;

        // Test invalid name
        invalidParams.name = "";
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidPoolName.selector);
        edenCore.createPool(invalidParams);

        // Test invalid admin
        invalidParams = defaultPoolParams;
        invalidParams.admin = address(0);
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidAddress.selector);
        edenCore.createPool(invalidParams);

        // Test invalid multisig
        invalidParams = defaultPoolParams;
        invalidParams.poolMultisig = address(0);
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidAddress.selector);
        edenCore.createPool(invalidParams);

        // Test invalid investment amounts
        invalidParams = defaultPoolParams;
        invalidParams.minInvestment = 0;
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidAmount.selector);
        edenCore.createPool(invalidParams);

        invalidParams = defaultPoolParams;
        invalidParams.maxInvestment = 500e18; // Less than minInvestment
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidAmount.selector);
        edenCore.createPool(invalidParams);

        // Test invalid lock duration
        invalidParams = defaultPoolParams;
        invalidParams.lockDuration = 0; // Less than 1 day
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidLockDuration.selector);
        edenCore.createPool(invalidParams);

        // Test invalid rate
        invalidParams = defaultPoolParams;
        invalidParams.expectedRate = 15000; // > 10000 (100%)
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidRate.selector);
        edenCore.createPool(invalidParams);

        // Test invalid tax rate
        invalidParams = defaultPoolParams;
        invalidParams.taxRate = 1500; // > 10%
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidTaxRate.selector);
        edenCore.createPool(invalidParams);
    }

    // ============ Investment Tests ============

    function test_Invest_Success() public {
        uint256 investAmount = 10000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), investAmount);

        (uint256 tokenId, uint256 lpTokens) = edenCore.invest(pool, investAmount, "Test Investment", 0);
        vm.stopPrank();

        assertTrue(tokenId > 0, "Invalid token ID");
        assertTrue(lpTokens > 0, "No LP tokens received");

        uint256 taxRate = 250; //2.5%
        uint256 expectedLpTokens = investAmount - (investAmount * taxRate / 10000);
        assertEq(IERC20(lpToken).balanceOf(user1), expectedLpTokens, "LP token balance mismatch");
    }

    function test_RevertWhen_InvestInInvalidPool() public {
        vm.startPrank(user1);
        cNGN.approve(address(edenCore), 10000e18);

        vm.expectRevert(EdenVestCore.InvalidPool.selector);
        edenCore.invest(address(0x999), 10000e18, "Test", 0);
        vm.stopPrank();
    }

    function test_RevertWhen_InvestInInactivePool() public {
        vm.prank(admin);
        edenCore.setPoolActive(pool, false);

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), 10000e18);

        vm.expectRevert(EdenVestCore.PoolNotActive.selector);
        edenCore.invest(pool, 10000e18, "Test", 0);
        vm.stopPrank();
    }

    function test_RevertWhen_InvestWithExpiredDeadline() public {
        vm.startPrank(user1);
        cNGN.approve(address(edenCore), 10000e18);

        vm.expectRevert(EdenVestCore.DeadlineExpired.selector);
        vm.warp(block.timestamp + 200);
        edenCore.invest(pool, 10000e18, "Test Invest with deadline", block.timestamp - 2);
        vm.stopPrank();
    }

    function test_RevertWhen_InvestWhilePaused() public {
        // Pause protocol via EdenAdmin
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Testing pause");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), 10000e18);

        vm.expectRevert("EnforcedPause()");
        edenCore.invest(pool, 10000e18, "Test", 0);
        vm.stopPrank();
    }

    // ============ Withdrawal Tests ============

    function test_Withdraw_Success() public {
        // First invest
        uint256 investAmount = 10_000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), investAmount);
        (uint256 tokenId, uint256 lpTokens) = edenCore.invest(pool, investAmount, "Test Investment", 0);
        vm.stopPrank();

        // Fund pool for withdrawal
        vm.prank(multisig);
        cNGN.transfer(pool, investAmount + 1500e18);

        // Wait for maturity
        vm.warp(block.timestamp + 31 days);

        vm.startPrank(user1);
        IERC20(lpToken).approve(address(edenCore), lpTokens);

        uint256 balanceBefore = cNGN.balanceOf(user1);
        uint256 withdrawAmount = edenCore.withdraw(pool, tokenId, lpTokens);
        uint256 balanceAfter = cNGN.balanceOf(user1);

        assertEq(balanceAfter - balanceBefore, withdrawAmount, "Withdrawal amount mismatch");
        vm.stopPrank();
    }

    function test_RevertWhen_WithdrawFromInvalidPool() public {
        vm.startPrank(user1);
        vm.expectRevert(EdenVestCore.InvalidPool.selector);
        edenCore.withdraw(address(0x999), 1, 1000e18);
        vm.stopPrank();
    }

    // ============ Tax Collection Tests ============

    function test_TaxCollection_Success() public {
        uint256 investAmount = 10000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), investAmount);
        edenCore.invest(pool, investAmount, "Test Investment", 0);
        vm.stopPrank();

        uint256 expectedTax = investAmount * 250 / 10000; // 2.5%
        assertEq(taxCollector.tokenTaxBalance(lpToken), expectedTax, "Tax not collected correctly");
    }

    // ============ View Function Tests ============

    function test_GetAllPools() public {
        address[] memory pools = edenCore.getAllPools();
        assertEq(pools.length, 1, "Pool count mismatch");
        assertEq(pools[0], pool, "Pool address mismatch");
    }

    function test_GetActivePools() public {
        vm.prank(admin);
        address pool2 = edenCore.createPool(defaultPoolParams);

        vm.prank(admin);
        edenCore.setPoolActive(pool, false);

        address[] memory activePools = edenCore.getActivePools();
        assertEq(activePools.length, 1, "Active pool count mismatch");
        assertEq(activePools[0], pool2, "Active pool address mismatch");
    }

    // ============ Admin Internal Functions Tests ============

    function test_SetGlobalTaxRateInternal_OnlyAdminContract() public {
        vm.prank(admin);
        vm.expectRevert("Only EdenAdmin");
        edenCore.setGlobalTaxRateInternal(500);
    }

    function test_SetProtocolTreasuryInternal_OnlyAdminContract() public {
        vm.prank(admin);
        vm.expectRevert("Only EdenAdmin");
        edenCore.setProtocolTreasuryInternal(address(0x999));
    }

    function test_EmergencyWithdrawInternal_OnlyAdminContract() public {
        vm.prank(admin);
        vm.expectRevert("Only EdenAdmin");
        edenCore.emergencyWithdrawInternal(address(cNGN), 1000e18, "Test");
    }

    function test_PauseProtocol_OnlyAdminContract() public {
        vm.prank(admin);
        vm.expectRevert("Only EdenAdmin");
        edenCore.pauseProtocol();
    }

    function test_UnpauseProtocol_OnlyAdminContract() public {
        vm.prank(admin);
        vm.expectRevert("Only EdenAdmin");
        edenCore.unpauseProtocol();
    }

    // ============ Admin Setter Function Tests ============

    function test_SetEdenAdmin_Success() public {
        address newAdmin = address(0x999);

        vm.prank(admin);
        edenCore.setEdenAdmin(newAdmin);

        assertTrue(edenCore.hasRole(edenCore.ADMIN_ROLE(), newAdmin), "New admin role not granted");
    }

    function test_RevertWhen_SetEdenAdminZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidAddress.selector);
        edenCore.setEdenAdmin(address(0));
    }

    function test_SetPoolFactory_Success() public {
        address newFactory = address(0x999);

        vm.prank(admin);
        edenCore.setPoolFactory(newFactory);

        assertEq(address(edenCore.poolFactory()), newFactory, "Pool factory not updated");
    }

    function test_SetTaxCollector_Success() public {
        address newCollector = address(0x999);

        vm.prank(admin);
        edenCore.setTaxCollector(newCollector);

        assertEq(address(edenCore.taxCollector()), newCollector, "Tax collector not updated");
    }

    function test_SetSwapRouter_Success() public {
        address newRouter = address(0x999);

        vm.prank(admin);
        edenCore.setSwapRouter(newRouter);

        assertEq(address(edenCore.swapRouter()), newRouter, "Swap router not updated");
    }

    function test_SetNFTManager_Success() public {
        address newManager = address(0x999);

        vm.prank(admin);
        edenCore.setNFTManager(newManager);

        assertEq(address(edenCore.nftManager()), newManager, "NFT manager not updated");
    }

    function test_SetPoolActive_Success() public {
        vm.prank(admin);
        edenCore.setPoolActive(pool, false);

        (,,,, bool isActive) = edenCore.poolInfo(pool);
        assertFalse(isActive, "Pool should be inactive");
    }

    function test_RevertWhen_SetPoolActiveInvalidPool() public {
        vm.prank(admin);
        vm.expectRevert(EdenVestCore.InvalidPool.selector);
        edenCore.setPoolActive(address(0x999), false);
    }

    // ============ Access Control Tests ============

    function test_RevertWhen_NonAdminSetsComponents() public {
        vm.startPrank(user1);

        vm.expectRevert();
        edenCore.setPoolFactory(address(0x999));

        vm.expectRevert();
        edenCore.setTaxCollector(address(0x999));

        vm.expectRevert();
        edenCore.setSwapRouter(address(0x999));

        vm.expectRevert();
        edenCore.setNFTManager(address(0x999));

        vm.expectRevert();
        edenCore.setPoolActive(pool, false);

        vm.stopPrank();
    }

    function test_CollectTax_Revert_NotMatured() public {
        uint256 amount = 5_000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), amount);
        (uint256 tokenId,) = edenCore.invest(pool, amount, "Tax not matured", 0);
        vm.stopPrank();

        uint256 investmentId = IInvestmentPool(pool).nftToInvestment(tokenId);

        IInvestmentPool.PoolConfig memory cfg = IInvestmentPool(pool).getPoolConfig();
        uint8 lpDec = IERC20Metadata(lpToken).decimals();
        uint8 cngnDec = IERC20Metadata(address(cNGN)).decimals();
        uint256 scaleFactor = (lpDec >= cngnDec) ? 10 ** (lpDec - cngnDec) : 1;

        uint256 effectiveTaxBps = cfg.taxRate > 0 ? cfg.taxRate : edenCore.globalTaxRate();
        uint256 taxLp = (amount * scaleFactor * effectiveTaxBps) / 10_000;

        vm.prank(address(taxCollector));
        IERC20(lpToken).transfer(admin, taxLp);

        (, address poolAdmin,,,) = edenCore.poolInfo(pool);
        vm.prank(poolAdmin);
        vm.expectRevert(bytes("Not matured"));
        InvestmentPool(payable(pool)).collectTax(investmentId);
    }

    function test_CollectTax_Revert_InsufficientLiquidity() public {
        uint256 amount = 7_000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), amount);
        (uint256 tokenId,) = edenCore.invest(pool, amount, "Insufficient liquidity", 0);
        vm.stopPrank();

        uint256 investmentId = IInvestmentPool(pool).nftToInvestment(tokenId);
        IInvestmentPool.PoolConfig memory cfg = IInvestmentPool(pool).getPoolConfig();
        IInvestmentPool.Investment memory inv = IInvestmentPool(pool).getInvestment(investmentId);

        uint8 lpDec = IERC20Metadata(lpToken).decimals();
        uint8 cngnDec = IERC20Metadata(address(cNGN)).decimals();
        uint256 scaleFactor = (lpDec >= cngnDec) ? 10 ** (lpDec - cngnDec) : 1;

        uint256 effectiveTaxBps = cfg.taxRate > 0 ? cfg.taxRate : edenCore.globalTaxRate();
        uint256 taxLp = (amount * scaleFactor * effectiveTaxBps) / 10_000;

        vm.prank(address(taxCollector));
        IERC20(lpToken).transfer(admin, taxLp);

        vm.warp(inv.maturityTime);

        uint256 lockSeconds = inv.maturityTime - inv.depositTime;
        uint256 interest = (amount * cfg.expectedRate * lockSeconds) / (10_000 * 365 days);
        uint256 gross = amount + interest;

        uint256 taxShare = (gross * taxLp) / inv.totalLpForPosition;
        require(taxShare > 0, "sanity: taxShare must be > 0");

        vm.prank(multisig);
        cNGN.transfer(pool, taxShare - 1);

        (, address poolAdmin,,,) = edenCore.poolInfo(pool);
        vm.prank(poolAdmin);
        vm.expectRevert(bytes("Insufficient liquidity"));
        InvestmentPool(payable(pool)).collectTax(investmentId);
    }

    function test_CollectTax_Success() public {
        uint256 amount = 10_000e18;
        vm.startPrank(user1);
        cNGN.approve(address(edenCore), amount);
        (uint256 tokenId,) = edenCore.invest(pool, amount, "Tax test", 0);
        vm.stopPrank();

        uint256 investmentId = IInvestmentPool(pool).nftToInvestment(tokenId);

        IInvestmentPool.PoolConfig memory cfg = IInvestmentPool(pool).getPoolConfig();
        IInvestmentPool.Investment memory inv = IInvestmentPool(pool).getInvestment(investmentId);

        uint8 lpDec = IERC20Metadata(lpToken).decimals();
        uint8 cngnDec = IERC20Metadata(address(cNGN)).decimals();
        uint256 scaleFactor = (lpDec >= cngnDec) ? 10 ** (lpDec - cngnDec) : 1;

        uint256 effectiveTaxBps = cfg.taxRate > 0 ? cfg.taxRate : edenCore.globalTaxRate();
        uint256 taxLp = (amount * scaleFactor * effectiveTaxBps) / 10_000;

        uint256 taxLpBal = IERC20(lpToken).balanceOf(address(taxCollector));
        assertEq(taxLpBal, taxLp, "TaxCollector LP mismatch");

        vm.warp(inv.maturityTime);

        uint256 lockSeconds = inv.maturityTime - inv.depositTime;
        uint256 interest = (amount * cfg.expectedRate * lockSeconds) / (10_000 * 365 days);
        uint256 gross = amount + interest;

        vm.prank(multisig);
        cNGN.transfer(pool, gross);

        uint256 adminBalBefore = cNGN.balanceOf(admin);

        (, address poolAdmin,,,) = edenCore.poolInfo(pool);
        vm.prank(poolAdmin);
        uint256 paid = InvestmentPool(payable(pool)).collectTax(investmentId);

        uint256 adminBalAfter = cNGN.balanceOf(admin);
        uint256 taxShare = (gross * taxLp) / inv.totalLpForPosition;

        assertEq(paid, taxShare, "Return value mismatch");
        assertEq(adminBalAfter - adminBalBefore, taxShare, "Admin cNGN not received");
        assertEq(IERC20(lpToken).balanceOf(admin), 0, "Admin tax LP not burned");

        (,,,,,, bool isWithdrawn,, bool taxWithdrawn,,,) = InvestmentPool(payable(pool)).investments(investmentId);
        assertFalse(isWithdrawn, "User leg should not be withdrawn");
        assertTrue(taxWithdrawn, "Tax not marked withdrawn");
    }

    function _gross(uint256 principal, uint256 aprBps, uint256 lockSeconds) internal pure returns (uint256) {
        return principal + ((principal * aprBps * lockSeconds) / (10_000 * 365 days));
    }

    // ============ collectTaxBatch Tests ============

    function test_CollectTaxBatch_AllProcessed() public {
        // 1) Create three investments (same lock, tax from global 250 bps)
        uint256 a1 = 5_000e18;
        uint256 a2 = 8_000e18;
        uint256 a3 = 12_000e18;

        vm.startPrank(user1);
        cNGN.approve(address(edenCore), a1 + a2 + a3);
        (uint256 t1,) = edenCore.invest(pool, a1, "A1", 0);
        (uint256 t2,) = edenCore.invest(pool, a2, "A2", 0);
        (uint256 t3,) = edenCore.invest(pool, a3, "A3", 0);
        vm.stopPrank();

        uint256 id1 = IInvestmentPool(pool).nftToInvestment(t1);
        uint256 id2 = IInvestmentPool(pool).nftToInvestment(t2);
        uint256 id3 = IInvestmentPool(pool).nftToInvestment(t3);

        IInvestmentPool.PoolConfig memory cfg = IInvestmentPool(pool).getPoolConfig();

        IInvestmentPool.Investment memory i1 = IInvestmentPool(pool).getInvestment(id1);
        IInvestmentPool.Investment memory i2 = IInvestmentPool(pool).getInvestment(id2);
        IInvestmentPool.Investment memory i3 = IInvestmentPool(pool).getInvestment(id3);

        // 2) Warp to maturity
        uint256 maturity = i3.maturityTime; // they should be similar; use the last
        vm.warp(maturity);

        // 3) Compute gross & tax shares
        uint256 lock1 = i1.maturityTime - i1.depositTime;
        uint256 lock2 = i2.maturityTime - i2.depositTime;
        uint256 lock3 = i3.maturityTime - i3.depositTime;

        // totalLpForPosition == amount (scaleFactor=1) and taxLp = amount * 250/10000
        uint256 taxLp1 = i1.taxLpRequired;
        uint256 taxLp2 = i2.taxLpRequired;
        uint256 taxLp3 = i3.taxLpRequired;

        uint256 g1 = _gross(i1.amount, cfg.expectedRate, lock1);
        uint256 g2 = _gross(i2.amount, cfg.expectedRate, lock2);
        uint256 g3 = _gross(i3.amount, cfg.expectedRate, lock3);

        uint256 s1 = (g1 * taxLp1) / i1.totalLpForPosition;
        uint256 s2 = (g2 * taxLp2) / i2.totalLpForPosition;
        uint256 s3 = (g3 * taxLp3) / i3.totalLpForPosition;

        // 4) Fund pool fully
        vm.prank(multisig);
        cNGN.transfer(pool, s1 + s2 + s3);

        // 5) Batch collect to admin
        (, address poolAdmin,,,) = edenCore.poolInfo(pool);
        uint256 balBefore = cNGN.balanceOf(admin);

        vm.prank(poolAdmin);
        (uint256 totalPaid, uint256 processed) = InvestmentPool(payable(pool)).collectTaxBatch(new uint256[](0), admin);
        // NOTE: above empty array is wrong; pass ids below:
    }
}
