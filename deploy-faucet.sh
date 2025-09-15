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
if [[ -z "$RPC_URL" || -z "$PRIVATE_KEY" ]]; then
  echo "❌ RPC_URL or PRIVATE_KEY not set in .env"
  exit 1
fi

# Set defaults if not provided
CHAIN_ID=${CHAIN_ID:-"42421"}
RPC_URL=${RPC_URL:-"https://enugu-rpc.assetchain.org/"}
VERIFIER=${VERIFIER:-"blockscout"}
VERIFIER_URL=${VERIFIER_URL:-"https://scan-testnet.assetchain.org/api/"}
ADMIN_ADDRESS=${ADMIN_ADDRESS:-$(cast wallet address --private-key $PRIVATE_KEY)}
FAUCET_NATIVE_FUNDING=${FAUCET_NATIVE_FUNDING:-"1"}

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

# Run deployment script
forge script script/05_Faucet.s.sol:DeployFaucetScript \
  --broadcast \
  --rpc-url "$RPC_URL" \
  --legacy \
  --gas-limit 80000000 \
  --private-key "$PRIVATE_KEY" \
  -vvv | tee faucet_deployment.log

# ───────────────────────────────────────────────
# Extract Deployed Addresses
# ───────────────────────────────────────────────
echo ""
echo "📝 Extracting deployed addresses..."

# Parse addresses from deployment log
FAUCET=$(grep "Faucet deployed at:" faucet_deployment.log | tail -1 | awk '{print $NF}')
CNGN=$(grep "cNGN deployed at:" faucet_deployment.log | tail -1 | awk '{print $NF}')
USDC=$(grep "USDC deployed at:" faucet_deployment.log | tail -1 | awk '{print $NF}')
USDT=$(grep "USDT deployed at:" faucet_deployment.log | tail -1 | awk '{print $NF}')

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
# EdenVest Faucet Deployment
FAUCET_ADDRESS=$FAUCET
CNGN_ADDRESS=$CNGN
USDC_ADDRESS=$USDC
USDT_ADDRESS=$USDT
EOF

# Save to JSON
cat <<EOF > deployments/faucet.json
{
      "faucet": "$FAUCET",
      "cNGN": "$CNGN",
      "USDC": "$USDC",
      "USDT": "$USDT"
}
EOF

echo "✅ Addresses saved to .env.faucet and deployments/faucet.json"

# ───────────────────────────────────────────────
# Wait before verification
# ───────────────────────────────────────────────
echo ""
echo "⏳ Waiting 30 seconds before verification..."
sleep 30

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
  local MAX_RETRIES=3
  local RETRY_COUNT=0
  
  echo "  Verifying $CONTRACT_NAME at $ADDRESS..."
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ -z "$CONSTRUCTOR_ARGS" ]; then
      # No constructor args
      forge verify-contract \
        --rpc-url "$RPC_URL" \
        --verifier "$VERIFIER" \
        --verifier-url "$VERIFIER_URL" \
        "$ADDRESS" \
        "$CONTRACT_PATH" --show-standard-json-input > deployments/stdjson.faucet.$ADDRESS.$CHAIN_ID.json && break
    else
      # With constructor args
      forge verify-contract \
        --rpc-url "$RPC_URL" \
        --verifier "$VERIFIER" \
        --verifier-url "$VERIFIER_URL" \
        --constructor-args "$CONSTRUCTOR_ARGS" \
        "$ADDRESS" \
        "$CONTRACT_PATH"  --show-standard-json-input > deployments/stdjson.faucet.$ADDRESS.$CHAIN_ID.json&& break
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "    Retry $RETRY_COUNT/$MAX_RETRIES in 10 seconds..."
      sleep 10
    fi
  done
  
  if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "  ⚠️ Failed to verify $CONTRACT_NAME after $MAX_RETRIES attempts"
  else
    echo "  ✅ $CONTRACT_NAME verified successfully"
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
  "Celo Nigerian Naira" \
  "cNGN" \
  6 \
  1000000000 \
  "$FAUCET")
verify_contract "$CNGN" "src/misc/Faucet.sol:EdenVestFaucet" "$CNGN_ARGS" "cNGN"

# Verify USDC Token
echo ""
echo "3️⃣ Verifying USDC Token..."
USDC_ARGS=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
  "USD Coin" \
  "USDC" \
  18 \
  1000000000 \
  "$FAUCET")
verify_contract "$USDC" "src/misc/Faucet.sol:EdenVestFaucet" "$USDC_ARGS" "USDC"

# Verify USDT Token
echo ""
echo "4️⃣ Verifying USDT Token..."
USDT_ARGS=$(cast abi-encode "constructor(string,string,uint8,uint256,address)" \
  "Tether USD" \
  "USDT" \
  18 \
  1000000000 \
  "$FAUCET")
verify_contract "$USDT" "src/misc/Faucet.sol:EdenVestFaucet" "$USDT_ARGS" "USDT"

# ───────────────────────────────────────────────
# Final Summary
# ───────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo "🎉 FAUCET DEPLOYMENT COMPLETE!"
echo "═══════════════════════════════════════════════"
echo ""
echo "📌 Deployed Contracts:"
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
echo "  Daily:     2 claims per day"
echo ""
echo "💰 Native Token Configuration:"
echo "  Amount:    0.001 tokens per claim"
echo "  Cooldown:  2 hours"
echo "  Daily:     2 claims per day"
echo ""
echo "📁 Files Created:"
echo "  - .env.faucet (environment variables)"
echo "  - deployments/faucet.json (deployment data)"
echo "  - faucet_commands.sh (interaction commands)"
echo ""
echo "🔗 Block Explorer:"
if [[ "$CHAIN_ID" == "42421" ]]; then
  echo "  https://scan-testnet.assetchain.org/address/$FAUCET"
else
  echo "  Check your chain's block explorer"
fi
echo ""
echo "═══════════════════════════════════════════════"