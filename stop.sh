#!/usr/bin/env bash
# stop.sh — Stop (or stop + remove) the OpenClaw Gateway containers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BOLD='\033[1m'; NC='\033[0m'

MODE="${1:-}"
case "$MODE" in
  ports)
    COMPOSE_FILES="-f docker-compose.yml"
    ;;
  tailscale)
    COMPOSE_FILES="-f docker-compose.yml -f docker-compose.tailscale.yml"
    ;;
  *)
    echo -e "${BOLD}Usage:${NC} ./stop.sh <mode> [--down]"
    echo ""
    echo "  ports       Stop in ports mode"
    echo "  tailscale   Stop in Tailscale mode"
    echo ""
    echo "  --down      Also remove containers and networks (docker compose down)"
    echo "              Default: docker compose stop (keeps containers)"
    echo ""
    exit 0
    ;;
esac

if [[ "${2:-}" == "--down" ]]; then
  docker compose $COMPOSE_FILES down
else
  docker compose $COMPOSE_FILES stop
fi
