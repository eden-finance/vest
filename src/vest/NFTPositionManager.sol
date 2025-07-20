// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/INFTPositionManager.sol";
import "../EdenPoolNFT.sol";
import "../libs/EdenPoolNFTRenderer.sol";

/**
 * @title NFTPositionManager
 * @notice Manages investment position NFTs
 */
contract NFTPositionManager is ERC721, ERC721Enumerable, AccessControl, INFTPositionManager {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    EdenPoolNFT public renderer;
    uint256 public nextTokenId = 1;

    mapping(uint256 => Position) public positions;
    mapping(address => bool) public authorizedPools;

    modifier onlyAuthorizedPool() {
        require(authorizedPools[msg.sender], "Unauthorized pool");
        _;
    }

    constructor(address _renderer, address _admin) ERC721("Eden Finance Position", "ePOS") {
        renderer = EdenPoolNFT(_renderer);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
    }

    function mintPosition(address investor, address pool, uint256 investmentId, uint256 amount, uint256 maturityTime)
        external
        override
        onlyAuthorizedPool
        returns (uint256 tokenId)
    {
        tokenId = nextTokenId++;

        positions[tokenId] = Position({
            pool: pool,
            investmentId: investmentId,
            amount: amount,
            investor: investor,
            maturityTime: maturityTime
        });

        _mint(investor, tokenId);

        emit PositionMinted(tokenId, investor, pool, investmentId);
    }

    function burnPosition(uint256 tokenId) external override onlyAuthorizedPool {
        require(_ownerOf(tokenId) != address(0), "Position not exists");
        _burn(tokenId);
        delete positions[tokenId];

        emit PositionBurned(tokenId);
    }

    function authorizePool(address pool, bool authorized) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedPools[pool] = authorized;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        Position memory position = positions[tokenId];

        // Simplified rendering params for new architecture
        EdenPoolNFTRenderer.RenderParams memory params = EdenPoolNFTRenderer.RenderParams({
            tokenId: tokenId,
            investor: position.investor,
            amount: position.amount,
            depositTime: block.timestamp,
            maturityTime: position.maturityTime,
            expectedReturn: 0,
            actualReturn: 0,
            isMatured: block.timestamp >= position.maturityTime,
            isWithdrawn: false,
            fundsCollected: true,
            lockDuration: position.maturityTime - block.timestamp,
            expectedRate: 1500 // Default 15% for display
        });

        return renderer.renderNFT(params);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        address from = _ownerOf(tokenId);

        // Allow minting and burning but not transfers
        if (from != address(0) && to != address(0)) {
            revert("Positions are non-transferable");
        }

        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
