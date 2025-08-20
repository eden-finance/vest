#!/bin/bash

set -e

echo "🚀 EdenVest Faucet Deployment Starting..."

# ───────────────────────────────────────────────
# Load Environment Variables
# ───────────────────────────────────────────────
if [ -f .env ]; then
  source .env
else
  echo "❌ .env file not found!"
  exit 1
fi

# Check required variables
required_vars=("CHAIN_ID" "RPC_URL" "PRIVATE_KEY" "ETHERSCAN_API_KEY")
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ $var not set in .env"
    exit 1
  fi
done

# Set defaults if not provided
ADMIN_ADDRESS=${ADMIN_ADDRESS:-$(cast wallet address --private-key $PRIVATE_KEY)}
FAUCET_NATIVE_FUNDING=${FAUCET_NATIVE_FUNDING:-"1"}

# Define chain-specific configurations
case $CHAIN_ID in
  84532) # Base Sepolia
    RPC_URL=${RPC_URL:-"https://sepolia.base.org"}
    VERIFIER=${VERIFIER:-"etherscan"}
    VERIFIER_URL=${VERIFIER_URL:-"https://api-sepolia.basescan.org/api"}
    EXPLORER_URL="https://sepolia.basescan.org"
    ;;
  8453) # Base Mainnet
    RPC_URL=${RPC_URL:-"https://mainnet.base.org"}
    VERIFIER=${VERIFIER:-"etherscan"}
    VERIFIER_URL=${VERIFIER_URL:-"https://api.basescan.org/api"}
    EXPLORER_URL="https://basescan.org"
    ;;
  42421) # Assetchain Testnet
    RPC_URL=${RPC_URL:-"https://enugu-rpc.assetchain.org"}
    VERIFIER=${VERIFIER:-"blockscout"}
    VERIFIER_URL=${VERIFIER_URL:-"https://scan-testnet.assetchain.org/api"}
    EXPLORER_URL="https://scan-testnet.assetchain.org"
    ;;
  *)
    echo "❌ Unsupported CHAIN_ID: $CHAIN_ID. Please configure RPC_URL, VERIFIER, VERIFIER_URL, and EXPLORER_URL."
    exit 1
    ;;
esac

# Create deployments directory
mkdir -p deployments

# ───────────────────────────────────────────────
# Deploy Faucet and Tokens
# ───────────────────────────────────────────────
echo "📦 Deploying Faucet Contract and Tokens..."
echo "  Chain: $CHAIN_ID"
echo "  RPC: $RPC_URL"
echo "  Admin: $ADMIN_ADDRESS"
echo ""

# Determine if --legacy is needed (Base networks support EIP-1559, Assetchain may require --legacy)
if [[ "$CHAIN_ID" == "84532" || "$CHAIN_ID" == "8453" ]]; then
  LEGACY_FLAG=""
else
  LEGACY_FLAG="--legacy"
fi

# Check deployer balance
DEPLOYER_BALANCE=$(cast balance --rpc-url "$RPC_URL" "$ADMIN_ADDRESS")
DEPLOYER_BALANCE_ETH=$(echo "$DEPLOYER_BALANCE / 1000000000000000000" | bc -l)

echo "  Deployer balance: $DEPLOYER_BALANCE_ETH ETH"

# Run deployment script
forge script script/05_Faucet.s.sol:DeployFaucetScript \
  --broadcast \
  --rpc-url "$RPC_URL" \
  --chain "$CHAIN_ID" \
  $LEGACY_FLAG \
  --gas-limit 80000000 \
  --private-key "$PRIVATE_KEY" \
  -vvv | tee deployments/faucet_deployment_$CHAIN_ID.log

# ───────────────────────────────────────────────
# Extract Deployed Addresses
# ───────────────────────────────────────────────
echo ""
echo "📝 Extracting deployed addresses..."

# Parse addresses from deployment log
FAUCET=$(grep "Faucet deployed at:" deployments/faucet_deployment_$CHAIN_ID.log | tail -1 | awk '{print $NF}')
CNGN=$(grep "cNGN deployed at:" deployments/faucet_deployment_$CHAIN_ID.log | tail -1 | awk '{print $NF}')
USDC=$(grep "USDC deployed at:" deployments/faucet_deployment_$CHAIN_ID.log | tail -1 | awk '{print $NF}')
USDT=$(grep "USDT deployed at:" deployments/faucet_deployment_$CHAIN_ID.log | tail -1 | awk '{print $NF}')

# Validate addresses were extracted
if [[ -z "$FAUCET" || -z "$CNGN" || -z "$USDC" || -z "$USDT" ]]; then
  echo "❌ Failed to extract addresses from deployment log"
  echo "  FAUCET: $FAUCET"
  echo "  cNGN: $CNGN"
  echo "  USDC: $USDC"
  echo "  USDT: $USDT"
  exit 1
fi

echo "✅ Addresses extracted successfully"
echo "  Faucet: $FAUCET"
echo "  cNGN: $CNGN"
echo "  USDC: $USDC"
echo "  USDT: $USDT"


# ───────────────────────────────────────────────
# Save Addresses to Files
# ───────────────────────────────────────────────
echo ""
echo "💾 Saving deployment addresses..."

# Save to .env.faucet
cat <<EOF > .env.faucet
# EdenVest Faucet Deployment (Chain ID: $CHAIN_ID)
FAUCET_ADDRESS=$FAUCET
CNGN_ADDRESS=$CNGN
USDC_ADDRESS=$USDC
USDT_ADDRESS=$USDT
EOF

