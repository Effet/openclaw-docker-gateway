#!/usr/bin/env bash
# update.sh — Hot-swap OpenClaw to a new version without rebuilding the image.
#
# Usage:
#   ./update.sh              # install latest openclaw
#   ./update.sh 2026.2.26    # install a specific version
#
# How it works:
#   Runs 'npm install -g openclaw@VERSION' inside the running container,
#   writing the package into the persisted ./toolchain volume.
#   On next restart, launcher.sh will automatically pick up the new version.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
heading() { echo -e "\n${BOLD}$*${NC}"; }

VERSION="${1:-latest}"

COMPOSE_FILES="-f docker-compose.yml"
[[ -f .env.tailscale ]] && COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.tailscale.yml"

# ── Preflight ─────────────────────────────────────────────────────────────────
heading "OpenClaw Update — target: ${VERSION}"

CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' openclaw-gateway 2>/dev/null || echo "not found")
if [[ "$CONTAINER_STATUS" != "running" ]]; then
  error "Container 'openclaw-gateway' is not running (status: ${CONTAINER_STATUS})"
  error "Start it first with: ./setup.sh"
  exit 1
fi

# Show currently active version
GCLAW=/home/node/.npm-global/bin/openclaw
CURRENT_GLOBAL=$(docker exec openclaw-gateway sh -c "[ -x '$GCLAW' ] && '$GCLAW' --version 2>/dev/null || echo '(none)'")
info "Current toolchain version: ${CURRENT_GLOBAL}"

# ── Install ───────────────────────────────────────────────────────────────────
heading "Installing openclaw@${VERSION} into toolchain volume..."

docker exec \
  -e NPM_CONFIG_PREFIX=/home/node/.npm-global \
  openclaw-gateway \
  npm install -g --no-fund --no-audit "openclaw@${VERSION}"

NEW_VERSION=$(docker exec openclaw-gateway sh -c "NPM_CONFIG_PREFIX=/home/node/.npm-global /home/node/.npm-global/bin/openclaw --version 2>/dev/null || echo 'unknown'")
info "Installed: ${NEW_VERSION}"

# ── Restart ───────────────────────────────────────────────────────────────────
heading "Restarting gateway to activate new version..."
docker compose $COMPOSE_FILES restart openclaw

# Wait for healthy
TIMEOUT=60
ELAPSED=0
while true; do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' openclaw-gateway 2>/dev/null || echo "unknown")
  [[ "$STATUS" == "healthy" ]] && break
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    error "Gateway did not become healthy after restart (status: ${STATUS})"
    echo "Check logs: docker compose $COMPOSE_FILES logs -f"
    exit 1
  fi
  sleep 3; ELAPSED=$((ELAPSED + 3)); echo -n "."
done
echo ""

# Verify the new version is live (launcher.sh logs it on startup)
ACTIVE=$(docker logs openclaw-gateway 2>&1 | grep "\[launcher\]" | tail -1)
info "Active: ${ACTIVE:-<see container logs>}"

heading "Done"
echo ""
echo "  Toolchain version : ${NEW_VERSION}"
echo "  Run ./test.sh to verify."
echo ""
