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

# ── 2. git backup helper ────────────────────────────────────────────────────
# Usage: backup_git_dir <dir> <label>
backup_git_dir() {
  local dir="$1" label="$2"

  [ -d "$dir" ] || { ok "${label}: directory not found, skipping"; return; }

  cd "$SCRIPT_DIR/$dir"

  if [ ! -d .git ]; then
    git init -q
    git config user.name "openclaw-backup"
    git config user.email "backup@local"
    ok "Initialized git repo in ${dir}/"
  fi

  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -q -m "backup: ${TIMESTAMP}"
    ok "${label} committed (${TIMESTAMP})"
  else
    ok "${label}: nothing to commit"
  fi

  if git remote get-url origin &>/dev/null; then
    git push -q
    ok "${label} pushed to remote"
  fi

  cd "$SCRIPT_DIR"
}

# ── 3. openclaw-workspace ───────────────────────────────────────────────────
backup_git_dir "openclaw-workspace" "workspace"

# ── 4. openclaw-workspaces ──────────────────────────────────────────────────
backup_git_dir "openclaw-workspaces" "workspaces"
