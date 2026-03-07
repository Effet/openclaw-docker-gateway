#!/usr/bin/env bash
# backup.sh — Snapshot openclaw-config and commit workspace git repos.
#
# Usage:
#   ./backup.sh              # run once
#   crontab -e               # schedule (see README for example)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
GREEN='\033[0;32m'; NC='\033[0m'
ok() { echo -e "${GREEN}[✓]${NC} $*"; }

# ── 1. openclaw-config snapshot ────────────────────────────────────────────
mkdir -p backups
BACKUP_FILE="backups/openclaw-config-${TIMESTAMP}.tar.gz"
tar -czf "$BACKUP_FILE" --exclude='openclaw-config/logs' openclaw-config/
ok "Config snapshot → $BACKUP_FILE"

# ── 2. workspace git (via container) ───────────────────────────────────────
STATUS=$(docker inspect --format='{{.State.Status}}' openclaw-gateway 2>/dev/null || echo "not found")
if [ "$STATUS" = "running" ]; then
  docker exec openclaw-gateway /home/node/scripts/backup.sh
else
  echo "[!] Container not running — skipping workspace git backup"
fi