# Save to JSON
cat <<EOF > deployments/faucet_$CHAIN_ID.json
{
  "chainId": "$CHAIN_ID",
  "explorerUrl": "$EXPLORER_URL",
  "faucet": "$FAUCET",
  "cNGN": "$CNGN",
  "USDC": "$USDC",
  "USDT": "$USDT"
}
EOF

echo "✅ Addresses saved to .env.faucet and deployments/faucet_$CHAIN_ID.json"

# ───────────────────────────────────────────────
# Wait before verification
# ───────────────────────────────────────────────
echo ""
echo "⏳ Waiting 60 seconds before verification to allow chain indexing..."
sleep 60

# ───────────────────────────────────────────────
# Verify Contracts
# ───────────────────────────────────────────────
echo ""
echo "🔍 Starting contract verification..."

# Function to verify contract with retries
verify_contract() {
  local ADDRESS=$1
  local CONTRACT_PATH=$2
  local CONSTRUCTOR_ARGS=$3
  local CONTRACT_NAME=$4
  local MAX_RETRIES=5
  local RETRY_COUNT=0
  
  echo "  Verifying $CONTRACT_NAME at $ADDRESS..."
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ -z "$CONSTRUCTOR_ARGS" ]; then
      # No constructor args
      forge verify-contract \
        --chain "$CHAIN_ID" \
        --verifier "$VERIFIER" \
        --verifier-url "$VERIFIER_URL" \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        "$ADDRESS" \
        "$CONTRACT_PATH" \
        --watch && break
    else
      # With constructor args
      forge verify-contract \
        --chain "$CHAIN_ID" \
        --verifier "$VERIFIER" \
        --verifier-url "$VERIFIER_URL" \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        "$ADDRESS" \
        "$CONTRACT_PATH" \
        --watch && break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "    Retry $RETRY_COUNT/$MAX_RETRIES in 15 seconds..."
      sleep 15
    fi
  done
  
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "  ⚠️ Failed to verify $CONTRACT_NAME after $MAX_RETRIES attempts"
    echo "  Manual verification command:"
    if [ -z "$CONSTRUCTOR_ARGS" ]; then
      echo "  forge verify-contract --chain $CHAIN_ID --verifier $VERIFIER --verifier-url $VERIFIER_URL --etherscan-api-key $ETHERSCAN_API_KEY $ADDRESS $CONTRACT_PATH --watch"
    else
      echo "  forge verify-contract --chain $CHAIN_ID --verifier $VERIFIER --verifier-url $VERIFIER_URL --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $CONSTRUCTOR_ARGS $ADDRESS $CONTRACT_PATH --watch"
    fi
  else
    echo "  ✅ $CONTRACT_NAME verified successfully"
    echo "  Check verification status: $EXPLORER_URL/address/$ADDRESS#code"
  fi
}

# Verify Faucet Contract
echo ""
echo "1️⃣ Verifying Faucet Contract..."
verify_contract "$FAUCET" "src/misc/Faucet.sol:EdenVestFaucet" "" "Faucet"

# Verify cNGN Token
echo ""
echo "2️⃣ Verifying cNGN Token..."
CNGN_ARGS=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
  "Compliant Nigerian Naira" \
  "cNGN" \
  18 \
  1000000000 \
  "$FAUCET")
verify_contract "$CNGN" "src/misc/Faucet.sol:FaucetToken" "$CNGN_ARGS" "cNGN"

# Verify USDC Token
echo ""
echo "3️⃣ Verifying USDC Token..."
USDC_ARGS=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
  "USD Coin" \
  "USDC" \
  18 \
  1000000000 \
  "$FAUCET")
verify_contract "$USDC" "src/misc/Faucet.sol:FaucetToken" "$USDC_ARGS" "USDC"

# Verify USDT Token
echo ""
echo "4️⃣ Verifying USDT Token..."
USDT_ARGS=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
  "Tether USD" \
  "USDT" \
  18 \
  1000000000 \
  "$FAUCET")
verify_contract "$USDT" "src/misc/Faucet.sol:FaucetToken" "$USDT_ARGS" "USDT"

# ───────────────────────────────────────────────
# Final Summary
# ───────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo "🎉 FAUCET DEPLOYMENT AND VERIFICATION COMPLETE!"
echo "═══════════════════════════════════════════════"
echo ""
echo "📌 Deployed Contracts on Chain ID $CHAIN_ID:"
echo "  Faucet:    $FAUCET"
echo "  cNGN:      $CNGN"
echo "  USDC:      $USDC"
echo "  USDT:      $USDT"
echo ""
echo "📊 Token Configuration:"
echo "  Supply:    1,000,000,000 tokens each"
echo "  Decimals:  18"
echo "  Amount:    10,000 tokens per claim"
echo "  Cooldown:  2 hours"
echo "  Daily:     3 claims per day"
echo ""
echo "💰 Native Token Configuration:"
echo "  Amount:    0.1 native tokens per claim"
echo "  Cooldown:  2 hours"
echo "  Daily:     3 claims per day"
echo ""
echo "📁 Files Created:"
echo "  - .env.faucet (environment variables)"
echo "  - deployments/faucet_$CHAIN_ID.json (deployment data)"
echo ""
echo "🔗 Block Explorer:"
echo "  Faucet: $EXPLORER_URL/address/$FAUCET#code"
echo "  cNGN:   $EXPLORER_URL/address/$CNGN#code"
echo "  USDC:   $EXPLORER_URL/address/$USDC#code"
echo "  USDT:   $EXPLORER_URL/address/$USDT#code"
echo ""
echo "═══════════════════════════════════════════════"