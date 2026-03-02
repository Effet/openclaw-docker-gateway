#!/usr/bin/env bash
# backup.sh — Snapshot openclaw-config and commit openclaw-workspace.
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
BACKUP_DIR="backups/openclaw-config-${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"
rsync -a openclaw-config/ "$BACKUP_DIR/"
ok "Config snapshot → $BACKUP_DIR"

# ── 2. openclaw-workspace git ──────────────────────────────────────────────
cd openclaw-workspace

if [ ! -d .git ]; then
  git init -q
  git config user.name "openclaw-backup"
  git config user.email "backup@local"
  ok "Initialized git repo in openclaw-workspace/"
fi

if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -q -m "backup: ${TIMESTAMP}"
  ok "Workspace committed (${TIMESTAMP})"
else
  ok "Workspace: nothing to commit"
fi

if git remote get-url origin &>/dev/null; then
  git push -q
  ok "Workspace pushed to remote"
fi
