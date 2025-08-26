#!/bin/bash

set -e

echo "🚀 EdenVest Faucet Deployment Starting..."

# ───────────────────────────────────────────────
# Load Environment Variables
# ───────────────────────────────────────────────
if [ -f .env.base ]; then
  source .env.base
  echo "✅ Loaded environment variables from .env.base"
else
  echo "❌ .env.base file not found!"
  exit 1
fi

# Export variables so they're available to child processes
export ETHERSCAN_API_KEY
export CHAIN_ID
export RPC_URL
export PRIVATE_KEY

# Validate required variables
required_vars=("CHAIN_ID" "RPC_URL" "PRIVATE_KEY" "ETHERSCAN_API_KEY")
for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ $var not set in .env.base"
    exit 1
  fi
done

echo "✅ All required environment variables are set"

# ───────────────────────────────────────────────
# Network Configuration
# ───────────────────────────────────────────────
ADMIN_ADDRESS=${ADMIN_ADDRESS:-$(cast wallet address --private-key $PRIVATE_KEY)}
FAUCET_NATIVE_FUNDING=${FAUCET_NATIVE_FUNDING:-"1"}

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
  *)
    echo "❌ Unsupported CHAIN_ID: $CHAIN_ID. Please configure RPC_URL, VERIFIER, VERIFIER_URL, and EXPLORER_URL."
    exit 1
    ;;
esac

mkdir -p deployments

echo "📦 Deploying Faucet Contract and Tokens..."
echo "  Chain: $CHAIN_ID"
echo "  RPC: $RPC_URL"
echo "  Admin: $ADMIN_ADDRESS"
echo "  Verifier: $VERIFIER"
echo ""

# ───────────────────────────────────────────────
# Check Balance and Compile
# ───────────────────────────────────────────────
DEPLOYER_BALANCE=$(cast balance --rpc-url "$RPC_URL" "$ADMIN_ADDRESS")
DEPLOYER_BALANCE_ETH=$(echo "$DEPLOYER_BALANCE / 1000000000000000000" | bc -l)

echo "  Deployer balance: $DEPLOYER_BALANCE_ETH ETH"

if (( $(echo "$DEPLOYER_BALANCE_ETH < 0.01" | bc -l) )); then
  echo "⚠️  Warning: Low balance. Consider getting more testnet ETH."
fi

# Build contracts first
echo "🔨 Building contracts..."
forge build --silent
echo "✅ Contracts built successfully"

# ───────────────────────────────────────────────
# Deploy Contracts
# ───────────────────────────────────────────────
echo "🚀 Starting deployment..."
forge script script/05_Faucet.s.sol:DeployFaucetScript \
  --broadcast \
  --rpc-url "$RPC_URL" \
  --chain "$CHAIN_ID" \
  --gas-limit 80000000 \
  --private-key "$PRIVATE_KEY" \
  -vvv | tee deployments/faucet_deployment_$CHAIN_ID.log

echo ""
echo "📝 Extracting deployed addresses..."

# Extract addresses from deployment log
FAUCET=$(grep "Faucet deployed at:" deployments/faucet_deployment_$CHAIN_ID.log | tail -1 | awk '{print $NF}')
CNGN=$(grep "cNGN deployed at:" deployments/faucet_deployment_$CHAIN_ID.log | tail -1 | awk '{print $NF}')
USDC=$(grep "USDC deployed at:" deployments/faucet_deployment_$CHAIN_ID.log | tail -1 | awk '{print $NF}')
USDT=$(grep "USDT deployed at:" deployments/faucet_deployment_$CHAIN_ID.log | tail -1 | awk '{print $NF}')

if [[ -z "$FAUCET" || -z "$CNGN" || -z "$USDC" || -z "$USDT" ]]; then
  echo "❌ Failed to extract addresses from deployment log"
  echo "  FAUCET: $FAUCET"
  echo "  cNGN: $CNGN"
  echo "  USDC: $USDC"
  echo "  USDT: $USDT"
  echo ""
  echo "📋 Full deployment log:"
  cat deployments/faucet_deployment_$CHAIN_ID.log
  exit 1
fi

echo "✅ Addresses extracted successfully"
echo "  Faucet: $FAUCET"
echo "  cNGN: $CNGN"
echo "  USDC: $USDC"
echo "  USDT: $USDT"

# ───────────────────────────────────────────────
# Save Deployment Data
# ───────────────────────────────────────────────
echo ""
echo "💾 Saving deployment addresses..."

cat <<EOF > .env.faucet.$CHAIN_ID
# EdenVest Faucet Deployment (Chain ID: $CHAIN_ID)
FAUCET_ADDRESS=$FAUCET
CNGN_ADDRESS=$CNGN
USDC_ADDRESS=$USDC
USDT_ADDRESS=$USDT
EOF

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

echo "✅ Addresses saved to .env.faucet.$CHAIN_ID and deployments/faucet_$CHAIN_ID.json"

# ───────────────────────────────────────────────
# Wait for Chain Indexing
# ───────────────────────────────────────────────
echo ""
echo "⏳ Waiting for chain indexing before verification..."
echo "  This ensures contracts are properly indexed on the blockchain"
sleep 30

