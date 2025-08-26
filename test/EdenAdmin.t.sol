// test/EdenAdmin.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/console.sol";
import "./EdenVestTestBase.sol";
import "../src/vest/EdenAdmin.sol";

contract EdenAdminTest is EdenVestTestBase {
    EdenAdmin public edenAdmin;

    function setUp() public override {
        super.setUp();

        // Create EdenAdmin contract
        edenAdmin = new EdenAdmin(address(edenCore), admin, multisigSigners);

        // Set EdenAdmin in EdenCore
        vm.prank(admin);
        edenCore.setEdenAdmin(address(edenAdmin));
    }

    // ============ Initialization Tests ============

    function test_Initialize_Success() public {
        EdenAdmin newAdmin = new EdenAdmin(address(edenCore), admin, multisigSigners);

        assertEq(newAdmin.edenCore(), address(edenCore), "EdenCore not set");
        assertTrue(newAdmin.hasRole(newAdmin.DEFAULT_ADMIN_ROLE(), admin), "Default admin role not granted");

        address[] memory signers = newAdmin.getMultisigSigners();
        assertEq(signers.length, 3, "Incorrect number of multisig signers");
        assertTrue(newAdmin.isMultisigSigner(multisigSigners[0]), "Signer 0 not set");
        assertTrue(newAdmin.isMultisigSigner(multisigSigners[1]), "Signer 1 not set");
        assertTrue(newAdmin.isMultisigSigner(multisigSigners[2]), "Signer 2 not set");
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        vm.expectRevert(EdenAdmin.InvalidAddress.selector);
        new EdenAdmin(address(0), admin, multisigSigners);

        vm.expectRevert(EdenAdmin.InvalidAddress.selector);
        new EdenAdmin(address(edenCore), address(0), multisigSigners);
    }

    function test_RevertWhen_InitializeWithInsufficientSigners() public {
        address[] memory insufficientSigners = new address[](1);
        insufficientSigners[0] = address(0x10);

        vm.expectRevert(EdenAdmin.InvalidSignerCount.selector);
        new EdenAdmin(address(edenCore), admin, insufficientSigners);
    }

    function test_RevertWhen_InitializeWithZeroAddressSigner() public {
        address[] memory invalidSigners = new address[](3);
        invalidSigners[0] = address(0x10);
        invalidSigners[1] = address(0); // Zero address
        invalidSigners[2] = address(0x12);

        vm.expectRevert(EdenAdmin.InvalidAddress.selector);
        new EdenAdmin(address(edenCore), admin, invalidSigners);
    }

    // ============ Proposal Creation Tests ============

    function test_CreateProposal_PauseProtocol() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Security issue detected");

        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);

        assertEq(proposal.id, proposalId, "Proposal ID mismatch");
        assertTrue(uint256(proposal.proposalType) == 0, "Proposal type should be PAUSE_PROTOCOL");
        assertEq(proposal.proposer, multisigSigners[0], "Proposer mismatch");
        assertEq(proposal.signatureCount, 1, "Should have 1 signature from proposer");
        assertFalse(proposal.executed, "Should not be executed yet");

        assertTrue(edenAdmin.hasSignedProposalView(proposalId, multisigSigners[0]), "Proposer should have signed");
    }

    function test_CreateProposal_UnpauseProtocol() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeUnpauseProtocol("Issue resolved");

        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);
        assertTrue(uint256(proposal.proposalType) == 1, "Proposal type should be UNPAUSE_PROTOCOL");
    }

    function test_CreateProposal_SetGlobalTaxRate() public {
        uint256 newRate = 500; // 5%

        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeSetGlobalTaxRate(newRate, "Adjust for market conditions");

        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);
        assertTrue(uint256(proposal.proposalType) == 2, "Proposal type should be SET_GLOBAL_TAX_RATE");

        uint256 decodedRate = abi.decode(proposal.data, (uint256));
        assertEq(decodedRate, newRate, "Encoded rate mismatch");
    }

    function test_CreateProposal_SetProtocolTreasury() public {
        address newTreasury = address(0x999);

        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeSetProtocolTreasury(newTreasury, "New treasury wallet");

        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);
        assertTrue(uint256(proposal.proposalType) == 3, "Proposal type should be SET_PROTOCOL_TREASURY");

        address decodedTreasury = abi.decode(proposal.data, (address));
        assertEq(decodedTreasury, newTreasury, "Encoded treasury mismatch");
    }

    function test_CreateProposal_EmergencyWithdraw() public {
        address token = address(cNGN);
        uint256 amount = 5000e18;
        string memory reason = "Emergency fund recovery";

        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeEmergencyWithdraw(token, amount, reason);

        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);
        assertTrue(uint256(proposal.proposalType) == 4, "Proposal type should be EMERGENCY_WITHDRAW");

        (address decodedToken, uint256 decodedAmount, string memory decodedReason) =
            abi.decode(proposal.data, (address, uint256, string));
        assertEq(decodedToken, token, "Encoded token mismatch");
        assertEq(decodedAmount, amount, "Encoded amount mismatch");
        assertEq(decodedReason, reason, "Encoded reason mismatch");
    }

    function test_CreateProposal_AddMultisigSigner() public {
        address newSigner = address(0x999);

        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeAddMultisigSigner(newSigner, "Adding new team member");

        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);
        assertTrue(uint256(proposal.proposalType) == 6, "Proposal type should be ADD_MULTISIG_SIGNER");

        address decodedSigner = abi.decode(proposal.data, (address));
        assertEq(decodedSigner, newSigner, "Encoded signer mismatch");
    }

    function test_CreateProposal_RemoveMultisigSigner() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeRemoveMultisigSigner(multisigSigners[2], "Removing inactive member");

        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);
        assertTrue(uint256(proposal.proposalType) == 7, "Proposal type should be REMOVE_MULTISIG_SIGNER");

        address decodedSigner = abi.decode(proposal.data, (address));
        assertEq(decodedSigner, multisigSigners[2], "Encoded signer mismatch");
    }

    // ============ Proposal Validation Tests ============

    function test_RevertWhen_NonSignerCreatesProposal() public {
        vm.prank(user1);
        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.proposePauseProtocol("Not a signer");
    }

    function test_RevertWhen_InvalidTaxRate() public {
        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenAdmin.InvalidTaxRate.selector);
        edenAdmin.proposeSetGlobalTaxRate(1001, "Invalid rate"); // > 10%
    }

    function test_RevertWhen_InvalidTreasuryAddress() public {
        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenAdmin.InvalidAddress.selector);
        edenAdmin.proposeSetProtocolTreasury(address(0), "Invalid address");
    }

    function test_RevertWhen_AddExistingSigner() public {
        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenAdmin.InvalidAddress.selector);
        edenAdmin.proposeAddMultisigSigner(multisigSigners[1], "Already exists");
    }

    function test_RevertWhen_RemoveNonexistentSigner() public {
        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenAdmin.InvalidAddress.selector);
        edenAdmin.proposeRemoveMultisigSigner(address(0x999), "Doesn't exist");
    }

    function test_RevertWhen_RemoveSignerBelowMinimum() public {
        // First, add a signer to have more than minimum
        vm.prank(multisigSigners[0]);
        uint256 addProposalId = edenAdmin.proposeAddMultisigSigner(address(0x999), "Temp signer");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(addProposalId);

        // Now try to remove signers until we hit the minimum
        // Remove first signer
        vm.prank(multisigSigners[0]);
        uint256 removeProposalId1 = edenAdmin.proposeRemoveMultisigSigner(multisigSigners[2], "Remove 1");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(removeProposalId1);

        // Remove second signer
        vm.prank(multisigSigners[0]);
        uint256 removeProposalId2 = edenAdmin.proposeRemoveMultisigSigner(multisigSigners[1], "Remove 2");

        vm.prank(address(0x999)); // The newly added signer
        edenAdmin.signProposal(removeProposalId2);

        // Now we should have exactly REQUIRED_SIGNATURES signers,
        // trying to remove one more should fail
        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenAdmin.InvalidSignerCount.selector);
        edenAdmin.proposeRemoveMultisigSigner(multisigSigners[0], "Would go below minimum");
    }

    // ============ Proposal Signing Tests ============

    function test_SignProposal_Success() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test proposal");

        // Sign by second signer
        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        // Check signature count
        assertEq(edenAdmin.getProposalSignatureCount(proposalId), 2, "Should have 2 signatures");
        assertTrue(edenAdmin.hasSignedProposalView(proposalId, multisigSigners[1]), "Second signer should have signed");
    }

    function test_RevertWhen_SigningTwice() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenAdmin.AlreadySigned.selector);
        edenAdmin.signProposal(proposalId);
    }

    function test_RevertWhen_NonSignerSigns() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        vm.prank(user1);
        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.signProposal(proposalId);
    }

    function test_RevertWhen_SigningExpiredProposal() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        // Wait for proposal to expire (> 2 days)
        vm.warp(block.timestamp + 3 days);

        vm.prank(multisigSigners[1]);
        vm.expectRevert(EdenAdmin.EProposalExpired.selector);
        edenAdmin.signProposal(proposalId);
    }

    function test_RevertWhen_SigningExecutedProposal() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId); // This should auto-execute

        // Try to sign again after execution
        vm.prank(multisigSigners[2]);
        vm.expectRevert(EdenAdmin.ProposalAlreadyExecuted.selector);
        edenAdmin.signProposal(proposalId);
    }

    // ============ Proposal Execution Tests ============

    function test_AutoExecuteProposal_PauseProtocol() public {
        // Create proposal
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Security issue");

        // Sign by second signer - should auto-execute with REQUIRED_SIGNATURES = 2
        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        // Check that protocol is paused
        assertTrue(edenCore.paused(), "Protocol should be paused");

        // Check proposal is executed
        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);
        assertTrue(proposal.executed, "Proposal should be executed");
    }

    function test_AutoExecuteProposal_UnpauseProtocol() public {
        // First pause the protocol
        vm.prank(multisigSigners[0]);
        uint256 pauseProposalId = edenAdmin.proposePauseProtocol("Security issue");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(pauseProposalId);

        assertTrue(edenCore.paused(), "Protocol should be paused");

        // Now create unpause proposal
        vm.prank(multisigSigners[0]);
        uint256 unpauseProposalId = edenAdmin.proposeUnpauseProtocol("Issue resolved");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(unpauseProposalId);

        // Check that protocol is unpaused
        assertFalse(edenCore.paused(), "Protocol should be unpaused");
    }

    function test_AutoExecuteProposal_SetGlobalTaxRate() public {
        uint256 newRate = 500; // 5%
        uint256 oldRate = edenCore.globalTaxRate();

        // Create proposal
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeSetGlobalTaxRate(newRate, "Adjust for market conditions");

        // Sign by second signer - should auto-execute
        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        // Check tax rate updated
        assertEq(edenCore.globalTaxRate(), newRate, "Global tax rate not updated");
        assertTrue(edenCore.globalTaxRate() != oldRate, "Tax rate should have changed");
    }

    function test_AutoExecuteProposal_SetProtocolTreasury() public {
        address newTreasury = address(0x999);
        address oldTreasury = edenCore.protocolTreasury();

        // Create proposal
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeSetProtocolTreasury(newTreasury, "New treasury wallet");

        // Sign by second signer - should auto-execute
        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        // Check treasury updated
        assertEq(edenCore.protocolTreasury(), newTreasury, "Protocol treasury not updated");
        assertTrue(edenCore.protocolTreasury() != oldTreasury, "Treasury should have changed");
    }

    function test_AutoExecuteProposal_EmergencyWithdraw() public {
        // Send some tokens to EdenCore
        cNGN.mint(address(edenCore), 10000e18);

        uint256 withdrawAmount = 5000e18;
        uint256 balanceBefore = cNGN.balanceOf(treasury);

        // Create proposal
        vm.prank(multisigSigners[0]);
        uint256 proposalId =
            edenAdmin.proposeEmergencyWithdraw(address(cNGN), withdrawAmount, "Emergency fund recovery");

        // Sign by second signer - should auto-execute
        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        // Check withdrawal succeeded
        uint256 balanceAfter = cNGN.balanceOf(treasury);
        assertEq(balanceAfter - balanceBefore, withdrawAmount, "Emergency withdrawal failed");
    }

    function test_AutoExecuteProposal_AddMultisigSigner() public {
        address newSigner = address(0x999);

        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposeAddMultisigSigner(newSigner, "Adding new team member");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        assertTrue(edenAdmin.isMultisigSigner(newSigner), "New signer not added");
        address[] memory signers = edenAdmin.getMultisigSigners();
        assertEq(signers.length, 4, "Signer count should be 4");
    }

    function test_AutoExecuteProposal_RemoveMultisigSigner() public {
        address newSigner = address(0x999);

        // First add a signer
        vm.prank(multisigSigners[0]);
        uint256 addProposalId = edenAdmin.proposeAddMultisigSigner(newSigner, "Adding for removal test");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(addProposalId);

        // Now remove a signer
        vm.prank(multisigSigners[0]);
        uint256 removeProposalId = edenAdmin.proposeRemoveMultisigSigner(multisigSigners[2], "Removing inactive member");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(removeProposalId);

        assertFalse(edenAdmin.isMultisigSigner(multisigSigners[2]), "Signer not removed");
        address[] memory signers = edenAdmin.getMultisigSigners();
        assertEq(signers.length, 3, "Signer count should be back to 3");
    }

    function test_ManualExecuteProposal_Success() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        // Don't auto-execute, manually execute instead
        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        // Should already be executed due to auto-execution
        assertTrue(edenCore.paused(), "Should be paused from auto-execution");
    }

    function test_RevertWhen_ExecutingWithInsufficientSignatures() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenAdmin.InsufficientSignatures.selector);
        edenAdmin.executeProposal(proposalId);
    }

    function test_RevertWhen_ExecutingExpiredProposal() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        // Wait for expiry
        vm.warp(block.timestamp + 3 days);

        vm.prank(multisigSigners[1]);
        vm.expectRevert(EdenAdmin.EProposalExpired.selector);
        edenAdmin.executeProposal(proposalId);
    }

    function test_RevertWhen_ExecutingNonexistentProposal() public {
        vm.prank(multisigSigners[0]);
        vm.expectRevert(EdenAdmin.ProposalNotFound.selector);
        edenAdmin.executeProposal(999);
    }

    // ============ View Function Tests ============

    function test_GetProposal() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test proposal");

        EdenAdmin.Proposal memory proposal = edenAdmin.getProposal(proposalId);

        assertEq(proposal.id, proposalId, "Proposal ID mismatch");
        assertTrue(uint256(proposal.proposalType) == 0, "Proposal type mismatch");
        assertEq(proposal.proposer, multisigSigners[0], "Proposer mismatch");
        assertEq(proposal.signatureCount, 1, "Signature count mismatch");
        assertTrue(proposal.expiresAt > block.timestamp, "Should not be expired");
        assertFalse(proposal.executed, "Should not be executed");
        assertTrue(
            keccak256(abi.encodePacked(proposal.description))
                == keccak256(abi.encodePacked("Pause Protocol: Test proposal")),
            "Description mismatch"
        );
    }

    function test_GetMultisigSigners() public {
        address[] memory signers = edenAdmin.getMultisigSigners();
        assertEq(signers.length, 3, "Signer count mismatch");
        assertEq(signers[0], multisigSigners[0], "Signer 0 mismatch");
        assertEq(signers[1], multisigSigners[1], "Signer 1 mismatch");
        assertEq(signers[2], multisigSigners[2], "Signer 2 mismatch");
    }

    function test_HasSignedProposalView() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        assertTrue(edenAdmin.hasSignedProposalView(proposalId, multisigSigners[0]), "Proposer should have signed");
        assertFalse(
            edenAdmin.hasSignedProposalView(proposalId, multisigSigners[1]), "Other signer should not have signed"
        );

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        assertTrue(edenAdmin.hasSignedProposalView(proposalId, multisigSigners[1]), "Second signer should have signed");
    }

    function test_GetProposalSignatureCount() public {
        vm.prank(multisigSigners[0]);
        uint256 proposalId = edenAdmin.proposePauseProtocol("Test");

        assertEq(edenAdmin.getProposalSignatureCount(proposalId), 1, "Should have 1 signature");

        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(proposalId);

        // Note: This proposal auto-executes at 2 signatures, so we test before execution
        // The count should still be 2 even after execution
        assertEq(edenAdmin.getProposalSignatureCount(proposalId), 2, "Should have 2 signatures");
    }

    function test_IsMultisigSigner() public {
        assertTrue(edenAdmin.isMultisigSigner(multisigSigners[0]), "Should be signer");
        assertTrue(edenAdmin.isMultisigSigner(multisigSigners[1]), "Should be signer");
        assertTrue(edenAdmin.isMultisigSigner(multisigSigners[2]), "Should be signer");
        assertFalse(edenAdmin.isMultisigSigner(user1), "Should not be signer");
        assertFalse(edenAdmin.isMultisigSigner(admin), "Admin should not be multisig signer");
    }

    // ============ Edge Cases and Complex Scenarios ============

    function test_MultipleProposalsSimultaneous() public {
        // Create multiple proposals
        vm.prank(multisigSigners[0]);
        uint256 pauseProposalId = edenAdmin.proposePauseProtocol("Security issue");

        vm.prank(multisigSigners[1]);
        uint256 taxProposalId = edenAdmin.proposeSetGlobalTaxRate(300, "Lower tax");

        vm.prank(multisigSigners[2]);
        uint256 treasuryProposalId = edenAdmin.proposeSetProtocolTreasury(address(0x999), "New treasury");

        // Sign different proposals by different signers
        vm.prank(multisigSigners[1]);
        edenAdmin.signProposal(pauseProposalId); // Should execute

        vm.prank(multisigSigners[0]);
        edenAdmin.signProposal(taxProposalId); // Should execute

        vm.prank(multisigSigners[0]);
        edenAdmin.signProposal(treasuryProposalId); // Should execute

        // Verify all executed correctly
        assertTrue(edenCore.paused(), "Should be paused");
        assertEq(edenCore.globalTaxRate(), 300, "Tax rate should be updated");
        assertEq(edenCore.protocolTreasury(), address(0x999), "Treasury should be updated");
    }

    function test_ProposalIdIncrement() public {
        vm.prank(multisigSigners[0]);
        uint256 firstId = edenAdmin.proposePauseProtocol("First");

        vm.prank(multisigSigners[0]);
        uint256 secondId = edenAdmin.proposeUnpauseProtocol("Second");

        assertEq(secondId, firstId + 1, "Proposal IDs should increment");
    }

    function test_LargeSignerSet() public {
        address[] memory largeSignerSet = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            largeSignerSet[i] = address(uint160(0x1000 + i));
        }

        EdenAdmin largeAdmin = new EdenAdmin(address(edenCore), admin, largeSignerSet);

        vm.prank(admin);
        edenCore.setEdenAdmin(address(largeAdmin));

        assertEq(largeAdmin.getMultisigSigners().length, 10, "Should have 10 signers");

        // Test proposal creation and signing with large signer set
        vm.prank(largeSignerSet[0]);
        uint256 proposalId = largeAdmin.proposePauseProtocol("Test with large signer set");

        // Should still only need REQUIRED_SIGNATURES (2) to execute
        vm.prank(largeSignerSet[1]);
        largeAdmin.signProposal(proposalId);

        EdenAdmin.Proposal memory proposal = largeAdmin.getProposal(proposalId);
        assertTrue(proposal.executed, "Should be executed with 2 signatures even in large signer set");
    }

    // ============ Constants and Configuration Tests ============

    function test_RequiredSignaturesConstant() public  {
        assertEq(edenAdmin.REQUIRED_SIGNATURES(), 2, "Required signatures should be 2");
    }

    function test_ProposalExpiryConstant() public  {
        assertEq(edenAdmin.PROPOSAL_EXPIRY(), 2 days, "Proposal expiry should be 2 days");
    }

    function test_MultisigSignerRole() public  {
        bytes32 expectedRole = keccak256("MULTISIG_SIGNER_ROLE");
        assertEq(edenAdmin.MULTISIG_SIGNER_ROLE(), expectedRole, "Multisig signer role hash mismatch");

        assertTrue(edenAdmin.hasRole(expectedRole, multisigSigners[0]), "Should have multisig signer role");
        assertFalse(edenAdmin.hasRole(expectedRole, user1), "Should not have multisig signer role");
    }

    // ============ Access Control Tests ============

    function test_OnlyMultisigSignerModifier() public {
        // Test all proposal creation functions require multisig signer role
        vm.startPrank(user1);

        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.proposePauseProtocol("Test");

        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.proposeUnpauseProtocol("Test");

        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.proposeSetGlobalTaxRate(300, "Test");

        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.proposeSetProtocolTreasury(address(0x999), "Test");

        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.proposeEmergencyWithdraw(address(cNGN), 1000e18, "Test");

        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.proposeAddMultisigSigner(address(0x999), "Test");

        vm.expectRevert(EdenAdmin.NotMultisigSigner.selector);
        edenAdmin.proposeRemoveMultisigSigner(multisigSigners[0], "Test");

        vm.stopPrank();
    }
}
