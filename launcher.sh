#!/bin/sh
# Bootstrap & version selector.
# First run: npm install -g openclaw into the persisted toolchain volume.
# Subsequent runs: use the cached binary directly (fast).
# Hot-swap: ./update.sh [version]

export HOME=/home/node
export NPM_CONFIG_PREFIX=/home/node/.npm-global
export PATH="/home/node/.npm-global/bin:$PATH"

GCLAW=/home/node/.npm-global/bin/openclaw

if [ ! -x "$GCLAW" ]; then
    echo "[launcher] Installing openclaw (first run)..."
    npm install -g --no-fund --no-audit \
        ${NPM_REGISTRY:+--registry "$NPM_REGISTRY"} \
        openclaw || { echo "[launcher] Install failed, will retry"; exit 1; }
fi

echo "[launcher] OpenClaw $("$GCLAW" --version 2>/dev/null)"
exec "$GCLAW" "$@"
