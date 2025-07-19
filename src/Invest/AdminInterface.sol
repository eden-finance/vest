// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IInvestmentPool.sol";
import "./EdenCore.sol";

/**
 * @title AdminInterface
 * @notice Administrative interface for Eden Finance protocol management
 */
contract AdminInterface is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    EdenCore public edenCore;

    struct PoolStats {
        address pool;
        string name;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 utilizationRate;
        uint256 activeInvestments;
        bool isActive;
    }

    struct ProtocolStats {
        uint256 totalValueLocked;
        uint256 totalPools;
        uint256 activePools;
        uint256 totalTaxCollected;
        uint256 globalTaxRate;
    }

    event PoolPaused(address indexed pool);
    event PoolUnpaused(address indexed pool);
    event EmergencyAction(string action, address indexed target, uint256 value);

    constructor(address _edenCore, address _admin) {
        edenCore = EdenCore(_edenCore);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @notice Get protocol-wide statistics
     */
    function getProtocolStats() external view returns (ProtocolStats memory stats) {
        address[] memory pools = edenCore.getAllPools();
        uint256 tvl;
        uint256 activePools;

        for (uint256 i = 0; i < pools.length; i++) {
            (uint256 deposited,,,) = IInvestmentPool(pools[i]).getPoolStats();
            tvl += deposited;

            (,,,, bool isActive) = edenCore.poolInfo(pools[i]);

            if (isActive) {
                activePools++;
            }
        }

        stats = ProtocolStats({
            totalValueLocked: tvl,
            totalPools: pools.length,
            activePools: activePools,
            totalTaxCollected: 0, // Would need tax collector integration
            globalTaxRate: edenCore.globalTaxRate()
        });
    }

    /**
     * @notice Get detailed pool statistics
     */
    function getPoolStats(address pool) external view returns (PoolStats memory stats) {
        (string memory name,,,, bool isActive) = edenCore.poolInfo(pool);

        (uint256 deposited, uint256 withdrawn,, uint256 utilization) = IInvestmentPool(pool).getPoolStats();

        stats = PoolStats({
            pool: pool,
            name: name,
            totalDeposited: deposited,
            totalWithdrawn: withdrawn,
            utilizationRate: utilization,
            activeInvestments: deposited - withdrawn,
            isActive: isActive
        });
    }

    /**
     * @notice Get all pools with statistics
     */
    function getAllPoolsWithStats() external view returns (PoolStats[] memory) {
        address[] memory pools = edenCore.getAllPools();
        PoolStats[] memory allStats = new PoolStats[](pools.length);

        for (uint256 i = 0; i < pools.length; i++) {
            allStats[i] = this.getPoolStats(pools[i]);
        }

        return allStats;
    }

    // ============ POOL MANAGEMENT ============

    /**
     * @notice Create a new pool with parameters
     */
    function createPool(IPoolFactory.PoolParams memory params) external onlyRole(ADMIN_ROLE) returns (address pool) {
        pool = edenCore.createPool(params);
        emit EmergencyAction("POOL_CREATED", pool, 0);
    }

    /**
     * @notice Pause a specific pool
     */
    function pausePool(address pool) external onlyRole(OPERATOR_ROLE) {
        IInvestmentPool(pool).pause();
        emit PoolPaused(pool);
    }

    /**
     * @notice Unpause a specific pool
     */
    function unpausePool(address pool) external onlyRole(OPERATOR_ROLE) {
        IInvestmentPool(pool).unpause();
        emit PoolUnpaused(pool);
    }

    /**
     * @notice Update pool configuration
     */
    function updatePoolConfig(address pool, IInvestmentPool.PoolConfig memory config) external onlyRole(ADMIN_ROLE) {
        IInvestmentPool(pool).updatePoolConfig(config);
    }

    /**
     * @notice Toggle pool active status
     */
    function setPoolActive(address pool, bool active) external onlyRole(ADMIN_ROLE) {
        edenCore.setPoolActive(pool, active);
    }

    // ============ PROTOCOL CONFIGURATION ============

    /**
     * @notice Update global tax rate
     */
    function setGlobalTaxRate(uint256 rate) external onlyRole(ADMIN_ROLE) {
        edenCore.setGlobalTaxRate(rate);
    }

    /**
     * @notice Update protocol treasury
     */
    function setProtocolTreasury(address treasury) external onlyRole(ADMIN_ROLE) {
        edenCore.setProtocolTreasury(treasury);
    }

    /**
     * @notice Update contract connections
     */
    function updateProtocolContracts(address poolFactory, address taxCollector, address swapRouter, address nftManager)
        external
        onlyRole(ADMIN_ROLE)
    {
        if (poolFactory != address(0)) edenCore.setPoolFactory(poolFactory);
        if (taxCollector != address(0)) edenCore.setTaxCollector(taxCollector);
        if (swapRouter != address(0)) edenCore.setSwapRouter(swapRouter);
        if (nftManager != address(0)) edenCore.setNFTManager(nftManager);
    }

    // ============ EMERGENCY FUNCTIONS ============

    /**
     * @notice Pause entire protocol
     */
    function pauseProtocol() external onlyRole(ADMIN_ROLE) {
        edenCore.pause();
        emit EmergencyAction("PROTOCOL_PAUSED", address(edenCore), 0);
    }

    /**
     * @notice Unpause entire protocol
     */
    function unpauseProtocol() external onlyRole(ADMIN_ROLE) {
        edenCore.unpause();
        emit EmergencyAction("PROTOCOL_UNPAUSED", address(edenCore), 0);
    }

    /**
     * @notice Emergency withdraw from Eden Core
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        edenCore.emergencyWithdraw(token, amount);
        emit EmergencyAction("EMERGENCY_WITHDRAW", token, amount);
    }

    // ============ BATCH OPERATIONS ============

    /**
     * @notice Batch pause multiple pools
     */
    function batchPausePools(address[] calldata pools) external onlyRole(OPERATOR_ROLE) {
        for (uint256 i = 0; i < pools.length; i++) {
            IInvestmentPool(pools[i]).pause();
            emit PoolPaused(pools[i]);
        }
    }

    /**
     * @notice Batch update pool configurations
     */
    function batchUpdatePoolConfigs(address[] calldata pools, IInvestmentPool.PoolConfig[] calldata configs)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(pools.length == configs.length, "Length mismatch");

        for (uint256 i = 0; i < pools.length; i++) {
            IInvestmentPool(pools[i]).updatePoolConfig(configs[i]);
        }
    }

    // ============ MONITORING ============

    /**
     * @notice Check pool health
     */
    function checkPoolHealth(address pool) external view returns (bool isHealthy, string memory issue) {
        try IInvestmentPool(pool).getPoolStats() returns (
            uint256 deposited, uint256 withdrawn, uint256, uint256 utilization
        ) {
            if (utilization > 9500) {
                // 95%
                return (false, "High utilization");
            }
            if (withdrawn > deposited) {
                return (false, "Negative balance");
            }
            return (true, "");
        } catch {
            return (false, "Pool unreachable");
        }
    }

    /**
     * @notice Get pools requiring attention
     */
    function getPoolsRequiringAttention() external view returns (address[] memory pools, string[] memory issues) {
        address[] memory allPools = edenCore.getAllPools();
        address[] memory tempPools = new address[](allPools.length);
        string[] memory tempIssues = new string[](allPools.length);
        uint256 count = 0;

        for (uint256 i = 0; i < allPools.length; i++) {
            (bool isHealthy, string memory issue) = this.checkPoolHealth(allPools[i]);
            if (!isHealthy) {
                tempPools[count] = allPools[i];
                tempIssues[count] = issue;
                count++;
            }
        }

        pools = new address[](count);
        issues = new string[](count);
        for (uint256 i = 0; i < count; i++) {
            pools[i] = tempPools[i];
            issues[i] = tempIssues[i];
        }
    }
}
