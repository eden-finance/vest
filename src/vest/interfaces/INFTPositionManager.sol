// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface INFTPositionManager {
    struct Position {
        address pool;
        uint256 investmentId;
        uint256 amount;
        address investor;
        uint256 maturityTime;
    }

    event PositionMinted(uint256 indexed tokenId, address indexed investor, address pool, uint256 investmentId);
    event PositionBurned(uint256 indexed tokenId);

    function mintPosition(address investor, address pool, uint256 investmentId, uint256 amount, uint256 maturityTime)
        external
        returns (uint256 tokenId);

    function burnPosition(uint256 tokenId) external;
}
