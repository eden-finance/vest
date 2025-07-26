// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IInvestmentPool.sol";
import "./EdenVestCore.sol";

/**
 * @title AdminInterface
 * @notice Administrative interface for Eden Finance protocol management
 */
contract AdminInterface is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant MAX_POOLS_PER_QUERY = 50;

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
        uint256 globalTaxRate;
    }

    event PoolPaused(address indexed pool);
    event PoolUnpaused(address indexed pool);
    event EmergencyAction(string action, address indexed target, uint256 value);

    error InvalidEdenCore(address core);
    error PoolNotRegistered(address pool);
    error InvalidAdmin(address provided);

    modifier validPool(address pool) {
        if (pool == address(0)) revert PoolNotRegistered(pool);
        if (!edenCore.isRegisteredPool(pool)) revert PoolNotRegistered(pool);
        _;
    }

    constructor(address _edenCore, address _admin) {
        if (_edenCore == address(0)) revert InvalidEdenCore(_edenCore);
        if (_admin == address(0)) revert InvalidAdmin(_admin);

        if (_edenCore.code.length == 0) revert InvalidEdenCore(_edenCore);

        try EdenCore(_edenCore).globalTaxRate() returns (uint256) {
            edenCore = EdenCore(_edenCore);
        } catch {
            revert InvalidEdenCore(_edenCore);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);

        emit EmergencyAction("ADMIN_INTERFACE_DEPLOYED", _edenCore, 0);
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
            address pool = pools[i];

            // Safe external call with try-catch
            try IInvestmentPool(pool).getPoolStats() returns (uint256 deposited, uint256, uint256, uint256) {
                tvl += deposited;
            } catch {
                // Pool call failed - continue with next pool
                continue;
            }

            try edenCore.poolInfo(pool) returns (string memory, address, address, uint256, bool isActive) {
                if (isActive) {
                    activePools++;
                }
            } catch {
                // Pool info call failed - continue
                continue;
            }
        }

        stats = ProtocolStats({
            totalValueLocked: tvl,
            totalPools: pools.length,
            activePools: activePools,
            globalTaxRate: edenCore.globalTaxRate()
        });
    }

    /**
     * @notice Get detailed pool statistics
     */
    function getPoolStats(address pool) external view validPool(pool) returns (PoolStats memory stats) {
        (string memory name,,,, bool isActive) = edenCore.poolInfo(pool);

        try IInvestmentPool(pool).getPoolStats() returns (
            uint256 deposited, uint256 withdrawn, uint256, uint256 utilization
        ) {
            stats = PoolStats({
                pool: pool,
                name: name,
                totalDeposited: deposited,
                totalWithdrawn: withdrawn,
                utilizationRate: utilization,
                activeInvestments: deposited > withdrawn ? deposited - withdrawn : 0,
                isActive: isActive
            });
        } catch {
            // Return default stats if pool is unreachable
            stats = PoolStats({
                pool: pool,
                name: name,
                totalDeposited: 0,
                totalWithdrawn: 0,
                utilizationRate: 0,
                activeInvestments: 0,
                isActive: false
            });
        }
    }

    /**
     * @notice Get all pools with statistics
     */
    function getAllPoolsWithStats(uint256 offset, uint256 limit)
        external
        view
        returns (PoolStats[] memory stats, uint256 total)
    {
        address[] memory pools = edenCore.getAllPools();
        total = pools.length;

        if (limit > MAX_POOLS_PER_QUERY) limit = MAX_POOLS_PER_QUERY;
        if (offset >= total) return (new PoolStats[](0), total);

        uint256 end = offset + limit;
        if (end > total) end = total;

        stats = new PoolStats[](end - offset);

        for (uint256 i = offset; i < end; i++) {
            try this.getPoolStats(pools[i]) returns (PoolStats memory poolStats) {
                stats[i - offset] = poolStats;
            } catch {
                stats[i - offset] = PoolStats({
                    pool: pools[i],
                    name: "",
                    totalDeposited: 0,
                    totalWithdrawn: 0,
                    utilizationRate: 0,
                    activeInvestments: 0,
                    isActive: false
                });
            }
        }
    }

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
    function getPoolsRequiringAttention(uint256 maxPools)
        external
        view
        returns (address[] memory pools, string[] memory issues)
    {
        address[] memory allPools = edenCore.getAllPools();
        uint256 poolCount = allPools.length;

        if (maxPools == 0 || maxPools > MAX_POOLS_PER_QUERY) {
            maxPools = MAX_POOLS_PER_QUERY;
        }

        if (poolCount > maxPools) poolCount = maxPools;

        address[] memory tempPools = new address[](poolCount);
        string[] memory tempIssues = new string[](poolCount);
        uint256 count = 0;

        for (uint256 i = 0; i < poolCount && count < maxPools; i++) {
            try this.checkPoolHealth(allPools[i]) returns (bool isHealthy, string memory issue) {
                if (!isHealthy) {
                    tempPools[count] = allPools[i];
                    tempIssues[count] = issue;
                    count++;
                }
            } catch {
                // Pool health check failed
                tempPools[count] = allPools[i];
                tempIssues[count] = "Health check failed";
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
