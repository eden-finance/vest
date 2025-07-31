// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/ITaxCollector.sol";

/**
 * @title TaxCollector
 * @notice Manages tax collection and distribution
 */
contract TaxCollector is ITaxCollector, Ownable {
    using SafeERC20 for IERC20;

    address public treasury;
    address public edenCore;

    mapping(address => uint256) public poolTaxCollected;
    mapping(address => uint256) public tokenTaxBalance;

    event TaxCollected(address indexed token, uint256 amount, address indexed pool);
    event TaxWithdrawn(address indexed token, uint256 amount, address indexed to);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event EdenCoreUpdated(address oldTreasury, address _treasury);

    constructor(address _treasury, address _owner, address _edenCore) Ownable(_owner) {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
        edenCore = _edenCore;
    }

    error NotEdenCore();

    // ============ MODIFIERS ============
    modifier onlyEdenCore() {
        if (msg.sender != edenCore) revert NotEdenCore();
        _;
    }

    function withdrawTax(address token) external onlyOwner {
        uint256 balance = tokenTaxBalance[token];
        require(balance > 0, "No tax to withdraw");

        tokenTaxBalance[token] = 0;
        IERC20(token).safeTransfer(treasury, balance);

        emit TaxWithdrawn(token, balance, treasury);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        address oldTreasury = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    function setEdenCore(address _edenCore) external onlyOwner {
        require(_edenCore != address(0), "Invalid EdenCore");
        address oldEdenCore = edenCore;
        edenCore = _edenCore;
        emit EdenCoreUpdated(oldEdenCore, _edenCore);
    }

    function getPoolTaxCollected(address pool) external view returns (uint256) {
        return poolTaxCollected[pool];
    }

    function getTokenTaxBalance(address token) external view returns (uint256) {
        return tokenTaxBalance[token];
    }

    function collectTax(address token, address pool, uint256 amount) external onlyEdenCore {
        tokenTaxBalance[token] += amount;
        emit TaxCollected(token, amount, pool);
    }
}
