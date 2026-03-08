#!/usr/bin/env bash
# backup.sh — Snapshot all openclaw data directories as tar.gz.
# Excludes runtime logs. Includes .git dirs for disaster recovery.
#
# Usage:
#   ./backup.sh              # run once
#   crontab -e               # schedule (see README for example)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

mkdir -p backups

BACKUP_FILE="backups/openclaw-${TIMESTAMP}.tar.gz"

# Collect directories that exist
DIRS=()
for dir in openclaw-config openclaw-workspace openclaw-workspaces openclaw-repos; do
  if [ -d "$dir" ]; then
    DIRS+=("${dir}/")
  else
    warn "${dir}/ not found, skipping"
  fi
done

if [ ${#DIRS[@]} -eq 0 ]; then
  warn "No directories to backup"
  exit 0
fi

tar -czf "$BACKUP_FILE" \
  --exclude='*/logs' \
  --exclude='*/logs/*' \
  "${DIRS[@]}"

ok "Snapshot → ${BACKUP_FILE}"
