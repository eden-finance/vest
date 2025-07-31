#!/bin/bash

set -e

echo "🚀 EdenVest Full Deployment Starting..."

# ───────────────────────────────────────────────
# Load .env
# ───────────────────────────────────────────────
if [ -f .env ]; then
  source .env
else
  echo "❌ .env file not found!"
  exit 1
fi

if [[ -z "$RPC_URL" || -z "$PRIVATE_KEY" ]]; then
  echo "❌ RPC_URL or PRIVATE_KEY not set in .env"
  exit 1
fi

mkdir -p deployments

# ───────────────────────────────────────────────
# Batch 1: Core Contracts
# ───────────────────────────────────────────────
echo "📦 Running Batch 1: Core Infrastructure..."
forge script script/01_DeployCore.s.sol:DeployCoreScript \
  --broadcast \
  --rpc-url "$RPC_URL" \
  --legacy \
  --gas-limit 60000000 \
  --private-key "$PRIVATE_KEY" | tee deployment.log

NFT_RENDERER=$(grep "NFT_RENDERER=" deployment.log | cut -d '=' -f2 | xargs)
TAX_COLLECTOR=$(grep "TAX_COLLECTOR=" deployment.log | cut -d '=' -f2 | xargs)
SWAP_ROUTER=$(grep "SWAP_ROUTER=" deployment.log | cut -d '=' -f2 | xargs)
EDEN_CORE_IMPL=$(grep "EDEN_CORE_IMPL=" deployment.log | cut -d '=' -f2 | xargs)

echo "✅ Batch 1 complete."
sleep 10

# ───────────────────────────────────────────────
# Batch 2: Proxy & EdenAdmin
# ───────────────────────────────────────────────
echo "🔐 Running Batch 2: Deploy Proxy and EdenAdmin..."
export NFT_RENDERER TAX_COLLECTOR SWAP_ROUTER EDEN_CORE_IMPL

forge script script/02_DeployProxy.s.sol:DeployProxyScript \
  --broadcast \
  --rpc-url "$RPC_URL" \
    --legacy \
  --gas-limit 60000000 \
  --private-key "$PRIVATE_KEY" | tee proxy.log

EDEN_CORE_PROXY=$(grep "export EDEN_CORE_PROXY=" proxy.log | cut -d '=' -f2 | xargs)
EDEN_ADMIN=$(grep "export EDEN_ADMIN=" proxy.log | cut -d '=' -f2 | xargs)

echo "✅ Batch 2 complete."
sleep 10

# ───────────────────────────────────────────────
# Batch 3A: PoolFactory
# ───────────────────────────────────────────────
echo "🏗️ Running Batch 3A: Deploy PoolFactory..."
forge script script/03a_DeployPoolFactory.s.sol:DeployPoolFactory \
  --broadcast \
  --rpc-url "$RPC_URL" \
  --legacy \
  --gas-limit 60000000 \
  --private-key "$PRIVATE_KEY" | tee factory.log

POOL_FACTORY=$(grep "export POOL_FACTORY=" factory.log | cut -d '=' -f2 | xargs)
POOL_IMPLEMENTATION=$(grep "export POOL_IMPLEMENTATION=" factory.log | cut -d '=' -f2 | xargs)
LP_TOKEN_IMPLEMENTATION=$(grep "export LP_TOKEN_IMPLEMENTATION=" factory.log | cut -d '=' -f2 | xargs)

# ───────────────────────────────────────────────
# Batch 3B: NFTPositionManager
# ───────────────────────────────────────────────
echo "🎨 Running Batch 3B: Deploy NFTPositionManager..."
forge script script/03b_DeployNFTPositionManager.s.sol:DeployNFTPositionManager \
  --broadcast \
  --rpc-url "$RPC_URL" \
    --legacy \
  --gas-limit 60000000 \
  --private-key "$PRIVATE_KEY" | tee nftpm.log

NFT_POSITION_MANAGER=$(grep "export NFT_POSITION_MANAGER=" nftpm.log | cut -d '=' -f2 | xargs)

echo "✅ Batch 3 complete."
sleep 10

