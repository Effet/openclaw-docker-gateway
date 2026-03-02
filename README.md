# OpenClaw Docker Gateway

Run [OpenClaw](https://openclaw.ai) Gateway in Docker with a fully isolated config — no interference with your host `~/.openclaw`.

## Quick Start

```bash
# 1. Build and start
docker compose up -d

# 2. Configure API keys and channels
docker exec -it openclaw-gateway bash

# 3. Check status
docker compose ps
docker compose logs -f
```

Gateway UI: **http://localhost:18789** (default, no Tailscale)

> **First boot takes ~2 minutes** — `launcher.sh` bootstraps openclaw via npm into the persisted `toolchain/` volume. Subsequent starts are fast.

## Project Structure

```
.
├── docker-compose.yml              # Default (no Tailscale)
├── docker-compose.tailscale.yml    # Tailscale sidecar overlay
├── Dockerfile                      # node:22 + supervisor
├── launcher.sh                     # Bootstraps and runs openclaw
├── supervisord.conf                # Process manager config
├── ts-serve.json                   # Tailscale serve config (Option B)
├── .env.tailscale.example          # Tailscale auth key template
├── openclaw-config/                # Isolated OpenClaw config (gitignored)
└── toolchain/                      # Persisted npm global prefix
```

## Tailscale

Two options for remote access via Tailscale:

### Option A — Host Tailscale (manual, simpler)

Keep the default `docker-compose.yml`. On your host, run once:

```bash
docker exec <tailscale-container> tailscale serve --bg https / proxy http://localhost:18789
```

`--bg` persists the config — survives reboots as long as the Tailscale container state volume is mounted.

Connect a node:

```bash
openclaw node run --host <device>.tail12345.ts.net --port 443 --tls
```

### Option B — Tailscale Sidecar (IaC, recommended)

Everything is declared in Compose — no manual steps after first deploy.

```bash
cp .env.tailscale.example .env.tailscale
# Fill in TS_AUTHKEY from https://login.tailscale.com/admin/settings/keys

docker compose -f docker-compose.yml -f docker-compose.tailscale.yml up -d
```

No ports are exposed to the host — all traffic goes through the Tailscale network.

**Prerequisites:** Enable HTTPS in the Tailscale admin console (DNS → Enable HTTPS). Required for `tailscale serve` to obtain a certificate.

### openclaw config for Tailscale

Add `allowTailscale` so the Gateway trusts Tailscale identity headers — Web UI access becomes token-free for tailnet members:

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

## Architecture Notes

### supervisord as PID 1

The container runs `supervisord` as PID 1, which manages the `openclaw gateway` process. This means:

- **The container never exits due to openclaw crashing.** supervisord restarts openclaw automatically (up to 5 retries).
- **`restart: unless-stopped` only triggers on container exit** — since PID 1 never exits, Docker's restart policy is effectively not involved in openclaw recovery. supervisord handles that layer.

### healthcheck behavior

The healthcheck probes port 18789 to report whether openclaw is reachable. Two common misconceptions:

- **Failing healthcheck does NOT trigger a container restart.** Docker's restart policy is based on container exit codes, not healthcheck state. An `unhealthy` status is purely informational.
- **During supervisord restarts of openclaw**, the healthcheck will temporarily fail and the container will show `unhealthy` — this is expected and resolves automatically once openclaw is back up.

The healthcheck is a status indicator, not a recovery mechanism.

### systemd warning

openclaw may warn that it is not managed by systemd. This is expected in any container environment and does not affect functionality. supervisord is the correct process manager for this context.

## Useful Commands

| Action | Command |
|--------|---------|
| Start | `docker compose up -d` |
| Stop | `docker compose down` |
| Logs | `docker compose logs -f` |
| Shell | `docker exec -it openclaw-gateway bash` |
| openclaw status | `docker exec openclaw-gateway supervisorctl status` |
| Restart openclaw | `docker exec openclaw-gateway supervisorctl restart openclaw` |
| Update openclaw | `./update.sh [version]` |

## Updating OpenClaw

```bash
./update.sh           # install latest
./update.sh 2026.2.26 # install a specific version
```

Hot-swaps the binary into the `toolchain/` volume and restarts the gateway — no image rebuild needed.
