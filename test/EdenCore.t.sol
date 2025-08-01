// test/EdenCore.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/console.sol";
import "./EdenVestTestBase.sol";
import "../src/vest/interfaces/IInvestmentPool.sol";
import "../src/vest/EdenAdmin.sol";


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

        vm.prank(admin);
        nftManager.authorizePool(pool, true);
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public {
        EdenVestCore newCore = new EdenVestCore();
        newCore.initialize(address(cNGN), treasury, admin, 250, multisigSigners);

        assertEq(newCore.cNGN(), address(cNGN), "cNGN not set");
        assertEq(newCore.protocolTreasury(), treasury, "Treasury not set");
        assertEq(newCore.globalTaxRate(), 250, "Tax rate not set");
        assertTrue(newCore.hasRole(newCore.ADMIN_ROLE(), admin), "Admin role not granted");

        address[] memory signers = newCore.getMultisigSigners();
        assertEq(signers.length, 3, "Incorrect number of multisig signers");
        assertTrue(newCore.isMultisigSigner(multisigSigners[0]), "Signer 0 not set");
        assertTrue(newCore.isMultisigSigner(multisigSigners[1]), "Signer 1 not set");
        assertTrue(newCore.isMultisigSigner(multisigSigners[2]), "Signer 2 not set");
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        EdenVestCore newCore = new EdenVestCore();

        vm.expectRevert(EdenVestCore.InvalidAddress.selector);
        newCore.initialize(address(0), treasury, admin, 250, multisigSigners);

        vm.expectRevert(EdenVestCore.InvalidAddress.selector);
        newCore.initialize(address(cNGN), address(0), admin, 250, multisigSigners);
    }

    function test_RevertWhen_InitializeWithHighTaxRate() public {
        EdenVestCore newCore = new EdenVestCore();

        vm.expectRevert(EdenVestCore.InvalidTaxRate.selector);
        newCore.initialize(address(cNGN), treasury, admin, 1001, multisigSigners); // > 10%
    }

    function test_RevertWhen_InitializeWithInsufficientSigners() public {
        EdenVestCore newCore = new EdenVestCore();
        address[] memory insufficientSigners = new address[](2);
        insufficientSigners[0] = address(0x10);
        insufficientSigners[1] = address(0x11);

        vm.expectRevert(EdenVestCore.InvalidSignerCount.selector);
        newCore.initialize(address(cNGN), treasury, admin, 250, insufficientSigners);
    }

    function test_AdminHasRole() public {
        EdenVestCore newCore = new EdenVestCore();
        newCore.initialize(address(cNGN), treasury, admin, 250, multisigSigners);

        assertTrue(newCore.hasRole(newCore.EMERGENCY_ROLE(), admin), "Emergency role not granted");
        assertTrue(newCore.hasRole(newCore.POOL_CREATOR_ROLE(), admin), "Pool creator role not granted");
    }

    // ============ Multisig Tests ============

    function test_CreateProposal_PauseProtocol() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposePauseProtocol("Security issue detected");

        (uint256 id, EdenAdmin.ProposalType proposalType, address proposer,,, bool executed, uint256 signatureCount,,) =
            edenCore.proposals(proposalId);

        assertEq(id, proposalId, "Proposal ID mismatch");
        assertTrue(uint256(proposalType) == 0, "Proposal type should be PAUSE_PROTOCOL");
        assertEq(proposer, multisigSigners[0], "Proposer mismatch");
        assertEq(signatureCount, 1, "Should have 1 signature from proposer");
        assertFalse(executed, "Should not be executed yet");

        assertTrue(edenCore.hasSignedProposalView(proposalId, multisigSigners[0]), "Proposer should have signed");
    }

    function test_SignAndExecuteProposal_PauseProtocol() public {
        // Create proposal
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposePauseProtocol("Security issue");

        // Sign by second signer
        vm.prank(multisigSigners[1]);
        edenCore.signProposal(proposalId);

        // Check signature count
        assertEq(edenCore.getProposalSignatureCount(proposalId), 2, "Should have 2 signatures");

        // Sign by third signer - should auto-execute
        vm.prank(multisigSigners[2]);
        edenCore.signProposal(proposalId);

        // Check that protocol is paused
        assertTrue(edenCore.paused(), "Protocol should be paused");

        // Check proposal is executed
        (,,,,, bool executed,,,) = edenCore.proposals(proposalId);
        assertTrue(executed, "Proposal should be executed");
    }

    function test_SetGlobalTaxRate_ViaMultisig() public {
        uint256 newRate = 500; // 5%

        // Create proposal
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposeSetGlobalTaxRate(newRate, "Adjust for market conditions");

        // Sign by other signers
        vm.prank(multisigSigners[1]);
        edenCore.signProposal(proposalId);

        vm.prank(multisigSigners[2]);
        edenCore.signProposal(proposalId);

        // Check tax rate updated
        assertEq(edenCore.globalTaxRate(), newRate, "Global tax rate not updated");
    }

    function test_EmergencyWithdraw_ViaMultisig() public {
        // Send some tokens to EdenCore
        cNGN.mint(address(edenCore), 10000e18);

        uint256 withdrawAmount = 5000e18;
        uint256 balanceBefore = cNGN.balanceOf(treasury);

        // Create proposal
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposeEmergencyWithdraw(address(cNGN), withdrawAmount, "Emergency fund recovery");

        // Sign by other signers
        vm.prank(multisigSigners[1]);
        edenCore.signProposal(proposalId);

        vm.prank(multisigSigners[2]);
        edenCore.signProposal(proposalId);

        // Check withdrawal succeeded
        uint256 balanceAfter = cNGN.balanceOf(treasury);
        assertEq(balanceAfter - balanceBefore, withdrawAmount, "Emergency withdrawal failed");
    }

    function test_RevertWhen_NonSignerCreatesProposal() public {
        vm.prank(user1);
        vm.expectRevert(EdenVestCore.NotMultisigSigner.selector);
        edenCore.proposePauseProtocol("Not a signer");
    }

    function test_RevertWhen_SigningTwice() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposePauseProtocol("Test");

        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenVestCore.AlreadySigned.selector);
        edenCore.signProposal(proposalId);
    }

    function test_RevertWhen_ExecutingWithInsufficientSignatures() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposePauseProtocol("Test");

        vm.prank(multisigSigners[1]);
        vm.expectRevert(EdenVestCore.InsufficientSignatures.selector);
        edenCore.executeProposal(proposalId);
    }

    function test_ProposalExpiry() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposePauseProtocol("Test");

        vm.warp(block.timestamp + 4 days);

        vm.prank(multisigSigners[1]);
        vm.expectRevert(EdenVestCore.EProposalExpired.selector);
        edenCore.signProposal(proposalId);
    }

    function test_AddMultisigSigner() public {
        address newSigner = address(0x999);

        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposeAddMultisigSigner(newSigner, "Adding new team member");

        vm.prank(multisigSigners[1]);
        edenCore.signProposal(proposalId);

        vm.prank(multisigSigners[2]);
        edenCore.signProposal(proposalId);

        assertTrue(edenCore.isMultisigSigner(newSigner), "New signer not added");
        address[] memory signers = edenCore.getMultisigSigners();
        assertEq(signers.length, 4, "Signer count should be 4");
    }

    function test_RemoveMultisigSigner() public {
        address newSigner = address(0x999);

        vm.prank(multisigSigners[0]);
        uint256 addProposalId = edenCore.proposeAddMultisigSigner(newSigner, "Adding for removal test");

        vm.prank(multisigSigners[1]);
        edenCore.signProposal(addProposalId);

        vm.prank(multisigSigners[2]);
        edenCore.signProposal(addProposalId);

        vm.prank(multisigSigners[0]);
        uint256 removeProposalId = edenCore.proposeRemoveMultisigSigner(multisigSigners[2], "Removing inactive member");

        vm.prank(multisigSigners[1]);
        edenCore.signProposal(removeProposalId);

        vm.prank(newSigner);
        edenCore.signProposal(removeProposalId);

        assertFalse(edenCore.isMultisigSigner(multisigSigners[2]), "Signer not removed");
        address[] memory signers = edenCore.getMultisigSigners();
        assertEq(signers.length, 3, "Signer count should be back to 3");
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

    function test_RevertWhen_InvestWhilePaused() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposePauseProtocol("Testing pause");

        vm.prank(multisigSigners[1]);
        edenCore.signProposal(proposalId);

        vm.prank(multisigSigners[2]);
        edenCore.signProposal(proposalId);

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

        vm.prank(multisig);
        cNGN.transfer(pool, investAmount + 1500e18);

        vm.warp(block.timestamp + 31 days);

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
        edenCore.invest(pool, investAmount, "Test Investment", 0);
        vm.stopPrank();

        uint256 expectedTax = investAmount * 250 / 10000; // 2.5%

        assertEq(taxCollector.tokenTaxBalance(lpToken), expectedTax, "Tax not collected correctly");
    }

    // ============ View Function Tests ============

    function test_GetAllPools() public view {
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

    function test_GetProposal() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenCore.proposePauseProtocol("Test proposal");

        EdenAdmin.Proposal memory proposal = edenCore.getProposal(proposalId);

        assertEq(proposal.id, proposalId, "Proposal ID mismatch");
        assertTrue(uint256(proposal.proposalType) == 0, "Proposal type mismatch");
        assertEq(proposal.proposer, multisigSigners[0], "Proposer mismatch");
        assertEq(proposal.signatureCount, 1, "Signature count mismatch");
        assertTrue(
            keccak256(abi.encodePacked(proposal.description))
                == keccak256(abi.encodePacked("Pause Protocol: Test proposal")),
            "Description mismatch"
        );
    }

    function test_GetMultisigSigners() public view {
        address[] memory signers = edenCore.getMultisigSigners();
        assertEq(signers.length, 3, "Signer count mismatch");
        assertEq(signers[0], multisigSigners[0], "Signer 0 mismatch");
        assertEq(signers[1], multisigSigners[1], "Signer 1 mismatch");
        assertEq(signers[2], multisigSigners[2], "Signer 2 mismatch");
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
}