# ───────────────────────────────────────────────
# Validate Before Final Config
# ───────────────────────────────────────────────
required_vars=(
  NFT_RENDERER TAX_COLLECTOR SWAP_ROUTER EDEN_CORE_IMPL
  EDEN_CORE_PROXY EDEN_ADMIN
  POOL_FACTORY POOL_IMPLEMENTATION LP_TOKEN_IMPLEMENTATION
  NFT_POSITION_MANAGER
)

for var in "${required_vars[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: $var is not set. Aborting Batch 4."
    exit 1
  fi
done

# ───────────────────────────────────────────────
# Batch 4: Final Configuration
# ───────────────────────────────────────────────
echo "⚙️ Running Batch 4: Final Protocol Configuration..."

export NFT_RENDERER TAX_COLLECTOR SWAP_ROUTER EDEN_CORE_IMPL
export EDEN_CORE_PROXY EDEN_ADMIN
export POOL_FACTORY NFT_POSITION_MANAGER
export POOL_IMPLEMENTATION LP_TOKEN_IMPLEMENTATION

forge script script/04_Configure.s.sol:ConfigureScript \
  --broadcast \
  --rpc-url "$RPC_URL" \
    --legacy \
  --gas-limit 60000000 \
  --private-key "$PRIVATE_KEY"

echo "✅ Batch 4 complete."

# ───────────────────────────────────────────────
# Save All Addresses
# ───────────────────────────────────────────────

echo "💾 Saving all deployment addresses..."

cat <<EOF > .env.core
NFT_RENDERER=$NFT_RENDERER
TAX_COLLECTOR=$TAX_COLLECTOR
SWAP_ROUTER=$SWAP_ROUTER
EDEN_CORE_IMPL=$EDEN_CORE_IMPL
EDEN_CORE_PROXY=$EDEN_CORE_PROXY
EDEN_ADMIN=$EDEN_ADMIN
POOL_FACTORY=$POOL_FACTORY
NFT_POSITION_MANAGER=$NFT_POSITION_MANAGER
POOL_IMPLEMENTATION=$POOL_IMPLEMENTATION
LP_TOKEN_IMPLEMENTATION=$LP_TOKEN_IMPLEMENTATION
EOF

cat <<EOF > deployments/core.json
{
  "NFT_RENDERER": "$NFT_RENDERER",
  "TAX_COLLECTOR": "$TAX_COLLECTOR",
  "SWAP_ROUTER": "$SWAP_ROUTER",
  "EDEN_CORE_IMPL": "$EDEN_CORE_IMPL",
  "EDEN_CORE_PROXY": "$EDEN_CORE_PROXY",
  "EDEN_ADMIN": "$EDEN_ADMIN",
  "POOL_FACTORY": "$POOL_FACTORY",
  "NFT_POSITION_MANAGER": "$NFT_POSITION_MANAGER",
  "POOL_IMPLEMENTATION": "$POOL_IMPLEMENTATION",
  "LP_TOKEN_IMPLEMENTATION": "$LP_TOKEN_IMPLEMENTATION"
}
EOF

# ───────────────────────────────────────────────
# Final Summary
# ───────────────────────────────────────────────

echo -e "\n🎉 EdenVest Deployment COMPLETE"
echo "🔑 All addresses saved to:"
echo "  → .env.core"
echo "  → deployments/core.json"

echo -e "\n📌 Deployed Contracts:"
echo "  - EdenCore Proxy:           $EDEN_CORE_PROXY"
echo "  - EdenCore Implementation:  $EDEN_CORE_IMPL"
echo "  - EdenAdmin:                $EDEN_ADMIN"
echo "  - TaxCollector:             $TAX_COLLECTOR"
echo "  - SwapRouter:               $SWAP_ROUTER"
echo "  - NFT Renderer:             $NFT_RENDERER"
echo "  - PoolFactory:              $POOL_FACTORY"
echo "  - NFTPositionManager:       $NFT_POSITION_MANAGER"
echo "  - Pool Implementation:      $POOL_IMPLEMENTATION"
echo "  - LP Token Implementation:  $LP_TOKEN_IMPLEMENTATION"

echo -e "\n✅ You're ready to create investment pools or launch to production."
