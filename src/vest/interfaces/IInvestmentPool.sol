// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IInvestmentPool {
    struct InitParams {
        string name;
        address lpToken;
        address cNGN;
        address poolMultisig;
        address nftManager;
        address edenCore;
        address admin;
        address[] multisigSigners;
        uint256 lockDuration;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 utilizationCap;
        uint256 expectedRate;
        uint256 taxRate;
    }

    struct PoolConfig {
        string name;
        uint256 lockDuration;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 utilizationCap;
        uint256 expectedRate;
        uint256 taxRate;
        bool acceptingDeposits;
    }

    struct Investment {
        address investor;
        uint256 amount;
        string title;
        uint256 depositTime;
        uint256 maturityTime;
        uint256 expectedReturn;
        bool isWithdrawn;
        uint256 userLpRequired;
        bool taxWithdrawn;
        uint256 taxLpRequired;
        uint256 actualReturn;
        uint256 totalLpForPosition;
    }

    event InvestmentCreated(
        uint256 indexed investmentId,
        address indexed investor,
        uint256 amount,
        uint256 lpTokens,
        uint256 indexed tokenId,
        uint256 expectedReturn,
        uint256 maturityTime,
        string title
    );
    event DepositsToggled(bool accepting, address indexed admin);

    event InvestmentWithdrawn(uint256 indexed investmentId, address indexed investor, uint256 amount);
    event InvestmentMatured(uint256 indexed investmentId, uint256 actualReturn);
    event PoolConfigUpdated(PoolConfig config);
    event PoolMultisigUpdated(address newMultisig);

    function invest(address investor, uint256 amount, string memory title)
        external
        returns (uint256 tokenId, uint256 userLPTokens, uint256 taxAmount);
    function withdraw(address investor, uint256 tokenId, uint256 lpAmount) external returns (uint256 withdrawAmount);
    function lpToken() external view returns (address);
    function taxRate() external view returns (uint256);
    function getPoolStats()
        external
        view
        returns (uint256 deposited, uint256 withdrawn, uint256 available, uint256 utilization);
    function pause() external;
    function unpause() external;
    function updatePoolConfig(PoolConfig memory config) external;
    function getPoolConfig() external view returns (PoolConfig memory);
    function nftToInvestment(uint256 tokenId) external view returns (uint256);
    function getInvestment(uint256 investmentId) external view returns (Investment memory);
}
