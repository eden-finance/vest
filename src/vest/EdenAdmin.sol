// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title EdenAdmin
 * @notice Administrative and multisig functions for Eden Finance protocol
 * @dev Handles governance, proposals, and critical protocol operations
 */
contract EdenAdmin is AccessControl {
    // ============ ROLES ============
    bytes32 public constant MULTISIG_SIGNER_ROLE = keccak256("MULTISIG_SIGNER_ROLE");

    // ============ MULTISIG CONSTANTS ============
    uint256 public constant REQUIRED_SIGNATURES = 3; // Require 3 out of N signatures
    uint256 public constant PROPOSAL_EXPIRY = 3 days;

    // ============ STATE VARIABLES ============
    address public edenCore;

    // ============ MULTISIG STATE ============
    uint256 public nextProposalId = 1;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasSignedProposal;
    address[] public multisigSigners;
    mapping(address => bool) public isMultisigSigner;

    // ============ STRUCTS ============
    struct Proposal {
        uint256 id;
        ProposalType proposalType;
        address proposer;
        uint256 createdAt;
        uint256 expiresAt;
        bool executed;
        uint256 signatureCount;
        bytes data;
        string description;
    }

    enum ProposalType {
        PAUSE_PROTOCOL,
        UNPAUSE_PROTOCOL,
        SET_GLOBAL_TAX_RATE,
        SET_PROTOCOL_TREASURY,
        EMERGENCY_WITHDRAW,
        UPGRADE_CONTRACT,
        ADD_MULTISIG_SIGNER,
        REMOVE_MULTISIG_SIGNER
    }

    // ============ EVENTS ============
    event ProposalCreated(
        uint256 indexed proposalId, ProposalType proposalType, address indexed proposer, string description
    );
    event ProposalSigned(uint256 indexed proposalId, address indexed signer, uint256 signatureCount);
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    event ProposalExpired(uint256 indexed proposalId);
    event MultisigSignerAdded(address indexed signer);
    event MultisigSignerRemoved(address indexed signer);

    // ============ ERRORS ============
    error ProposalNotFound();
    error ProposalAlreadyExecuted();
    error AlreadySigned();
    error NotMultisigSigner();
    error InsufficientSignatures();
    error InvalidProposalType();
    error InvalidSignerCount();
    error EProposalExpired();
    error InvalidAddress();
    error InvalidTaxRate();

    // ============ MODIFIERS ============
    modifier onlyMultisigSigner() {
        if (!isMultisigSigner[msg.sender]) revert NotMultisigSigner();
        _;
    }

    modifier validProposal(uint256 proposalId) {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.id == 0) revert ProposalNotFound();
        if (block.timestamp > proposal.expiresAt) revert EProposalExpired();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        _;
    }

    constructor(address _edenCore, address _admin, address[] memory _multisigSigners) {
        if (_edenCore == address(0)) revert InvalidAddress();
        if (_admin == address(0)) revert InvalidAddress();
        if (_multisigSigners.length < REQUIRED_SIGNATURES) revert InvalidSignerCount();

        edenCore = _edenCore;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        for (uint256 i = 0; i < _multisigSigners.length; i++) {
            if (_multisigSigners[i] == address(0)) revert InvalidAddress();
            multisigSigners.push(_multisigSigners[i]);
            isMultisigSigner[_multisigSigners[i]] = true;
            _grantRole(MULTISIG_SIGNER_ROLE, _multisigSigners[i]);
        }
    }

    /**
     * @notice Create a new proposal for critical operations
     * @param proposalType Type of proposal
     * @param data Encoded function call data
     * @param description Human readable description
     */
    function createProposal(ProposalType proposalType, bytes memory data, string memory description)
        internal
        onlyMultisigSigner
        returns (uint256 proposalId)
    {
        proposalId = nextProposalId++;

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposalType: proposalType,
            proposer: msg.sender,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + PROPOSAL_EXPIRY,
            executed: false,
            signatureCount: 1,
            data: data,
            description: description
        });

        hasSignedProposal[proposalId][msg.sender] = true;

        emit ProposalCreated(proposalId, proposalType, msg.sender, description);
        emit ProposalSigned(proposalId, msg.sender, 1);
    }

    /**
     * @notice Sign a proposal
     * @param proposalId ID of the proposal to sign
     */
    function signProposal(uint256 proposalId) external onlyMultisigSigner validProposal(proposalId) {
        if (hasSignedProposal[proposalId][msg.sender]) revert AlreadySigned();

        hasSignedProposal[proposalId][msg.sender] = true;
        proposals[proposalId].signatureCount++;

        emit ProposalSigned(proposalId, msg.sender, proposals[proposalId].signatureCount);

        // Auto-execute if we have enough signatures
        if (proposals[proposalId].signatureCount >= REQUIRED_SIGNATURES) {
            _executeProposal(proposalId);
        }
    }

    /**
     * @notice Execute a proposal with sufficient signatures
     * @param proposalId ID of the proposal to execute
     */
    function executeProposal(uint256 proposalId) external onlyMultisigSigner validProposal(proposalId) {
        if (proposals[proposalId].signatureCount < REQUIRED_SIGNATURES) revert InsufficientSignatures();
        _executeProposal(proposalId);
    }

    /**
     * @dev Internal function to execute proposals
     */
    function _executeProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        proposal.executed = true;

        if (proposal.proposalType == ProposalType.PAUSE_PROTOCOL) {
            (bool success,) = edenCore.call(abi.encodeWithSignature("pauseProtocol()"));
            require(success, "Pause failed");
        } else if (proposal.proposalType == ProposalType.UNPAUSE_PROTOCOL) {
            (bool success,) = edenCore.call(abi.encodeWithSignature("unpauseProtocol()"));
            require(success, "Unpause failed");
        } else if (proposal.proposalType == ProposalType.SET_GLOBAL_TAX_RATE) {
            uint256 newRate = abi.decode(proposal.data, (uint256));
            (bool success,) = edenCore.call(abi.encodeWithSignature("setGlobalTaxRateInternal(uint256)", newRate));
            require(success, "Set tax rate failed");
        } else if (proposal.proposalType == ProposalType.SET_PROTOCOL_TREASURY) {
            address newTreasury = abi.decode(proposal.data, (address));
            (bool success,) =
                edenCore.call(abi.encodeWithSignature("setProtocolTreasuryInternal(address)", newTreasury));
            require(success, "Set treasury failed");
        } else if (proposal.proposalType == ProposalType.EMERGENCY_WITHDRAW) {
            (address token, uint256 amount, string memory reason) =
                abi.decode(proposal.data, (address, uint256, string));
            (bool success,) = edenCore.call(
                abi.encodeWithSignature("emergencyWithdrawInternal(address,uint256,string)", token, amount, reason)
            );
            require(success, "Emergency withdraw failed");
        } else if (proposal.proposalType == ProposalType.ADD_MULTISIG_SIGNER) {
            address newSigner = abi.decode(proposal.data, (address));
            _addMultisigSigner(newSigner);
        } else if (proposal.proposalType == ProposalType.REMOVE_MULTISIG_SIGNER) {
            address signerToRemove = abi.decode(proposal.data, (address));
            _removeMultisigSigner(signerToRemove);
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    /**
     * @notice Create proposal to pause protocol
     */
    function proposePauseProtocol(string memory reason) external onlyMultisigSigner returns (uint256) {
        return createProposal(ProposalType.PAUSE_PROTOCOL, "", string.concat("Pause Protocol: ", reason));
    }

    /**
     * @notice Create proposal to unpause protocol
     */
    function proposeUnpauseProtocol(string memory reason) external onlyMultisigSigner returns (uint256) {
        return createProposal(ProposalType.UNPAUSE_PROTOCOL, "", string.concat("Unpause Protocol: ", reason));
    }

    /**
     * @notice Create proposal to update global tax rate
     */
    function proposeSetGlobalTaxRate(uint256 newRate, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        if (newRate > 1000) revert InvalidTaxRate(); // Max 10%

        return createProposal(
            ProposalType.SET_GLOBAL_TAX_RATE,
            abi.encode(newRate),
            string.concat("Set Global Tax Rate to ", _uint2str(newRate), " basis points: ", reason)
        );
    }

    /**
     * @notice Create proposal to update protocol treasury
     */
    function proposeSetProtocolTreasury(address newTreasury, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        if (newTreasury == address(0)) revert InvalidAddress();

        return createProposal(
            ProposalType.SET_PROTOCOL_TREASURY,
            abi.encode(newTreasury),
            string.concat("Set Protocol Treasury: ", reason)
        );
    }

    /**
     * @notice Create proposal for emergency withdrawal
     */
    function proposeEmergencyWithdraw(address token, uint256 amount, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        return createProposal(
            ProposalType.EMERGENCY_WITHDRAW,
            abi.encode(token, amount, reason),
            string.concat("Emergency Withdraw: ", reason)
        );
    }

    /**
     * @notice Create proposal to add multisig signer
     */
    function proposeAddMultisigSigner(address newSigner, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        if (newSigner == address(0)) revert InvalidAddress();
        if (isMultisigSigner[newSigner]) revert InvalidAddress(); // Already a signer

        return createProposal(
            ProposalType.ADD_MULTISIG_SIGNER, abi.encode(newSigner), string.concat("Add Multisig Signer: ", reason)
        );
    }

    /**
     * @notice Create proposal to remove multisig signer
     */
    function proposeRemoveMultisigSigner(address signerToRemove, string memory reason)
        external
        onlyMultisigSigner
        returns (uint256)
    {
        if (!isMultisigSigner[signerToRemove]) revert InvalidAddress();
        if (multisigSigners.length <= REQUIRED_SIGNATURES) revert InvalidSignerCount(); // Can't go below minimum

        return createProposal(
            ProposalType.REMOVE_MULTISIG_SIGNER,
            abi.encode(signerToRemove),
            string.concat("Remove Multisig Signer: ", reason)
        );
    }

    // ============ INTERNAL MULTISIG FUNCTIONS ============

    function _addMultisigSigner(address newSigner) internal {
        multisigSigners.push(newSigner);
        isMultisigSigner[newSigner] = true;
        _grantRole(MULTISIG_SIGNER_ROLE, newSigner);
        emit MultisigSignerAdded(newSigner);
    }

    function _removeMultisigSigner(address signerToRemove) internal {
        isMultisigSigner[signerToRemove] = false;
        _revokeRole(MULTISIG_SIGNER_ROLE, signerToRemove);

        // Remove from array
        for (uint256 i = 0; i < multisigSigners.length; i++) {
            if (multisigSigners[i] == signerToRemove) {
                multisigSigners[i] = multisigSigners[multisigSigners.length - 1];
                multisigSigners.pop();
                break;
            }
        }
        emit MultisigSignerRemoved(signerToRemove);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get proposal details
     */
    function getProposal(uint256 proposalId) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /**
     * @notice Get all multisig signers
     */
    function getMultisigSigners() external view returns (address[] memory) {
        return multisigSigners;
    }

    /**
     * @notice Check if address has signed a proposal
     */
    function hasSignedProposalView(uint256 proposalId, address signer) external view returns (bool) {
        return hasSignedProposal[proposalId][signer];
    }

    /**
     * @notice Get signature count for a proposal
     */
    function getProposalSignatureCount(uint256 proposalId) external view returns (uint256) {
        return proposals[proposalId].signatureCount;
    }

    // ============ UTILITY FUNCTIONS ============

    function _uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) return "0";

        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }

        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }

        str = string(bstr);
    }
}
