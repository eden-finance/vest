#!/usr/bin/env bash
set -euo pipefail

# EdenVest — Extract Standard JSON (Foundry build-info) per contract
# Usage:
#   ./scripts/extract-stdjson.sh                            # build + export ALL contracts found
#   ./scripts/extract-stdjson.sh src/misc/Faucet.sol:EdenVestFaucet src/misc/Faucet.sol:FaucetToken
#
# Env:
#   SKIP_BUILD=1      # skip `forge build`
#   OUT_DIR=standard-json

OUT_DIR="${OUT_DIR:-standard-json}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "❌ Missing dependency: $1"; exit 1; }; }
need jq

if [[ -z "${SKIP_BUILD:-}" ]]; then
  echo "🧱 forge build --build-info --use-literal-content"
  forge clean >/dev/null 2>&1 || true
  forge build --build-info --use-literal-content -q
fi

mkdir -p "$OUT_DIR"

# Gather all build-info files
mapfile -t BUILDINFO_FILES < <(ls -1 out/build-info/*.json 2>/dev/null || true)
if [[ ${#BUILDINFO_FILES[@]} -eq 0 ]]; then
  echo "❌ No build-info files found. Did you run with --build-info?"
  exit 1
fi

# Helper: export one contract (path:Name) from a given build-info
export_one() {
  local bi="$1" spec="$2"
  local src="${spec%%:*}"
  local name="${spec#*:}"

  # Check presence in this build-info
  if ! jq -e --arg p "$src" --arg n "$name" '.output.contracts[$p][$n]' "$bi" >/dev/null; then
    return 1
  fi

  # File-friendly names
  local base
  base="$(basename "$src" .sol)"
  local safe_src="${src//\//__}"      # replace '/' with '__' for file naming
  local short="${name}"
  local full="${safe_src}___${name}"

  # Write inputs/outputs
  jq '.input' "$bi" > "$OUT_DIR/$full.input.json"
  jq '.output.contracts[$p][$n]' --arg p "$src" --arg n "$name" "$bi" > "$OUT_DIR/$full.output.json"

  # Metadata (useful for verif)
  jq '{solcVersion, settings: .input.settings}' "$bi" > "$OUT_DIR/$full.meta.json"

  # Also create convenient short names (may overwrite if duplicate names exist)
  cp "$OUT_DIR/$full.input.json"  "$OUT_DIR/$short.input.json"  2>/dev/null || true
  cp "$OUT_DIR/$full.output.json" "$OUT_DIR/$short.output.json" 2>/dev/null || true
  cp "$OUT_DIR/$full.meta.json"   "$OUT_DIR/$short.meta.json"   2>/dev/null || true

  echo "✅ $spec →"
  echo "   - $OUT_DIR/$full.input.json"
  echo "   - $OUT_DIR/$full.output.json"
  echo "   - $OUT_DIR/$full.meta.json"
}

# If specs passed as args, export exactly those
if [[ $# -gt 0 ]]; then
  for spec in "$@"; do
    found=0
    for bi in "${BUILDINFO_FILES[@]}"; do
      if export_one "$bi" "$spec"; then
        found=1
        break
      fi
    done
    if [[ $found -eq 0 ]]; then
      echo "⚠️  Not found in any build-info: $spec"
    fi
  done
  echo "🗂  Output in: $OUT_DIR"
  exit 0
fi

# No args: enumerate ALL contracts and export them
echo "🔎 Discovering all contracts from build-info…"
declare -A SEEN
for bi in "${BUILDINFO_FILES[@]}"; do
  # Get all path:contract pairs in this build-info
  mapfile -t pairs < <(jq -r '
    .output.contracts
    | to_entries[]
    | .key as $path
    | .value | keys[] as $name
    | "\($path):\($name)"
  ' "$bi")

  for spec in "${pairs[@]}"; do
    # Skip duplicates across build-infos
    if [[ -n "${SEEN[$spec]:-}" ]]; then continue; fi
    if export_one "$bi" "$spec"; then
      SEEN["$spec"]=1
    fi
  done
done

echo "🗂  All Standard JSON dumped to: $OUT_DIR"