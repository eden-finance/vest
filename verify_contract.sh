#!/bin/bash

# Configuration
CHAIN_ID=42421
RPC_URL=$TESTNET_RPC
SOLC_VERSION="v0.8.22"
VERIFIER_URL="https://scan-testnet.assetchain.org/api?"
LOG_FILE="verify_contracts.log"

# Check environment variables
if [ -z "$RPC_URL" ]; then
    echo "Error: TESTNET_RPC environment variable not set."
    echo "Please set it, e.g., export TESTNET_RPC=https://enugu-rpc.assetchain.org"
    exit 1
fi

# Check if contract files exist
if [ ! -f "script/NigerianMoneyMarket.s.sol" ]; then
    echo "Error: script/NigerianMoneyMarket.s.sol not found."
    exit 1
fi
if [ ! -f "src/NigerianMoneyMarket.sol" ]; then
    echo "Error: src/NigerianMoneyMarket.sol not found."
    exit 1
fi
if [ ! -f "src/NMMNFT.sol" ]; then
    echo "Error: src/NMMNFT.sol not found."
    exit 1
fi
if [ ! -f "src/libs/NMMNFTRenderer.sol" ]; then
    echo "Error: src/libs/NMMNFTRenderer.sol not found."
    exit 1
fi
if [ ! -f "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol" ]; then
    echo "Error: OpenZeppelin ERC1967Proxy.sol not found. Run 'forge install openzeppelin/openzeppelin-contracts'."
    exit 1
fi

# Log all output to a file
exec > >(tee -a $LOG_FILE) 2>&1

# Test RPC connectivity
echo "Testing RPC connectivity..."
if ! cast block latest --rpc-url $RPC_URL > /dev/null; then
    echo "Error: Failed to connect to RPC URL $RPC_URL. Check the URL or network status."
    exit 1
fi

# Clear cache and recompile contracts
echo "Clearing cache and recompiling contracts with $SOLC_VERSION..."
forge clean
if ! forge build --force --compiler-version $SOLC_VERSION --root .; then
    echo "Error: Compilation failed with $SOLC_VERSION. Trying v0.8.22+commit.87f61d96..."
    if ! forge build --force --compiler-version 0.8.22+commit.87f61d96.Darwin.appleclang --root .; then
        echo "Error: Compilation failed. Check contract code or foundry.toml."
        exit 1
    fi
    SOLC_VERSION="v0.8.22+commit.87f61d96"
fi

# Check for MockERC20 artifact
echo "Checking for MockERC20 artifact..."
if [ ! -d "out/NigerianMoneyMarket.s.sol" ] || [ ! -f "out/NigerianMoneyMarket.s.sol/MockERC20.json" ]; then
    echo "Error: No artifact found for MockERC20 in script/NigerianMoneyMarket.s.sol."
    echo "Available artifacts:"
    ls -R out
    exit 1
fi

# Check for NigerianMoneyMarket artifact
echo "Checking for NigerianMoneyMarket artifact..."
if [ ! -d "out/NigerianMoneyMarket.sol" ] || [ ! -f "out/NigerianMoneyMarket.sol/NigerianMoneyMarket.json" ]; then
    echo "Error: No artifact found for NigerianMoneyMarket in src/NigerianMoneyMarket.sol."
    echo "Available artifacts:"
    ls -R out
    exit 1
fi

# Check for NMMNFTRenderer artifact
echo "Checking for NMMNFTRenderer artifact..."
if [ ! -d "out/NMMNFTRenderer.sol" ] || [ ! -f "out/NMMNFTRenderer.sol/NMMNFTRenderer.json" ]; then
    echo "Error: No artifact found for NMMNFTRenderer in src/lib/NMMNFTRenderer.sol"
    echo "Available artifacts:"
    ls -R out
    exit 1
fi

# Check for ERC1967Proxy artifact
echo "Checking for ERC1967Proxy artifact..."
if [ ! -d "out/ERC1967Proxy.sol" ] || [ ! -f "out/ERC1967Proxy.sol/ERC1967Proxy.json" ]; then
    echo "Error: No artifact found for ERC1967Proxy in lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol."
    echo "Available artifacts:"
    ls -R out
    exit 1
fi

# Test cast abi-encode for MockERC20
echo "Testing cast abi-encode for MockERC20..."
if ! cast abi-encode "constructor(string,string,uint8)" "cNGN Stablecoin" "cNGN" 18 > /dev/null; then
    echo "Error: cast abi-encode failed for MockERC20. Check constructor signature or update Foundry."
    exit 1
fi

