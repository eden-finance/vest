// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/ILPToken.sol";

/**
 * @title LPToken
 * @notice ERC20 token representing pool shares
 * @dev Mintable/burnable by authorized pools
 */
contract LPToken is Initializable, ERC20Upgradeable, AccessControlUpgradeable, ILPToken {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    address public pool;

    function initialize(string memory name, string memory symbol, address admin, address _pool) public initializer {
        __ERC20_init(name, symbol);
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, _pool);
        pool = address(_pool);
    }

    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external override onlyRole(MINTER_ROLE) {
        _burn(from, amount);
    }

    function setPool(address _pool) external onlyRole(ADMIN_ROLE) {
        pool = _pool;
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
        super.grantRole(role, account);
    }
}
