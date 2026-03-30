#!/usr/bin/env bash
# Wipe, rebuild, and redeploy the entire localnet environment.
# Outputs the env vars needed to run Sigil against localnet.
#
# Usage:
#   ./scripts/localnet-reset.sh              # Full reset (wipe + redeploy everything)
#   ./scripts/localnet-reset.sh --sigil-only  # Republish Sigil contracts only (chain state preserved)
#
# Requires: sudo (for Docker), jq, base64, xxd
set -euo pipefail

SCAFFOLD_DIR="${BUILDER_SCAFFOLD_DIR:-$HOME/builder-scaffold}"
DOCKER_DIR="$SCAFFOLD_DIR/docker"
SIGIL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="docker-sui-dev-1"
INIT_WAIT="${LOCALNET_INIT_WAIT:-25}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

step() { echo -e "\n${CYAN}==>${NC} ${BOLD}$1${NC}"; }
ok()   { echo -e "    ${GREEN}OK${NC} $1"; }
warn() { echo -e "    ${YELLOW}!!${NC} $1"; }
fail() { echo -e "    ${RED}FAIL${NC} $1"; exit 1; }

# --- Pre-flight checks ---
for cmd in jq base64 xxd; do
  command -v $cmd &>/dev/null || fail "Missing required command: $cmd"
done
[ -d "$DOCKER_DIR" ] || fail "builder-scaffold not found at $SCAFFOLD_DIR"

MODE="full"
[[ "${1:-}" == "--sigil-only" ]] && MODE="sigil-only"

# ═══════════════════════════════════════════════════════════════
# Full reset: wipe volumes, restart containers, deploy everything
# ═══════════════════════════════════════════════════════════════
if [ "$MODE" = "full" ]; then
  step "Stopping containers and wiping volumes"
  cd "$DOCKER_DIR"
  sudo docker compose down -v 2>&1 | tail -1
  sudo docker system prune -f --volumes 2>&1 | tail -1
  ok "Docker cleaned"

  step "Starting fresh containers"
  sudo docker compose up -d 2>&1 | tail -1
  ok "Containers started"

  step "Waiting ${INIT_WAIT}s for Sui node initialization"
  sleep "$INIT_WAIT"

  # Verify both containers are healthy
  if ! sudo docker ps --filter "name=$CONTAINER" --format '{{.Status}}' | grep -q "Up"; then
    fail "sui-dev container not running"
  fi
  for attempt in 1 2 3; do
    if sudo docker ps --filter "name=docker-postgres" --format '{{.Status}}' | grep -q "healthy"; then
      break
    fi
    [ "$attempt" -eq 3 ] && fail "postgres container not healthy after 15s"
    sleep 5
  done
  ok "Both containers healthy"
fi

# ═══════════════════════════════════════════════════════════════
# Sigil-only: just republish Sigil contracts on existing chain
# ═══════════════════════════════════════════════════════════════
if [ "$MODE" = "sigil-only" ]; then
  step "Sigil-only mode — checking container"
  if ! sudo docker ps --filter "name=$CONTAINER" --format '{{.Status}}' | grep -q "Up"; then
    fail "sui-dev container not running. Run without --sigil-only first."
  fi
  ok "Container is running"
fi

# --- Extract wallet keys (both modes need this) ---
step "Extracting wallet keys"

ADMIN_ADDR=$(sudo docker exec "$CONTAINER" sui client active-address 2>/dev/null)
ADMIN_PRIVKEY=$(sudo docker exec "$CONTAINER" sui keytool export --key-identity ADMIN --json 2>/dev/null \
  | jq -r '.exportedPrivateKey')
PLAYER_A_PRIVKEY=$(sudo docker exec "$CONTAINER" sui keytool export --key-identity PLAYER_A --json 2>/dev/null \
  | jq -r '.exportedPrivateKey')
PLAYER_B_PRIVKEY=$(sudo docker exec "$CONTAINER" sui keytool export --key-identity PLAYER_B --json 2>/dev/null \
  | jq -r '.exportedPrivateKey')