# Test cast abi-encode for ERC1967Proxy
echo "Testing cast abi-encode for ERC1967Proxy..."
if ! cast abi-encode "constructor(address,bytes)" 0x1645133509eB39aAc9248a9946Fe4454B2AeC195 0x2313d7eb000000000000000000000000686aef1de9511f1a99fb43062ac570296122bb7c00000000000000000000000054527b09aeb2be23f99958db8f2f827dab863a2800000000000000000000000000000000000000000000000000000000000007d000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000068bb6616b7f12b2ef7650dff84febcacd342c82e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000054527b09aeb2be23f99958db8f2f827dab863a280000000000000000000000001234567890123456789012345678901234567890 > /dev/null; then
    echo "Error: cast abi-encode failed for ERC1967Proxy. Check constructor signature or update Foundry."
    exit 1
fi

# Function to run forge verify-contract with error handling
run_verify() {
    local contract_name=$1
    local output_file=$2
    local command=$3
    echo "Generating Standard JSON Input for $contract_name..."
    if ! eval "$command"; then
        echo "Error: Failed to generate JSON for $contract_name. Trying without --show-standard-json-input..."
        # Fallback without --show-standard-json-input
        command_without_json="${command/--show-standard-json-input /}"
        if ! eval "$command_without_json"; then
            echo "Error: Fallback verification failed for $contract_name. Check $LOG_FILE for details."
            exit 1
        fi
        echo "Warning: Generated without --show-standard-json-input. Manually generate JSON if needed."
        return
    fi
    if [ ! -s "$output_file" ]; then
        echo "Error: Generated JSON file $output_file is empty."
        exit 1
    fi
    echo "Generated JSON for $contract_name successfully: $output_file"
}

# NMMNFT
run_verify "NMMNFT" "nft_renderer.json" "forge verify-contract \
  --chain $CHAIN_ID \
  --compiler-version $SOLC_VERSION \
  --num-of-optimizations 100000 \
  0x68bb6616b7f12b2ef7650dff84febcacd342c82e \
  src/NMMNFT.sol:NMMNFT \
  --verifier blockscout \
  --verifier-url $VERIFIER_URL \
  --show-standard-json-input \
  --verbosity > nft_renderer.json"

# MockERC20
run_verify "MockERC20" "mock_cngn.json" "forge verify-contract \
  --chain $CHAIN_ID \
  --compiler-version $SOLC_VERSION \
  --num-of-optimizations 100000 \
  --constructor-args \"\$(cast abi-encode 'constructor(string,string,uint8)' 'cNGN Stablecoin' 'cNGN' 18)\" \
  0x686aef1de9511f1a99fb43062ac570296122bb7c \
  script/NigerianMoneyMarket.s.sol:MockERC20 \
  --verifier blockscout \
  --verifier-url $VERIFIER_URL \
  --show-standard-json-input \
  --verbosity > mock_cngn.json"

# NigerianMoneyMarket Implementation
run_verify "NigerianMoneyMarket Implementation" "implementation.json" "forge verify-contract \
  --chain $CHAIN_ID \
  --compiler-version $SOLC_VERSION \
  --num-of-optimizations 100000 \
  0x1645133509eb39aac9248a9946fe4454b2aec195 \
  src/NigerianMoneyMarket.sol:NigerianMoneyMarket \
  --verifier blockscout \
  --verifier-url $VERIFIER_URL \
  --show-standard-json-input \
  --verbosity > implementation.json"

# ERC1967Proxy
run_verify "ERC1967Proxy" "proxy.json" "forge verify-contract \
  --chain $CHAIN_ID \
  --compiler-version $SOLC_VERSION \
  --num-of-optimizations 100000 \
  --constructor-args \"\$(cast abi-encode 'constructor(address,bytes)' 0x1645133509eb39aac9248a9946fe4454b2aec195 0x2313d7eb000000000000000000000000686aef1de9511f1a99fb43062ac570296122bb7c00000000000000000000000054527b09aeb2be23f99958db8f2f827dab863a2800000000000000000000000000000000000000000000000000000000000007d000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000200000000000000000000000068bb6616b7f12b2ef7650dff84febcacd342c82e000000000000000000000000000000000000000000000000000000000000000200000000000000000000000054527b09aeb2be23f99958db8f2f827dab863a280000000000000000000000001234567890123456789012345678901234567890)\" \
  0x76ab610b39338149f04aabcfe42d69cb9584ac78 \
  lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy \
  --verifier blockscout \
  --verifier-url $VERIFIER_URL \
  --show-standard-json-input \
  --verbosity > proxy.json"

echo "Standard JSON Input files generated: mock_cngn.json, implementation.json, proxy.json"
echo "Please upload these files to the Assetchain testnet explorer at https://scan-testnet.assetchain.org"
echo "Logs saved to $LOG_FILE"