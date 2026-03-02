#!/usr/bin/env bash
# restart.sh — Restart the OpenClaw process or the whole container.
#
# Default (no --full): restarts only the openclaw process via supervisorctl.
# Useful after config changes; the container keeps running.
#
# --full <mode>: restarts the entire container via docker compose.
# Needed only if supervisord.conf or Dockerfile-level settings change.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOLD='\033[1m'; GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[✓]${NC} $*"; }

if [[ "${1:-}" == "--full" ]]; then
  MODE="${2:-}"
  case "$MODE" in
    ports)     COMPOSE_FILES="-f docker-compose.yml" ;;
    tailscale) COMPOSE_FILES="-f docker-compose.yml -f docker-compose.tailscale.yml" ;;
    *)
      echo -e "${BOLD}Usage:${NC} ./restart.sh [--full <ports|tailscale>]"
      echo ""
      echo "  (no args)             Restart openclaw process via supervisorctl (fast)"
      echo "  --full ports          Restart entire container in ports mode"
      echo "  --full tailscale      Restart entire container in Tailscale mode"
      echo ""
      exit 0
      ;;
  esac
  docker compose $COMPOSE_FILES restart openclaw
  info "Container restarted"
else
  if ! docker inspect openclaw-gateway --format='{{.State.Status}}' 2>/dev/null | grep -q running; then
    echo "Error: openclaw-gateway is not running." >&2
    exit 1
  fi
  docker exec openclaw-gateway supervisorctl restart openclaw
  info "openclaw process restarted"
fi
