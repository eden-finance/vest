// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ILPToken.sol";

/**
 * @title LPToken
 * @notice ERC20 token representing pool shares
 * @dev Mintable/burnable by authorized pools
 */
contract LPToken is Initializable, PausableUpgradeable, ERC20Upgradeable, AccessControlUpgradeable, ILPToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public pool;
    uint256 public maxSupply;
    bool public hasMaxSupply;

    event PoolSet(address indexed oldPool, address indexed newPool);
    event TokensMinted(address indexed to, uint256 amount, address indexed minter);
    event TokensBurned(address indexed from, uint256 amount, address indexed burner);

    event MaxSupplySet(uint256 maxSupply);

    error InvalidAddress(address provided);
    error InvalidTokenName();
    error InvalidTokenSymbol();
    error ZeroAddress();
    error ZeroAmount();
    error BurnAmountExceedsBalance(uint256 balance, uint256 amount);
    error MaxSupplyExceeded(uint256 currentSupply, uint256 maxSupply, uint256 mintAmount);

    function initialize(string memory name, string memory symbol, address admin, address _pool) public initializer {
        if (bytes(name).length == 0) revert InvalidTokenName();
        if (bytes(symbol).length == 0) revert InvalidTokenSymbol();
        if (admin == address(0)) revert InvalidAddress(admin);
        if (_pool == address(0)) revert InvalidAddress(_pool);

        if (_pool.code.length == 0) revert InvalidAddress(_pool);

        __ERC20_init(name, symbol);
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _grantRole(MINTER_ROLE, _pool);
        pool = address(_pool);

        emit PoolSet(address(0), _pool);
    }

    function setMaxSupply(uint256 _maxSupply) external onlyRole(ADMIN_ROLE) {
        require(_maxSupply >= totalSupply(), "Max supply below current supply");
        maxSupply = _maxSupply;
        hasMaxSupply = true;
        emit MaxSupplySet(_maxSupply);
    }

    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        if (hasMaxSupply) {
            uint256 newSupply = totalSupply() + amount;
            if (newSupply > maxSupply) revert MaxSupplyExceeded(totalSupply(), maxSupply, amount);
        }

        _mint(to, amount);
        emit TokensMinted(to, amount, msg.sender);
    }

    function burn(address from, uint256 amount) external override onlyRole(MINTER_ROLE) whenNotPaused {
        if (from == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 balance = balanceOf(from);
        if (amount > balance) revert BurnAmountExceedsBalance(balance, amount);

        _burn(from, amount);
        emit TokensBurned(from, amount, msg.sender);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setPool(address _pool) external onlyRole(ADMIN_ROLE) {
        if (_pool == address(0)) revert InvalidAddress(_pool);
        if (_pool.code.length == 0) revert InvalidAddress(_pool);
        address oldPool = pool;

        if (oldPool != address(0)) {
            _revokeRole(MINTER_ROLE, oldPool);
        }

        _grantRole(MINTER_ROLE, _pool);

        pool = _pool;

        emit PoolSet(oldPool, _pool);
    }

    /**
     * @dev Override grantRole to resolve conflict between AccessControlUpgradeable and ILPToken
     */
    function grantRole(bytes32 role, address account)
        public
        virtual
        override(AccessControlUpgradeable, ILPToken)
        onlyRole(getRoleAdmin(role))
    {
        if (role == MINTER_ROLE) {
            require(account != address(0), "Invalid minter address");

            require(account.code.length > 0, "Minter must be a contract");
        }
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        if (role == MINTER_ROLE && account == pool) {
            pool = address(0);
        }

        super.revokeRole(role, account);

        emit RoleRevoked(role, account, msg.sender);
    }

    function isMinter(address account) external view returns (bool) {
        return hasRole(MINTER_ROLE, account);
    }

    function isAdmin(address account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    function getPoolAddress() external view returns (address) {
        return pool;
    }
}