# ───────────────────────────────────────────────
# Verification Function
# ───────────────────────────────────────────────
verify_contract() {
  local ADDRESS=$1
  local CONTRACT_PATH=$2
  local CONSTRUCTOR_ARGS=$3
  local CONTRACT_NAME=$4
  local MAX_RETRIES=3
  local RETRY_COUNT=0
  
  echo "  🔍 Verifying $CONTRACT_NAME at $ADDRESS..."
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ -z "$CONSTRUCTOR_ARGS" ]; then
      # No constructor args
      echo "    Attempting verification without constructor args..."
      if forge verify-contract \
        --chain "$CHAIN_ID" \
        --verifier "$VERIFIER" \
        --verifier-url "$VERIFIER_URL" \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        "$ADDRESS" \
        "$CONTRACT_PATH" \
        --watch; then
        echo "    ✅ $CONTRACT_NAME verified successfully"
        return 0
      fi
    else
      # With constructor args
      echo "    Attempting verification with constructor args..."
      if forge verify-contract \
        --chain "$CHAIN_ID" \
        --verifier "$VERIFIER" \
        --verifier-url "$VERIFIER_URL" \
        --etherscan-api-key "$ETHERSCAN_API_KEY" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        "$ADDRESS" \
        "$CONTRACT_PATH" \
        --watch; then
        echo "    ✅ $CONTRACT_NAME verified successfully"
        return 0
      fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "    ⚠️  Retry $RETRY_COUNT/$MAX_RETRIES in 20 seconds..."
      sleep 20
    fi
  done
  
  echo "    ❌ Failed to verify $CONTRACT_NAME after $MAX_RETRIES attempts"
  echo "    📋 Manual verification command:"
  if [ -z "$CONSTRUCTOR_ARGS" ]; then
    echo "    forge verify-contract --chain $CHAIN_ID --verifier $VERIFIER --verifier-url $VERIFIER_URL --etherscan-api-key $ETHERSCAN_API_KEY $ADDRESS $CONTRACT_PATH --watch"
  else
    echo "    forge verify-contract --chain $CHAIN_ID --verifier $VERIFIER --verifier-url $VERIFIER_URL --etherscan-api-key $ETHERSCAN_API_KEY --constructor-args $CONSTRUCTOR_ARGS $ADDRESS $CONTRACT_PATH --watch"
  fi
  return 1
}

# ───────────────────────────────────────────────
# Verify All Contracts
# ───────────────────────────────────────────────
echo ""
echo "🔍 Starting automatic contract verification..."

VERIFICATION_SUCCESS=true

echo ""
echo "1️⃣ Verifying Faucet Contract..."
if ! verify_contract "$FAUCET" "src/misc/Faucet.sol:EdenVestFaucet" "" "Faucet"; then
  VERIFICATION_SUCCESS=false
fi

echo ""
echo "2️⃣ Verifying cNGN Token..."
CNGN_ARGS=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
  "Compliant Nigerian Naira" \
  "cNGN" \
  18 \
  1000000000 \
  "$FAUCET")
if ! verify_contract "$CNGN" "src/misc/Faucet.sol:FaucetToken" "$CNGN_ARGS" "cNGN"; then
  VERIFICATION_SUCCESS=false
fi

echo ""
echo "3️⃣ Verifying USDC Token..."
USDC_ARGS=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
  "USD Coin" \
  "USDC" \
  18 \
  1000000000 \
  "$FAUCET")
if ! verify_contract "$USDC" "src/misc/Faucet.sol:FaucetToken" "$USDC_ARGS" "USDC"; then
  VERIFICATION_SUCCESS=false
fi

echo ""
echo "4️⃣ Verifying USDT Token..."
USDT_ARGS=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
  "Tether USD" \
  "USDT" \
  18 \
  1000000000 \
  "$FAUCET")
if ! verify_contract "$USDT" "src/misc/Faucet.sol:FaucetToken" "$USDT_ARGS" "USDT"; then
  VERIFICATION_SUCCESS=false
fi

# ───────────────────────────────────────────────
# Final Summary
# ───────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
if [ "$VERIFICATION_SUCCESS" = true ]; then
  echo "🎉 FAUCET DEPLOYMENT AND VERIFICATION COMPLETE!"
else
  echo "⚠️  FAUCET DEPLOYMENT COMPLETE, BUT SOME VERIFICATIONS FAILED!"
fi
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
echo "  - .env.faucet.$CHAIN_ID (environment variables)"
echo "  - deployments/faucet_$CHAIN_ID.json (deployment data)"
echo ""
echo "🔗 Block Explorer:"
echo "  Faucet: $EXPLORER_URL/address/$FAUCET#code"
echo "  cNGN:   $EXPLORER_URL/address/$CNGN#code"
echo "  USDC:   $EXPLORER_URL/address/$USDC#code"
echo "  USDT:   $EXPLORER_URL/address/$USDT#code"
echo ""

if [ "$VERIFICATION_SUCCESS" = false ]; then
  echo "⚠️  Some contracts failed verification. Check the manual commands above."
  echo "   You can run them manually or check the block explorer for verification status."
fi

echo "═══════════════════════════════════════════════"