PLAYER_A_ADDR=$(sudo docker exec "$CONTAINER" bash -c "sui keytool list --json 2>/dev/null" \
  | jq -r '.[] | select(.alias == "PLAYER_A") | .suiAddress')
PLAYER_B_ADDR=$(sudo docker exec "$CONTAINER" bash -c "sui keytool list --json 2>/dev/null" \
  | jq -r '.[] | select(.alias == "PLAYER_B") | .suiAddress')

ok "ADMIN:    $ADMIN_ADDR"
ok "PLAYER_A: $PLAYER_A_ADDR"
ok "PLAYER_B: $PLAYER_B_ADDR"

# --- Full mode: deploy world, configure, seed ---
if [ "$MODE" = "full" ]; then
  # Update .env inside container
  sudo docker exec "$CONTAINER" bash -c "cat > /workspace/world-contracts/.env << ENVEOF
SUI_NETWORK=localnet
GOVERNOR_PRIVATE_KEY=$ADMIN_PRIVKEY
ADMIN_ADDRESS=$ADMIN_ADDR
SPONSOR_ADDRESSES=$ADMIN_ADDR
ADMIN_PRIVATE_KEY=$ADMIN_PRIVKEY
PLAYER_A_PRIVATE_KEY=$PLAYER_A_PRIVKEY
PLAYER_B_PRIVATE_KEY=$PLAYER_B_PRIVKEY
TENANT=dev
FUEL_TYPE_IDS=78437,78515,78516,84868,88319,88335
FUEL_EFFICIENCIES=90,80,40,40,15,10
ASSEMBLY_TYPE_IDS=77917,84556,84955,87119,87120,88063,88064,88067,88068,88069,88070,88071,88082,88083,90184,91978,92279,92401,92404
ENERGY_REQUIRED_VALUES=500,10,950,50,250,100,200,100,200,100,200,300,50,100,1,100,10,20,40
WORLD_PACKAGE_ID=
BUILDER_PACKAGE_ID=
GATE_TYPE_IDS=88086,84955
MAX_DISTANCES=520340175991902420,1040680351983804840
ENVEOF"
  ok ".env updated"

  step "Deploying world contracts"
  sudo docker exec "$CONTAINER" bash -c "cd /workspace/world-contracts && pnpm deploy-world localnet" 2>&1 \
    | grep -E '(Wrote|Deployed|Error)' || true

  step "Configuring world (fuel, energy, gates)"
  sudo docker exec "$CONTAINER" bash -c "cd /workspace/world-contracts && pnpm configure-world localnet" 2>&1 \
    | grep -E '(complete|Error)' || true
  ok "World configured"

  step "Seeding test resources (characters, assemblies)"
  SEED_OUTPUT=$(sudo docker exec "$CONTAINER" bash -c \
    "cd /workspace/world-contracts && pnpm create-test-resources localnet" 2>&1)

  CHAR_A=$(echo "$SEED_OUTPUT" | grep -A1 "Game Character ID: 811880" | grep "Pre-computed Character ID" \
    | sed 's/.*: //' || echo "unknown")
  CHAR_B=$(echo "$SEED_OUTPUT" | grep -A1 "Game Character ID: 900000001" | grep "Pre-computed Character ID" \
    | sed 's/.*: //' || echo "unknown")
  GATE_1=$(echo "$SEED_OUTPUT" | grep "Gate Object Id:" | head -1 | sed 's/.*: //' || echo "unknown")
  GATE_2=$(echo "$SEED_OUTPUT" | grep "Gate Object Id:" | tail -1 | sed 's/.*: //' || echo "unknown")
  NWN_ID=$(echo "$SEED_OUTPUT" | grep "NWN Object Id:" | sed 's/.*: //' | tr -d '[:space:]' || echo "unknown")
  SSU_ID=$(echo "$SEED_OUTPUT" | grep "Storage Unit Object Id:" | sed 's/.*: //' | tr -d '[:space:]' || echo "unknown")
  ok "Seeded"

  # --- Seed additional UAT world objects ---
  step "Extracting world object IDs for UAT seeding"
  REGISTRY_ID=$(sudo docker exec "$CONTAINER" jq -r '.world.objectRegistry' \
    /workspace/world-contracts/deployments/localnet/extracted-object-ids.json 2>/dev/null || echo "")
  ACL_ID=$(sudo docker exec "$CONTAINER" jq -r '.world.adminAcl' \
    /workspace/world-contracts/deployments/localnet/extracted-object-ids.json 2>/dev/null || echo "")

  if [ -n "$REGISTRY_ID" ] && [ "$REGISTRY_ID" != "null" ]; then
    ok "Registry: $REGISTRY_ID"
    ok "AdminACL: $ACL_ID"

    step "Seeding additional UAT world objects (extra characters + assemblies)"
    sudo docker cp "$SIGIL_DIR/scripts/seed-uat-world-objects.ts" \
      "$CONTAINER:/workspace/world-contracts/ts-scripts/seed-uat-world-objects.ts"

    UAT_OUTPUT=$(sudo docker exec "$CONTAINER" bash -c "
      cd /workspace/world-contracts
      export WORLD_OBJECT_REGISTRY=$REGISTRY_ID
      export ADMIN_ACL=$ACL_ID
      export PLAYER_A_ADDRESS=$PLAYER_A_ADDR
      export PLAYER_B_ADDRESS=$PLAYER_B_ADDR
      export ADMIN_ADDRESS=$ADMIN_ADDR
      export CHAR_A_ID=$CHAR_A
      export CHAR_B_ID=$CHAR_B
      export NWN_ID=$NWN_ID
      npx tsx ts-scripts/seed-uat-world-objects.ts 2>/dev/null
    " 2>&1 || true)

    # Parse all IDs from UAT script output (more reliable than grepping basic seed stdout)
    CHAR_A=$(echo "$UAT_OUTPUT" | grep "^CHAR_A1=" | cut -d= -f2 || true)
    CHAR_B=$(echo "$UAT_OUTPUT" | grep "^CHAR_B1=" | cut -d= -f2 || true)
    CHAR_A2=$(echo "$UAT_OUTPUT" | grep "^CHAR_A2=" | cut -d= -f2 || true)
    CHAR_C1=$(echo "$UAT_OUTPUT" | grep "^CHAR_C1=" | cut -d= -f2 || true)
    NWN_ID=$(echo "$UAT_OUTPUT" | grep "^NWN_A=" | cut -d= -f2 || true)
    NWN_B=$(echo "$UAT_OUTPUT" | grep "^NWN_B=" | cut -d= -f2 || true)
    TURRET_A=$(echo "$UAT_OUTPUT" | grep "^TURRET_A=" | cut -d= -f2 || true)
    GATE_B=$(echo "$UAT_OUTPUT" | grep "^GATE_B=" | cut -d= -f2 || true)

    if [ -n "$CHAR_A2" ]; then
      ok "char_a1 (tribe 100): $CHAR_A"
      ok "char_b1 (tribe 100): $CHAR_B"
      ok "char_a2 (tribe 999): $CHAR_A2"
      ok "char_c1 (tribe 200): $CHAR_C1"
      ok "NWN_B (PLAYER_B):   $NWN_B"
      ok "TURRET_A:           $TURRET_A"
      ok "GATE_B (PLAYER_B):  $GATE_B"
    else
      warn "UAT world object seeding failed — continuing without extras"
      warn "Output: $UAT_OUTPUT"
    fi
  else
    warn "Could not extract registry/ACL IDs — skipping UAT world objects"
  fi
fi

# --- Get world package ID (both modes) ---
WORLD_PKG=$(sudo docker exec "$CONTAINER" bash -c \
  "jq -r '.world.packageId' /workspace/world-contracts/deployments/localnet/extracted-object-ids.json 2>/dev/null" \
  || echo "")
[ "$WORLD_PKG" != "null" ] && [ -n "$WORLD_PKG" ] || fail "No world package ID found. Run full reset first."
ok "World package: $WORLD_PKG"

# --- Publish Sigil contracts (both modes) ---
step "Publishing Sigil contracts"

sudo docker exec "$CONTAINER" rm -rf /workspace/sigil-contracts 2>/dev/null || true
sudo docker cp "$SIGIL_DIR/contracts" "$CONTAINER:/workspace/sigil-contracts"
# Remove lock/build/deps artifacts that pin testnet dependency paths
sudo docker exec "$CONTAINER" bash -c \
  "cd /workspace/sigil-contracts && rm -rf deps build Move.lock Published.toml Pub.*.toml" 2>/dev/null || true

sudo docker exec "$CONTAINER" bash -c "cd /workspace/sigil-contracts && cat > Move.toml << MOVEEOF
[package]
name = \"sigil\"
edition = \"2024\"

[dependencies]
world = { local = \"/workspace/world-contracts/contracts/world\" }
MOVEEOF"

# Link sigil against the already-published world package via --pubfile-path.
# The world deploy script uses --build-env testnet (system env), so we match that.
# Copy the world Pub file and strip any previous sigil entries (test-publish appends to it).
WORLD_PUBFILE="/workspace/world-contracts/contracts/world/Pub.localnet.toml"
sudo docker exec "$CONTAINER" bash -c "
  python3 << 'PYEOF'
text = open('$WORLD_PUBFILE').read()
parts = text.split('[[published]]')
if len(parts) >= 2:
    with open('/tmp/world-pub.toml', 'w') as f:
        f.write(parts[0] + '[[published]]' + parts[1])
else:
    import shutil; shutil.copy('$WORLD_PUBFILE', '/tmp/world-pub.toml')
PYEOF"

sudo docker exec "$CONTAINER" bash -c \
  "cd /workspace/sigil-contracts && sui client test-publish --build-env testnet --gas-budget 5000000000 --pubfile-path /tmp/world-pub.toml" \
  2>&1 | grep -E '(Transaction Digest|BUILDING|Error)' || true

# Extract sigil package ID from the pubfile (test-publish appends the sigil entry)
SIGIL_PKG=$(sudo docker exec "$CONTAINER" bash -c \
  "grep 'published-at' /tmp/world-pub.toml | tail -1" \
  | sed 's/.*= "//' | sed 's/"//')
[ -n "$SIGIL_PKG" ] || fail "Sigil publish failed"
ok "Sigil package: $SIGIL_PKG"

# --- Extract signer key ---
step "Extracting PLAYER_A signer key (hex)"

SIGNER_KEY=$(sudo docker exec "$CONTAINER" bash -c "cd /workspace/world-contracts && node -e \"
const { decodeSuiPrivateKey } = require('@mysten/sui/cryptography');
const decoded = decodeSuiPrivateKey('$PLAYER_A_PRIVKEY');
console.log(Buffer.from(decoded.secretKey).toString('hex'));
\"" 2>/dev/null)
[ -n "$SIGNER_KEY" ] || fail "Could not extract signer key"
ok "Signer key extracted (PLAYER_A)"

# Extract ADMIN and PLAYER_B hex keys for Sigil seed task
ADMIN_KEY_HEX=$(sudo docker exec "$CONTAINER" bash -c "cd /workspace/world-contracts && node -e \"
const { decodeSuiPrivateKey } = require('@mysten/sui/cryptography');
const decoded = decodeSuiPrivateKey('$ADMIN_PRIVKEY');
console.log(Buffer.from(decoded.secretKey).toString('hex'));
\"" 2>/dev/null)

PLAYER_B_KEY_HEX=$(sudo docker exec "$CONTAINER" bash -c "cd /workspace/world-contracts && node -e \"
const { decodeSuiPrivateKey } = require('@mysten/sui/cryptography');
const decoded = decodeSuiPrivateKey('$PLAYER_B_PRIVKEY');
console.log(Buffer.from(decoded.secretKey).toString('hex'));
\"" 2>/dev/null)

ok "ADMIN + PLAYER_B hex keys extracted"

# --- Verify GraphQL ---
step "Verifying GraphQL indexer"
for i in 1 2 3 4 5; do
  if curl -sf http://localhost:9125/graphql -H 'Content-Type: application/json' \
    -d '{"query": "{ chainIdentifier }"}' &>/dev/null; then
    ok "GraphQL responding at localhost:9125"
    break
  fi
  [ "$i" -eq 5 ] && warn "GraphQL not responding yet — indexer may still be catching up"
  sleep 3
done

# ═══════════════════════════════════════════════════════════════
# Sigil Database + On-Chain Seeding
# ═══════════════════════════════════════════════════════════════
if [ "$MODE" = "full" ]; then
  step "Resetting and seeding Sigil database"
  cd "$SIGIL_DIR"

  # Set env for Mix task
  export SUI_LOCALNET_PACKAGE_ID="$WORLD_PKG"
  export SUI_LOCALNET_SIGIL_PACKAGE_ID="$SIGIL_PKG"
  export SUI_LOCALNET_SIGNER_KEY="$SIGNER_KEY"
  export EVE_WORLD=localnet

  mix ecto.reset 2>&1 | grep -v "^$" || true
  ok "Database reset"

  if [ -n "${CHAR_A2:-}" ] && [ -n "${CHAR_C1:-}" ]; then
    step "Seeding Sigil on-chain objects and database records"
    export SEED_CHAR_A1="${CHAR_A:-}"
    export SEED_CHAR_B1="${CHAR_B:-}"
    export SEED_CHAR_C1="${CHAR_C1:-}"
    export SEED_GATE_1="${GATE_1:-}"
    export SEED_GATE_2="${GATE_2:-}"
    export SEED_NWN="${NWN_ID:-}"
    export SEED_SSU="${SSU_ID:-}"
    export SEED_TURRET="${TURRET_A:-}"
    export SEED_GATE_B="${GATE_B:-}"
    export SEED_NWN_B="${NWN_B:-}"
    export SEED_PLAYER_A_ADDR="$PLAYER_A_ADDR"
    export SEED_PLAYER_B_ADDR="$PLAYER_B_ADDR"
    export SEED_ADMIN_ADDR="$ADMIN_ADDR"
    export SEED_ADMIN_KEY_HEX="$ADMIN_KEY_HEX"
    export SEED_PLAYER_B_KEY_HEX="$PLAYER_B_KEY_HEX"

    if mix sigil.seed_localnet 2>&1; then
      ok "Sigil seeding complete"
    else
      warn "Sigil seeding failed — database records may be incomplete"
    fi
  else
    warn "Skipping Sigil seeding — UAT world objects were not created"
  fi
fi

# ═══════════════════════════════════════════════════════════════
# Output
# ═══════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  Localnet Ready${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}Run Sigil:${NC}"
echo ""
echo "  source .env.localnet && EVE_WORLD=localnet iex -S mix phx.server"
echo ""
echo -e "${BOLD}Environment Variables:${NC}"
echo ""
echo "  export SUI_LOCALNET_PACKAGE_ID=$WORLD_PKG"
echo "  export SUI_LOCALNET_SIGIL_PACKAGE_ID=$SIGIL_PKG"
echo "  export SUI_LOCALNET_SIGNER_KEY=$SIGNER_KEY"
echo ""
echo -e "${BOLD}Wallets (import PLAYER_A into Slush):${NC}"
echo ""
printf "  %-10s %-66s %s\n" "ADMIN" "$ADMIN_ADDR" "$ADMIN_PRIVKEY"
printf "  %-10s %-66s %s\n" "PLAYER_A" "$PLAYER_A_ADDR" "$PLAYER_A_PRIVKEY"
printf "  %-10s %-66s %s\n" "PLAYER_B" "$PLAYER_B_ADDR" "$PLAYER_B_PRIVKEY"

if [ "$MODE" = "full" ]; then
  echo ""
  echo -e "${BOLD}Characters:${NC}"
  echo ""
  printf "  %-10s %-66s ID: %-10s Tribe: %s\n" "PLAYER_A" "${CHAR_A:-unknown}" "811880" "100"
  printf "  %-10s %-66s ID: %-10s Tribe: %s\n" "PLAYER_A" "${CHAR_A2:-unknown}" "811881" "999 (no custodian)"
  printf "  %-10s %-66s ID: %-10s Tribe: %s\n" "PLAYER_B" "${CHAR_B:-unknown}" "900000001" "100"
  printf "  %-10s %-66s ID: %-10s Tribe: %s\n" "ADMIN" "${CHAR_C1:-unknown}" "900000002" "200"
  echo ""
  echo -e "${BOLD}Assets (PLAYER_A):${NC}"
  echo ""
  printf "  %-12s %s\n" "Gate 1" "${GATE_1:-unknown}"
  printf "  %-12s %s\n" "Gate 2" "${GATE_2:-unknown}"
  printf "  %-12s %s\n" "NetworkNode" "${NWN_ID:-unknown}"
  printf "  %-12s %s\n" "StorageUnit" "${SSU_ID:-unknown}"
  printf "  %-12s %s\n" "Turret" "${TURRET_A:-unknown}"
  echo ""
  echo -e "${BOLD}Assets (PLAYER_B):${NC}"
  echo ""
  printf "  %-12s %s\n" "NetworkNode" "${NWN_B:-unknown}"
  printf "  %-12s %s\n" "Gate" "${GATE_B:-unknown}"
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"

# --- Write .env.localnet ---
ENV_FILE="$SIGIL_DIR/.env.localnet"
cat > "$ENV_FILE" << EOF
# Auto-generated by scripts/localnet-reset.sh — $(date -Iseconds)
# Usage: source .env.localnet && EVE_WORLD=localnet iex -S mix phx.server

export SUI_LOCALNET_PACKAGE_ID=$WORLD_PKG
export SUI_LOCALNET_SIGIL_PACKAGE_ID=$SIGIL_PKG
export SUI_LOCALNET_SIGNER_KEY=$SIGNER_KEY

# Wallets (import PLAYER_A into Slush for browser testing)
# ADMIN:    $ADMIN_ADDR — $ADMIN_PRIVKEY
# PLAYER_A: $PLAYER_A_ADDR — $PLAYER_A_PRIVKEY
# PLAYER_B: $PLAYER_B_ADDR — $PLAYER_B_PRIVKEY
EOF

if [ "$MODE" = "full" ]; then
  cat >> "$ENV_FILE" << EOF

# Characters
# PLAYER_A char_a1: ${CHAR_A:-unknown} (ID: 811880, Tribe: 100)
# PLAYER_A char_a2: ${CHAR_A2:-unknown} (ID: 811881, Tribe: 999 — no custodian)
# PLAYER_B char_b1: ${CHAR_B:-unknown} (ID: 900000001, Tribe: 100)
# ADMIN    char_c1: ${CHAR_C1:-unknown} (ID: 900000002, Tribe: 200)

# Assets (PLAYER_A)
# Gate 1:      ${GATE_1:-unknown}
# Gate 2:      ${GATE_2:-unknown}
# NetworkNode: ${NWN_ID:-unknown}
# StorageUnit: ${SSU_ID:-unknown}
# Turret:      ${TURRET_A:-unknown}

# Assets (PLAYER_B)
# NetworkNode: ${NWN_B:-unknown}
# Gate:        ${GATE_B:-unknown}

# UAT seed env vars (for mix sigil.seed_localnet)
export SEED_CHAR_A1="${CHAR_A:-}"
export SEED_CHAR_A2="${CHAR_A2:-}"
export SEED_CHAR_B1="${CHAR_B:-}"
export SEED_CHAR_C1="${CHAR_C1:-}"
export SEED_GATE_1="${GATE_1:-}"
export SEED_GATE_2="${GATE_2:-}"
export SEED_NWN="${NWN_ID:-}"
export SEED_SSU="${SSU_ID:-}"
export SEED_TURRET="${TURRET_A:-}"
export SEED_GATE_B="${GATE_B:-}"
export SEED_NWN_B="${NWN_B:-}"
export SEED_PLAYER_A_ADDR="$PLAYER_A_ADDR"
export SEED_PLAYER_B_ADDR="$PLAYER_B_ADDR"
export SEED_ADMIN_ADDR="$ADMIN_ADDR"
export SEED_ADMIN_KEY_HEX="$ADMIN_KEY_HEX"
export SEED_PLAYER_B_KEY_HEX="$PLAYER_B_KEY_HEX"
EOF
fi

ok "Wrote $ENV_FILE"
