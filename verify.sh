#!/bin/bash
set -e


# Load .env (main) and .env.core (deployment addresses)
if [ -f .env ]; then
  source .env
fi

if [ -f .env.core ]; then
  source .env.core.$CHAIN_ID
fi


# REQUIRED ENV VARS CHECK
required_envs=(
  TREASURY_ADDRESS ADMIN_ADDRESS
  UNISWAP_ROUTER UNISWAP_QUOTER
  NFT_RENDERER TAX_COLLECTOR SWAP_ROUTER EDEN_CORE_IMPL
)

for var in "${required_envs[@]}"; do
  if [ -z "${!var}" ]; then
    echo "❌ ERROR: $var is not set in .env or .env.core"
    exit 1
  fi
done


# Setup chain RPC and blockscout config
ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY:-"dummy"} # Needed by forge
CHAIN_ID=${CHAIN_ID:-"42421"}
RPC_URL=${RPC_URL:-"https://enugu-rpc.assetchain.org/"}
VERIFIER=${VERIFIER}
VERIFIER_URL=${VERIFIER_URL}


# ✅ EdenPoolNFT - No constructor args
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  $NFT_RENDERER src/EdenPoolNFT.sol:EdenPoolNFT || echo "⚠️ EdenPoolNFT already verified or failed"

# ✅ TaxCollector - (treasury, admin, core = address(0))
constructor_tax=$(cast abi-encode "constructor(address,address,address)" $TREASURY_ADDRESS $ADMIN_ADDRESS 0x0000000000000000000000000000000000000000)
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  --constructor-args $constructor_tax \
  $TAX_COLLECTOR src/vest/TaxCollector.sol:TaxCollector || echo "⚠️ TaxCollector already verified or failed"

# ✅ SwapRouter - (uniswapRouter, uniswapQuoter, admin)
constructor_swap=$(cast abi-encode "constructor(address,address,address)" $UNISWAP_ROUTER $UNISWAP_QUOTER $ADMIN_ADDRESS)
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  --constructor-args $constructor_swap \
  $SWAP_ROUTER src/vest/SwapRouter.sol:EdenSwapRouter || echo "⚠️ EdenSwapRouter already verified or failed"

# ✅ EdenCore Impl - No constructor args
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  --constructor-args "" \
  $EDEN_CORE_IMPL src/vest/EdenVestCore.sol:EdenVestCore || echo "⚠️ EdenVestCore already verified or failed"

# ───────────────────────────────────────────────
# Batch 2: EdenCore Proxy and EdenAdmin
# ───────────────────────────────────────────────

# Verify EdenAdmin
constructor_admin=$(cast abi-encode "constructor(address,address,address[])" \
  $EDEN_CORE_PROXY \
  $ADMIN_ADDRESS \
  "[$ADMIN_ADDRESS,$MULTISIG_SIGNER_2,$MULTISIG_SIGNER_3]")

forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  --constructor-args $constructor_admin \
  $EDEN_ADMIN src/vest/EdenAdmin.sol:EdenAdmin || echo "⚠️ EdenAdmin already verified or failed"

echo "✅ Batch 2 verification complete."
# ───────────────────────────────────────────────
# Batch 3A: PoolFactory, InvestmentPool, LPToken
# ───────────────────────────────────────────────

# PoolFactory (constructor: address admin)
constructor_factory=$(cast abi-encode "constructor(address)" $ADMIN_ADDRESS)

forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  --constructor-args $constructor_factory \
  $POOL_FACTORY src/vest/PoolFactory.sol:PoolFactory || echo "⚠️ PoolFactory already verified or failed"

# InvestmentPool - No constructor args
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  --constructor-args "" \
  $POOL_IMPLEMENTATION src/vest/InvestmentPool.sol:InvestmentPool || echo "⚠️ InvestmentPool already verified or failed"

# LPToken - No constructor args
forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  --constructor-args "" \
  $LP_TOKEN_IMPLEMENTATION src/vest/LPToken.sol:LPToken || echo "⚠️ LPToken already verified or failed"

echo "✅ Batch 3A verification complete."

# ───────────────────────────────────────────────
# Batch 3B: NFTPositionManager
# ───────────────────────────────────────────────

# Encode constructor args for NFTPositionManager (renderer, admin)
constructor_nftpm=$(cast abi-encode "constructor(address,address)" $NFT_RENDERER $ADMIN_ADDRESS)

forge verify-contract \
  --rpc-url $RPC_URL \
  --verifier $VERIFIER \
  --verifier-url $VERIFIER_URL \
  --constructor-args $constructor_nftpm \
  $NFT_POSITION_MANAGER src/vest/NFTPositionManager.sol:NFTPositionManager || echo "⚠️ NFTPositionManager already verified or failed"

echo "✅ Batch 3B verification complete."

