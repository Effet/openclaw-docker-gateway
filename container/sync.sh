#!/bin/sh
# sync.sh — Commit and push workspace git repos to local bare repos.
# Run via: docker exec openclaw-gateway /home/node/scripts/sync.sh

[ -f /.dockerenv ] || { echo "Error: this script must run inside the container"; exit 1; }

SCRIPTS_DIR=/home/node/scripts
REPOS_DIR=/home/node/repos
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

sync_repo() {
  local dir="$1" name="$2"
  local bare_repo="${REPOS_DIR}/${name}.git"

  [ -d "$dir" ] || { echo "[sync] ${name}: directory not found, skipping"; return; }

  # Ensure bare repo exists
  if [ ! -d "$bare_repo" ]; then
    "$SCRIPTS_DIR/repos.sh" init "$name"
  fi

  cd "$dir"

  # Init git repo if needed
  if [ ! -d .git ]; then
    git init -q
    git config user.name "openclaw-sync"
    git config user.email "sync@local"
    echo "[sync] Initialized git repo in ${name}"
  fi

  # Set remote origin if not configured (don't override existing remotes)
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$bare_repo"
    echo "[sync] Remote origin → ${bare_repo}"
  fi

  # Commit if there are changes
  if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git commit -q -m "sync: ${TIMESTAMP}"
    echo "[sync] ${name} committed (${TIMESTAMP})"
  else
    echo "[sync] ${name}: nothing to commit"
  fi

  # Push to main branch
  if git push -q origin HEAD:main 2>/dev/null; then
    echo "[sync] ${name} pushed"
  else
    echo "[sync] ${name}: push failed (check remote)"
  fi
}

sync_repo /home/node/.openclaw/workspace "workspace"
sync_repo /home/node/workspaces "workspaces"
