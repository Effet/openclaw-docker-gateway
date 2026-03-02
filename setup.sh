#!/usr/bin/env bash
# setup.sh — Start OpenClaw Gateway in Docker.
# API keys and channels are configured via: docker compose run --rm -it openclaw onboard
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; }
heading() { echo -e "\n${BOLD}$*${NC}"; }

# ── Prerequisites ─────────────────────────────────────────────────────────────
heading "Checking prerequisites..."
command -v docker &>/dev/null || { error "Docker not found"; exit 1; }
docker compose version &>/dev/null || { error "Docker Compose plugin not found"; exit 1; }
info "Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"

# ── Directories ───────────────────────────────────────────────────────────────
heading "Preparing directories..."
mkdir -p openclaw-config openclaw-workspace toolchain
info "openclaw-config/    (gateway config & state)"
info "openclaw-workspace/ (agent workspace)"
info "toolchain/          (npm global prefix — persists across restarts)"

# ── Compose files ─────────────────────────────────────────────────────────────
COMPOSE_FILES="-f docker-compose.yml"
if [[ -f .env.tailscale ]]; then
  COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.tailscale.yml"
  info "Tailscale mode detected (.env.tailscale found)"
fi

# ── Start ─────────────────────────────────────────────────────────────────────
heading "Starting container..."
docker compose $COMPOSE_FILES up -d --build

info "Waiting for gateway to become healthy..."
info "First run installs openclaw via npm (~2 min). Subsequent starts are fast."

TIMEOUT=180; ELAPSED=0
while true; do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' openclaw-gateway 2>/dev/null || echo "unknown")
  [[ "$STATUS" == "healthy" ]] && break
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    error "Gateway did not become healthy within ${TIMEOUT}s (status: ${STATUS})"
    docker compose $COMPOSE_FILES logs --tail=20
    exit 1
  fi
  sleep 5; ELAPSED=$((ELAPSED + 5)); echo -n "."
done
echo ""
info "Gateway is healthy"

# ── Onboarding hint ───────────────────────────────────────────────────────────
if [[ ! -s openclaw-config/openclaw.json ]]; then
  echo ""
  warn "No config found — run the onboarding wizard to set up API keys and channels:"
  echo ""
  echo -e "  ${BOLD}docker compose $COMPOSE_FILES run --rm -it openclaw onboard${NC}"
  echo ""
fi

heading "Done"
echo "  Onboard  : docker compose $COMPOSE_FILES run --rm -it openclaw onboard"
echo "  Shell    : docker exec -it openclaw-gateway bash"
echo "  Logs     : docker compose $COMPOSE_FILES logs -f"
echo "  Update   : ./update.sh [version]"
echo "  Test     : ./test.sh"
echo ""
