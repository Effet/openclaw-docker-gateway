#!/bin/sh
# repos.sh — Manage bare git repos in /home/node/repos.
# Run via: docker exec openclaw-gateway /home/node/scripts/repos.sh <command> [name]
#
# Commands:
#   list              List all bare repos
#   init <name>       Initialize a new bare repo (name without .git)
#   delete <name>     Delete a bare repo

[ -f /.dockerenv ] || { echo "Error: this script must run inside the container"; exit 1; }

REPOS_DIR=/home/node/repos

case "${1:-}" in
  list)
    echo "Bare repos in ${REPOS_DIR}:"
    ls -1 "$REPOS_DIR" 2>/dev/null | grep '\.git$' || echo "  (none)"
    ;;
  init)
    [ -n "${2:-}" ] || { echo "Usage: repos.sh init <name>"; exit 1; }
    target="${REPOS_DIR}/${2}.git"
    [ -d "$target" ] && { echo "Already exists: ${target}"; exit 1; }
    git init --bare -q "$target"
    echo "Initialized: ${target}"
    echo "Remote URL:  /home/node/repos/${2}.git"
    ;;
  delete)
    [ -n "${2:-}" ] || { echo "Usage: repos.sh delete <name>"; exit 1; }
    target="${REPOS_DIR}/${2}.git"
    [ -d "$target" ] || { echo "Not found: ${target}"; exit 1; }
    rm -rf "$target"
    echo "Deleted: ${target}"
    ;;
  *)
    echo "Usage: repos.sh <list|init|delete> [name]"
    exit 1
    ;;
esac
