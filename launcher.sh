#!/bin/sh
# Bootstrap & version selector.
# First run: npm install -g openclaw into the persisted toolchain volume.
# Subsequent runs: use the cached binary directly (fast).
# Hot-swap: ./update.sh [version]

export HOME=/home/node
export NPM_CONFIG_PREFIX=/home/node/.npm-global
export PATH="/home/node/.npm-global/bin:$PATH"

# PROXY=scheme://[user:pass@]host:port  →  propagate to standard vars for npm etc.
if [ -n "${PROXY:-}" ]; then
    export HTTPS_PROXY="$PROXY"
    export HTTP_PROXY="$PROXY"
fi

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
# Supported formats:
#   http://host:port
#   socks5://host:port
#   http://user:pass@host:port
PROXY="${HTTPS_PROXY:-${https_proxy:-}}"
if [ -n "$PROXY" ]; then
    SCHEME="${PROXY%%://*}"
    rest="${PROXY#*://}"
    # Extract optional user:pass
    if echo "$rest" | grep -q '@'; then
        auth="${rest%@*}"; rest="${rest#*@}"
        PUSER="${auth%:*}"; PPASS="${auth#*:}"
    else
        PUSER=""; PPASS=""
    fi
    hp="${rest%%/*}"
    PHOST="${hp%:*}"; PPORT="${hp##*:}"
    # proxychains uses 'http' for HTTP CONNECT proxies (including https://)
    [ "$SCHEME" = "https" ] && SCHEME="http"
    PROXY_LINE="${SCHEME} ${PHOST} ${PPORT}${PUSER:+ ${PUSER} ${PPASS}}"
    cat > /tmp/proxychains.conf << CONF
strict_chain
proxy_dns
[ProxyList]
${PROXY_LINE}
CONF
    echo "[launcher] proxychains4 via ${SCHEME}://${PHOST}:${PPORT}"
    exec proxychains4 -f /tmp/proxychains.conf -q "$GCLAW" "$@"
fi

exec "$GCLAW" "$@"
