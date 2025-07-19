// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface ILPToken {
    function initialize(string memory name, string memory symbol, address admin, address pool_) external;
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
    function grantRole(bytes32 role, address account) external;
}
