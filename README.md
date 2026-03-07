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

Node.js's native `fetch` (undici) does not respect `HTTPS_PROXY`. This setup uses **proxychains4** to transparently route openclaw's traffic at the socket level.

Set a single variable in `.env`:

```env
# HTTP proxy
PROXY=http://192.168.1.1:7890

# HTTP proxy with authentication
PROXY=http://user:pass@192.168.1.1:7890

# SOCKS5 (recommended — see below)
PROXY=socks5://192.168.1.1:1080
```

`npm install` also benefits — `PROXY` is automatically used during bootstrapping and hot-swap updates.

**Prefer SOCKS5 over HTTP proxy.** HTTP CONNECT proxies are designed for HTTPS (port 443) and often block or mishandle connections to other ports (e.g. SSH on port 22). Some npm packages depend on private git repos cloned over SSH — with an HTTP proxy these installs fail with a misleading `Permission denied (publickey)` error. SOCKS5 tunnels raw TCP regardless of port, so SSH git dependencies work correctly.

**DNS hijacking.** proxychains4 is configured with `proxy_dns`, meaning DNS resolution is also routed through the proxy. This prevents DNS pollution/hijacking (common in China and some corporate networks) from causing silent failures that masquerade as authentication errors.

## Restore from Backup

Restore an existing config **before** running `setup.sh`:

```bash
rsync -av /path/to/backup/ ./openclaw-config/

# If workspace has a git remote
git clone <remote-url> ./openclaw-workspace

./setup.sh ports
```

## Backup

`backup.sh` snapshots `openclaw-config/` as a `.tar.gz` and commits `openclaw-workspace/` to its own git history.

```bash
./backup.sh

# Schedule with cron (every hour)
0 * * * * /path/to/openclaw-docker-gateway/backup.sh >> /tmp/openclaw-backup.log 2>&1
```

**Push workspace to a remote** (optional — `backup.sh` will push automatically once configured):

```bash
cd openclaw-workspace && git remote add origin <your-private-repo-url>
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
