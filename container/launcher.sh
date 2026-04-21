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
    # Use proxy environment variables ONLY for npm installation to avoid loopbacks later.
    HTTPS_PROXY="${PROXY:-}" HTTP_PROXY="${PROXY:-}" \
    npm install -g --no-fund --no-audit \
        ${NPM_REGISTRY:+--registry "$NPM_REGISTRY"} \
        openclaw || { echo "[launcher] Install failed, will retry"; exit 1; }
fi

echo "[launcher] OpenClaw $("$GCLAW" --version 2>/dev/null)"

# Kill any stale gateway instance before starting (prevents port 18789 conflict
# when supervisor restarts and the previous openclaw-gateway became an orphan).
"$GCLAW" gateway stop 2>/dev/null && echo "[launcher] Stopped stale gateway" || true

# If PROXY is set, route openclaw through proxychains4.
if [ -n "${PROXY:-}" ]; then
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
    PHOST="${hp%:*}"
    PPORT="${hp##*:}"

    # Handle cases where no port is specified.
    if [ "$PHOST" = "$PPORT" ]; then
        case "$SCHEME" in
            socks*) PPORT="1080" ;;
            *) PPORT="80" ;;
        esac
    fi

    # Normalize scheme for proxychains (uses 'http' for HTTP/HTTPS CONNECT).
    case "$SCHEME" in
        socks5*) SCHEME="socks5" ;;
        socks4*) SCHEME="socks4" ;;
        https|http) SCHEME="http" ;;
    esac

    PROXY_LINE="${SCHEME} ${PHOST} ${PPORT}${PUSER:+ ${PUSER} ${PPASS}}"
    # localnet ${PHOST} prevents double-wrap: apps honoring HTTP_PROXY already
    # dial the proxy directly; without this proxychains would re-wrap that dial.
    cat > /tmp/proxychains.conf << CONF
strict_chain
proxy_dns
localnet 127.0.0.0/255.0.0.0
localnet ::1/128
localnet 169.254.0.0/255.255.0.0
localnet ${PHOST}/255.255.255.255
[ProxyList]
${PROXY_LINE}
CONF
    echo "[launcher] proxychains4 via ${SCHEME}://${PHOST}:${PPORT}"
    
    # Do NOT export HTTPS_PROXY here. Run via proxychains to avoid loopbacks.
    exec proxychains4 -f /tmp/proxychains.conf -q "$GCLAW" "$@"
fi

exec "$GCLAW" "$@"
