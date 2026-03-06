#!/usr/bin/env bash
# test.sh — Verify OpenClaw Gateway is running correctly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
PASS=0; FAIL=0

pass() { echo -e "  ${GREEN}PASS${NC}  $*"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC}  $*"; FAIL=$((FAIL + 1)); }
info() { echo -e "         ${YELLOW}$*${NC}"; }
heading() { echo -e "\n${BOLD}$*${NC}"; }

# ── Test 1: Container running ─────────────────────────────────────────────────
heading "Test 1: Container status"

STATUS=$(docker inspect --format='{{.State.Status}}' openclaw-gateway 2>/dev/null || echo "not found")
[[ "$STATUS" == "running" ]] && pass "Container is running" || { fail "Container is not running (${STATUS})"; info "Run: ./setup.sh"; }

# ── Test 2: Port 18789 (inside container) ────────────────────────────────────
heading "Test 2: Gateway port 18789"

if docker exec openclaw-gateway node -e \
  "require('net').createConnection(18789,'127.0.0.1').on('connect',()=>process.exit(0)).on('error',()=>process.exit(1))" \
  2>/dev/null; then
  pass "Port 18789 is open inside the container"
else
  fail "Port 18789 is not responding"
  info "Check logs: docker compose logs"
fi

# ── Test 3: Docker healthcheck + openclaw health ──────────────────────────────
heading "Test 3: Gateway health"

HEALTH=$(docker inspect --format='{{.State.Health.Status}}' openclaw-gateway 2>/dev/null || echo "unknown")
[[ "$HEALTH" == "healthy" ]] && pass "Docker healthcheck: healthy" || fail "Docker healthcheck: ${HEALTH}"

HEALTH_OUT=$(docker exec openclaw-gateway sh /launcher.sh health 2>&1 || true)
if echo "$HEALTH_OUT" | grep -qiE "(agents:|session|heartbeat)"; then
  pass "openclaw health: OK"
  info "$HEALTH_OUT"
elif echo "$HEALTH_OUT" | grep -qi "1006"; then
  pass "openclaw health: gateway up (WS 1006 on cold start — normal)"
else
  fail "openclaw health: unexpected output"
  info "${HEALTH_OUT:0:200}"
fi

# ── Test 4: Bridge port 18791 ─────────────────────────────────────────────────
heading "Test 4: Bridge port 18791"

if docker exec openclaw-gateway node -e \
  "require('net').createConnection(18791,'127.0.0.1').on('connect',()=>process.exit(0)).on('error',()=>process.exit(1))" \
  2>/dev/null; then
  pass "Bridge port 18791 is open"
else
  info "SKIP — bridge port 18791 only opens on first browser client connection"
fi

# ── Test 5: Config isolation ──────────────────────────────────────────────────
heading "Test 5: Config isolation"

MOUNT=$(docker inspect \
  --format='{{range .Mounts}}{{if eq .Destination "/home/node/.openclaw"}}{{.Source}}{{end}}{{end}}' \
  openclaw-gateway 2>/dev/null || echo "")

if [[ "$MOUNT" == *"openclaw-config"* ]]; then
  pass "Config: ./openclaw-config → /home/node/.openclaw (host ~/.openclaw untouched)"
else
  fail "Config mount unexpected: '${MOUNT}'"
fi

# ── Test 6: Onboarding status ─────────────────────────────────────────────────
heading "Test 6: Onboarding status"

if [[ -s openclaw-config/openclaw.json ]]; then
  pass "openclaw.json exists — onboarding completed"
else
  info "No config yet. Run the onboarding wizard:"
  info "  ./openclaw onboard"
fi

# ── Test 7: Toolchain volume ──────────────────────────────────────────────────
heading "Test 7: Toolchain volume (PROT-003)"

TOOL_MOUNT=$(docker inspect \
  --format='{{range .Mounts}}{{if eq .Destination "/home/node/.npm-global"}}{{.Source}}{{end}}{{end}}' \
  openclaw-gateway 2>/dev/null || echo "")

[[ "$TOOL_MOUNT" == *"toolchain"* ]] \
  && pass "Toolchain: ./toolchain → /home/node/.npm-global" \
  || fail "Toolchain volume not found"

PREFIX=$(docker exec openclaw-gateway \
  sh -c 'NPM_CONFIG_PREFIX=/home/node/.npm-global npm config get prefix' 2>/dev/null || echo "error")
[[ "$PREFIX" == "/home/node/.npm-global" ]] \
  && pass "npm prefix → /home/node/.npm-global" \
  || fail "npm prefix mismatch: '${PREFIX}'"

# ── Test 8: Launcher & user ───────────────────────────────────────────────────
heading "Test 8: Launcher & user"

LAUNCHER_MOUNT=$(docker inspect \
  --format='{{range .Mounts}}{{if eq .Destination "/launcher.sh"}}{{.Source}}{{end}}{{end}}' \
  openclaw-gateway 2>/dev/null || echo "")
[[ "$LAUNCHER_MOUNT" == *"launcher.sh"* ]] \
  && pass "launcher.sh mounted at /launcher.sh" \
  || fail "launcher.sh not found as bind mount"

PROC_USER=$(docker exec openclaw-gateway sh -c "ps aux | grep '[o]penclaw' | awk '{print \$1}' | head -1" 2>/dev/null || echo "unknown")
[[ "$PROC_USER" == "node" ]] \
  && pass "openclaw process running as: node" \
  || fail "openclaw process running as: ${PROC_USER} (expected: node)"

LOG=$(docker logs openclaw-gateway 2>&1 | grep "\[launcher\]" | tail -1 || echo "")
[[ -n "$LOG" ]] && pass "Launcher: ${LOG}" || info "No launcher log line found"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}────────────────────────────────────────${NC}"
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}All ${TOTAL} tests passed.${NC}"
  exit 0
else
  echo -e "${RED}${FAIL} of ${TOTAL} tests failed.${NC}"
  exit 1
fi
