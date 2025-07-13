# Nigerian Money Market Protocol

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Solidity](https://img.shields.io/badge/Solidity-^0.8.20-purple.svg)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-5.x-green.svg)
![AssetChain](https://img.shields.io/badge/AssetChain-Mainnet-orange.svg)

## Overview

The Nigerian Money Market Protocol is a decentralized finance (DeFi) platform that enables time-locked investments in Nigerian money markets using cNGN stablecoin. This protocol provides investors with secure, transparent, and profitable investment opportunities while maintaining regulatory compliance.

## Features

- **Time-locked Investments**: Secure your capital with predetermined lock periods
- **cNGN Stablecoin Integration**: Invest using Nigeria's premier stablecoin
- **Non-transferable NFTs**: Receive unique position tokens that cannot be transferred
- **Flexible Returns**: Support for both expected and actual returns managed by multisig
- **Upgradeable Architecture**: UUPS proxy pattern for future enhancements
- **Multi-role Access Control**: Admin, multisig, and pauser roles for security
- **Emergency Pause**: Circuit breaker functionality for security

## How It Works

1. **Invest**: Users deposit cNGN tokens and receive non-transferable NFTs representing their position
2. **Lock Period**: Investments are locked for a predetermined duration (default: 30 days)
3. **Returns**: Multisig-managed actual returns are set based on real market performance
4. **Withdraw**: After maturity, users can withdraw their principal plus returns

## Smart Contract Architecture

```
NigerianMoneyMarket (UUPS Proxy)
├── ERC721Upgradeable (Position NFTs)
├── AccessControl (Role-based permissions)
├── ReentrancyGuard (Protection against reentrancy)
├── Pausable (Emergency stop mechanism)
└── UUPSUpgradeable (Upgrade functionality)
```

## Installation

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/)
- [Node.js](https://nodejs.org/) (for additional tooling)

### Clone the Repository

```bash
git clone https://github.com/eden-finance/nigerian-money-market.git
cd nigerian-money-market
```

### Install Dependencies

```bash
forge install
```

### Set Up Environment Variables

Create a `.env` file in the root directory:

```env
# Deployment Configuration
PRIVATE_KEY=your_private_key_here
ADMIN_ADDRESS=0x...
CNGN_ADDRESS=0x...
MULTISIG_ADDRESS=0x...
EXPECTED_RATE=1500  # 15% in basis points

# RPC URLs
ASSETCHAIN_RPC=https://rpc.assetchain.org
TESTNET_RPC=https://testnet-rpc.assetchain.org

# Verification
ETHERSCAN_API_KEY=your_api_key_here
```

## Deployment

### Mainnet Deployment

```bash
# Deploy to AssetChain Mainnet
   forge script --chain 42421 script/NigerianMoneyMarket.s.sol:DeployTestnet --rpc-url $TESTNET_RPC --broadcast --private-key $PRIVATE_KEY
```

### Testnet Deployment

```bash
# Deploy to AssetChain Testnet (includes mock cNGN)
forge script script/DeployNigerianMoneyMarket.s.sol:DeployTestnet \
  --rpc-url $TESTNET_RPC \
  --broadcast
```

## Usage

### For Investors

#### Making an Investment

```solidity
// Approve cNGN spending
cNGN.approve(address(market), amount);

// Invest
uint256 tokenId = market.invest(amount);
```

#### Withdrawing Returns

```solidity
// Check if withdrawable
bool canWithdraw = market.isWithdrawable(tokenId);

// Withdraw after maturity
market.withdraw(tokenId);
```

### For Administrators

#### Updating Market Configuration

```solidity
market.updateMarketConfig(
    30 days,    // Lock duration
    1500,       // Expected rate (15%)
    true        // Accepting deposits
);
```

#### Managing Multisigs

```solidity
// Add multisig
market.updateMultisig(multisigAddress, true);

// Remove multisig
market.updateMultisig(multisigAddress, false);
```

### For Multisigs

#### Collecting Funds

```solidity
// Collect funds for investment
market.collectFunds(amount);
```

#### Setting Actual Returns

```solidity
uint256[] memory tokenIds = [1, 2, 3];
uint256[] memory actualReturns = [150e18, 200e18, 175e18];

market.setActualReturns(tokenIds, actualReturns);
```

## Testing

### Run All Tests

```bash
forge test
```

### Run Specific Test File

```bash
forge test --match-contract NigerianMoneyMarketTest
```

### Run with Verbose Output

```bash
forge test -vvv
```

### Generate Coverage Report

```bash
forge coverage
```

## Security

### Access Control

- **Admin Role**: Can update market configuration and manage multisigs
- **Multisig Role**: Can collect funds, return funds, and set actual returns
- **Pauser Role**: Can pause/unpause the contract in emergencies

### Security Features

- **ReentrancyGuard**: Prevents reentrancy attacks
- **Pausable**: Allows emergency stopping of contract functions
- **Non-transferable NFTs**: Position tokens cannot be transferred
- **Input Validation**: Comprehensive validation of all inputs
- **Safe Math**: Uses OpenZeppelin's SafeERC20 for token operations

### Audit Status

🔍 **Audit Pending** - This contract is currently undergoing security audit. Please use with caution in production environments.

## Contract Addresses

### AssetChain Mainnet

- **Proxy Contract**: `0x...` (To be updated after deployment)
- **Implementation**: `0x...` (To be updated after deployment)

### AssetChain Testnet

- **Proxy Contract**: `0x...` (To be updated after deployment)
- **Mock cNGN Token**: `0x...` (To be updated after deployment)

## API Reference

### Core Functions

#### `invest(uint256 amount) → uint256`
Creates a new investment position and returns the NFT token ID.

#### `withdraw(uint256 tokenId)`
Withdraws a matured investment position.

#### `getInvestment(uint256 tokenId) → Investment`
Returns detailed information about an investment.

#### `isWithdrawable(uint256 tokenId) → bool`
Checks if an investment can be withdrawn.

### View Functions

#### `getUserInvestments(address user) → uint256[]`
Returns all investment token IDs for a user.

#### `getContractBalance() → uint256`
Returns the total cNGN balance in the contract.

#### `marketConfig() → MarketConfig`
Returns current market configuration.

## Constants

- **MIN_INVESTMENT**: 1,000 cNGN
- **MAX_INVESTMENT**: 10,000,000 cNGN
- **DEFAULT_LOCK_DURATION**: 30 days
- **BASIS_POINTS**: 10,000 (100%)

## Events

```solidity
event InvestmentCreated(uint256 indexed tokenId, address indexed investor, uint256 amount, uint256 maturityTime);
event InvestmentWithdrawn(uint256 indexed tokenId, address indexed investor, uint256 principal, uint256 returns);
event InvestmentMatured(uint256 indexed tokenId, uint256 actualReturn);
event FundsCollected(address indexed multisig, uint256 amount);
event FundsReturned(address indexed multisig, uint256 amount);
event MarketConfigUpdated(uint256 lockDuration, uint256 expectedRate, bool acceptingDeposits);
event MultisigUpdated(address indexed multisig, bool authorized);
```

## Contributing

We welcome contributions to the Nigerian Money Market Protocol! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Development Guidelines

- Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Write comprehensive tests for new features
- Update documentation for any API changes
- Ensure all tests pass before submitting PR

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Disclaimer

This software is provided "as is" and any express or implied warranties are disclaimed. The use of this software is at your own risk. Eden Finance is not responsible for any losses that may occur from using this protocol.

## Support

For technical support or questions:

- **Email**: hello@edenfinance.org
- **Telegram**: [@eden_finance](https://t.me/@eden_finance)


## About Eden Finance

Eden Finance is a leading DeFi protocol focused on bringing traditional finance opportunities to the blockchain. We specialize in creating secure, transparent, and profitable investment products for the African financial markets and the world at large.

- **Website**: [https://edenfinance.org](https://edenfinance.org)
- **Twitter**: [@EdenFinance](https://twitter.com/0xedenfi)

