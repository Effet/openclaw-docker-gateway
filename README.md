# OpenClaw Docker Gateway

[中文文档](README.zh.md)

Run [OpenClaw](https://openclaw.ai) Gateway in Docker with **fully isolated config**, **Tailscale remote access**, and **proxy support** for restricted networks — no interference with your host environment.

## Highlights

- **Config isolation** — all state lives in `./openclaw-config`, never touching `~/.openclaw` on the host
- **Tailscale sidecar** — expose the gateway over your tailnet with zero open ports, fully declared in Compose
- **Proxy-aware** — single `PROXY=` env var routes Node.js traffic through proxychains4 (works in China and corporate networks where `HTTPS_PROXY` alone isn't enough)
- **VM-like UX** — `docker exec` drops you in as `node`, wrapper scripts for every operation, supervisord keeps the process alive without restarting the container
- **Hot-swap updates** — upgrade openclaw without rebuilding the image

## Quick Start

```bash
# 1. Clone and configure
cp .env.example .env
$EDITOR .env   # set GATEWAY_HOSTNAME, PROXY, etc. as needed

# 2. Start (ports mode — gateway on localhost:18789)
./setup.sh ports

# 3. Configure API keys and channels
./openclaw onboard
```

Gateway UI: **http://localhost:18789**

## Configuration (`.env`)

Copy `.env.example` to `.env` and fill in as needed. All fields are optional.

| Variable | Description |
|----------|-------------|
| `GATEWAY_HOSTNAME` | Container hostname shown in Tailscale admin (default: `openclaw-gateway`) |
| `TS_AUTHKEY` | Tailscale OAuth client secret or auth key (Tailscale mode only) |
| `TS_TAG` | Tailscale tag to advertise, e.g. `tag:server` (Tailscale mode only) |
| `NPM_REGISTRY` | npm registry mirror, e.g. `https://registry.npmmirror.com` |
| `PROXY` | Outbound proxy — see [Proxy](#proxy) below |

## Scripts

| Script | Description |
|--------|-------------|
| `./setup.sh <ports\|tailscale>` | Build and start the gateway |
| `./stop.sh <ports\|tailscale> [--down]` | Stop (or stop + remove) containers |
| `./restart.sh` | Restart the openclaw process via supervisorctl (fast) |
| `./restart.sh --full <ports\|tailscale>` | Restart the entire container |
| `./update.sh <ports\|tailscale> [version]` | Hot-swap openclaw to a new version |
| `./backup.sh` | Snapshot config + commit workspace |
| `./openclaw <args>` | Run openclaw CLI inside the container |

Run any script without arguments to see its usage.

## Tailscale

Use `./setup.sh tailscale` to start with the Tailscale sidecar. The `openclaw` container shares the sidecar's network — no ports are exposed to the host.

**Prerequisites:**
1. Create an OAuth client at Tailscale admin → Settings → OAuth clients (`devices:write` scope)
2. Define your tag in ACL `tagOwners`
3. Enable HTTPS in Tailscale admin (DNS → Enable HTTPS) for certificate support

```bash
# .env
TS_AUTHKEY=tskey-client-xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TS_TAG=tag:server
```

```bash
./setup.sh tailscale
```

Tailscale state is persisted in `./tailscale-state/` — the device stays registered across restarts without re-authentication.

**openclaw config for Tailscale** — add `allowTailscale` so the gateway trusts Tailscale identity headers (token-free Web UI access for tailnet members):

```json
{
  "gateway": {
    "auth": {
      "mode": "token",
      "token": "...",
      "allowTailscale": true
    }
  }
}
```

> API endpoints (`/v1/*`) still require a token regardless of `allowTailscale`.

## Proxy

OpenClaw needs outbound access to Google/Gemini APIs. Set a single variable in `.env`:

```env
# HTTP proxy
PROXY=http://192.168.1.1:7890

# HTTP proxy with authentication
PROXY=http://user:pass@192.168.1.1:7890

# SOCKS5 (recommended — see below)
PROXY=socks5://192.168.1.1:1080
```

**Two-layer coverage.** `PROXY` is propagated two ways:

1. As `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` env vars — picked up by standard HTTP clients (npm, curl, git, Node `fetch`/undici).
2. The gateway daemon and the `./openclaw` CLI wrapper run under **proxychains4**, which hooks libc `connect()` as a catch-all for libraries that ignore env vars or use raw TCP.

Most clients are covered by the env vars; proxychains sweeps up the stragglers. `npm install` during bootstrap / hot-swap is also covered.

**Prefer SOCKS5 over HTTP proxy.** HTTP CONNECT proxies are designed for HTTPS (port 443) and often block or mishandle connections to other ports (e.g. SSH on port 22). Some npm packages depend on private git repos cloned over SSH — with an HTTP proxy these installs fail with a misleading `Permission denied (publickey)` error. SOCKS5 tunnels raw TCP regardless of port, so SSH git dependencies work correctly.

**DNS hijacking.** proxychains4 runs with `proxy_dns`, so name resolution is also tunneled. Prevents DNS pollution (common in China and some corporate networks) from causing silent failures that masquerade as auth errors.

**Bypass whitelist.** proxychains is configured with a `localnet` whitelist so loopback (`127.0.0.0/8`, `::1`), link-local (`169.254.0.0/16`, where cloud-metadata endpoints live), and the proxy host itself never enter the proxy chain. This prevents two classes of problems: double-wrapping when an env-aware app dials the proxy directly, and Google SDK's ADC discovery hanging on a metadata probe that got misrouted upstream. The container additionally sets `GCE_METADATA_HOST=metadata.invalid` to short-circuit that probe at the SDK layer.

## Restore from Backup

Restore an existing config **before** running `setup.sh`:

```bash
rsync -av /path/to/backup/ ./openclaw-config/

# If workspace has a git remote
git clone <remote-url> ./openclaw-workspace

./setup.sh ports
```

## Backup

### Snapshot (host)

`backup.sh` snapshots all four data directories (`openclaw-config`, `openclaw-workspace`, `openclaw-workspaces`, `openclaw-repos`) as a single `.tar.gz`. Runtime logs are excluded; `.git` dirs are included for disaster recovery.

```bash
./backup.sh

# Schedule with cron (every hour)
0 * * * * /path/to/openclaw-docker-gateway/backup.sh >> /tmp/openclaw-backup.log 2>&1
```

### Workspace sync (container)

`sync.sh` commits and pushes workspace changes to local bare repos in `/home/node/repos/`. Bare repos are auto-initialized if missing; remote `origin` is set automatically if not configured (existing remotes are never overridden, making future migration to a real git server seamless).

```bash
docker exec openclaw-gateway /home/node/scripts/sync.sh
```

**Push workspace to a real remote** (optional — set the remote before running sync):

```bash
docker exec openclaw-gateway git -C /home/node/.openclaw/workspace remote set-url origin <your-remote-url>
```

## Updating OpenClaw

```bash
./update.sh ports            # latest
./update.sh ports 2026.3.1   # specific version
```

Hot-swaps the binary into the `toolchain/` volume and restarts the gateway — no image rebuild needed.

## Multiple Workspaces

openclaw supports configuring the workspace path per agent. Additional workspaces live in `./openclaw-workspaces/` on the host, mounted at `/home/node/workspaces` in the container.

Create a subdirectory per agent:

```bash
mkdir -p openclaw-workspaces/agent-a openclaw-workspaces/agent-b
```

Then point each agent's workspace to `/home/node/workspaces/agent-a` in openclaw's config. The main workspace (`./openclaw-workspace`) is unaffected.

## Skills

The `container/skills/` directory contains openclaw skills shipped with this repo. Skills teach agents how to use the gateway's scripts (backup, workspace management, bare repos).

**Enable globally** (all agents) — add to `openclaw.json`:

```json
{
  "skills": {
    "load": {
      "extraDirs": ["/home/node/scripts/skills"]
    }
  }
}
```

**Enable per agent** (symlink into workspace):

```bash
mkdir -p openclaw-workspaces/agent-a/skills
ln -s /home/node/scripts/skills/gateway-ops \
      /home/node/workspaces/agent-a/skills/gateway-ops
```

The skill source lives in `container/skills/` and is mounted read-only at `/home/node/scripts/skills/`. Runtime-installed skills (`~/.openclaw/skills/`) are unaffected.

## Shared Git Repos (Bare Repos)

Agents can share knowledge via local bare git repos mounted at `/home/node/repos` in the container.

Initialize a bare repo:

```bash
git init --bare openclaw-repos/knowledge.git
```

Then inside any agent's workspace:

```bash
git remote add origin /home/node/repos/knowledge.git
git push origin main
```

Any agent with access to the container can clone or pull from the same path. No network required.

## Architecture Notes

### supervisord as PID 1

`supervisord` manages the `openclaw gateway` process. Key implications:

- The container never exits due to openclaw crashing — supervisord restarts it automatically (up to 5 retries)
- `restart: unless-stopped` is effectively not involved in openclaw recovery; supervisord handles that layer
- `./restart.sh` restarts just the openclaw process without touching the container

### Healthcheck

The healthcheck probes port 18789. A failing healthcheck does **not** trigger a container restart — Docker's restart policy is based on container exit codes, not healthcheck state. An `unhealthy` status is purely informational and resolves automatically once openclaw recovers.

### First Boot

On first start, `launcher.sh` installs openclaw via `npm install -g`. This takes ~2 minutes. The binary is cached in `./toolchain/` — subsequent starts are fast.
