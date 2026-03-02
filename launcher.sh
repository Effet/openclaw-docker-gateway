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

# If HTTPS_PROXY is set, route openclaw through proxychains4.
# Node.js native fetch (undici) does not respect HTTPS_PROXY natively.
PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
if [ -n "$PROXY" ]; then
    hp="${PROXY#*://}"   # strip scheme
    hp="${hp%%/*}"       # strip trailing path
    PHOST="${hp%:*}"
    PPORT="${hp##*:}"
    cat > /tmp/proxychains.conf << CONF
strict_chain
proxy_dns
[ProxyList]
http ${PHOST} ${PPORT}
CONF
    echo "[launcher] proxychains4 via ${PHOST}:${PPORT}"
    exec proxychains4 -f /tmp/proxychains.conf -q "$GCLAW" "$@"
fi

exec "$GCLAW" "$@"
