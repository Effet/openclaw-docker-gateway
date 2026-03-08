#!/bin/sh
# autosync.sh — Periodically sync workspace git repos inside the container.
# Interval is controlled by SYNC_INTERVAL env var (seconds, default 300).

INTERVAL="${SYNC_INTERVAL:-300}"
SCRIPTS_DIR=/home/node/scripts

echo "[autosync] Starting — interval=${INTERVAL}s"

while true; do
  "$SCRIPTS_DIR/sync.sh"
  sleep "$INTERVAL"
done
