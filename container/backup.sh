#!/bin/sh
# backup.sh (container-side) — git commit workspace and workspaces.
# Run via: docker exec openclaw-gateway /home/node/scripts/backup.sh

[ -f /.dockerenv ] || { echo "Error: this script must run inside the container"; exit 1; }

TIMESTAMP=$(date +%Y%m%d-%H%M%S)

backup_git_dir() {
  local dir="$1" label="$2"
  [ -d "$dir" ] || { echo "[backup] ${label}: not found, skipping"; return; }
  cd "$dir"
  if [ ! -d .git ]; then
    git init -q
    git config user.name "openclaw-backup"
    git config user.email "backup@local"
    echo "[backup] Initialized git repo in ${label}"
  fi
  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -q -m "backup: ${TIMESTAMP}"
    echo "[backup] ${label} committed (${TIMESTAMP})"
  else
    echo "[backup] ${label}: nothing to commit"
  fi
  if git remote get-url origin >/dev/null 2>&1; then
    git push -q
    echo "[backup] ${label} pushed to remote"
  fi
}

backup_git_dir /home/node/.openclaw/workspace "workspace"
backup_git_dir /home/node/workspaces "workspaces"
