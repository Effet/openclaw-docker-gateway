# OpenClaw Docker Gateway

在 Docker 中运行 [OpenClaw](https://openclaw.ai) Gateway，**配置完全隔离**、支持 **Tailscale 远程访问**，以及为受限网络提供**代理支持** — 不影响宿主机环境。

## 亮点

- **配置隔离** — 所有状态存放在 `./openclaw-config`，不会碰宿主机的 `~/.openclaw`
- **Tailscale 边车** — 通过 tailnet 暴露 gateway，零开放端口，完全在 Compose 中声明
- **代理友好** — 单个 `PROXY=` 环境变量，通过 proxychains4 在 socket 层透明代理 Node.js 流量（在国内及企业网络中，仅靠 `HTTPS_PROXY` 往往不够）
- **类 VM 体验** — `docker exec` 直接以 `node` 用户进入，每个操作都有封装脚本，supervisord 在不重启容器的前提下保活进程
- **热更新** — 无需重建镜像即可升级 openclaw

## 快速开始

```bash
# 1. 克隆并配置
cp .env.example .env
$EDITOR .env   # 按需填写 GATEWAY_HOSTNAME、PROXY 等

# 2. 启动（端口模式 — gateway 监听 localhost:18789）
./setup.sh ports

# 3. 配置 API key 和渠道
./openclaw onboard
```

Gateway 界面：**http://localhost:18789**

## 配置（`.env`）

将 `.env.example` 复制为 `.env` 并按需填写，所有字段均为可选。

| 变量 | 说明 |
|------|------|
| `GATEWAY_HOSTNAME` | 在 Tailscale 管理后台显示的容器主机名（默认：`openclaw-gateway`） |
| `TS_AUTHKEY` | Tailscale OAuth client secret 或 auth key（仅 Tailscale 模式需要） |
| `TS_TAG` | 要广播的 Tailscale 标签，例如 `tag:server`（仅 Tailscale 模式需要） |
| `NPM_REGISTRY` | npm 镜像源，例如 `https://registry.npmmirror.com` |
| `PROXY` | 出站代理 — 详见下方 [代理](#代理) 章节 |

## 脚本

| 脚本 | 说明 |
|------|------|
| `./setup.sh <ports\|tailscale>` | 构建并启动 gateway |
| `./stop.sh <ports\|tailscale> [--down]` | 停止（或停止并删除）容器 |
| `./restart.sh` | 通过 supervisorctl 重启 openclaw 进程（快速） |
| `./restart.sh --full <ports\|tailscale>` | 重启整个容器 |
| `./update.sh <ports\|tailscale> [version]` | 热更新 openclaw 到新版本 |
| `./backup.sh` | 快照配置并提交工作区 |
| `./openclaw <args>` | 在容器内运行 openclaw CLI |

不带参数运行任意脚本可查看用法说明。

## Tailscale

使用 `./setup.sh tailscale` 启动带 Tailscale 边车的模式。`openclaw` 容器共享边车的网络 — 宿主机不暴露任何端口。

**前置条件：**
1. 在 Tailscale 管理后台 → Settings → OAuth clients 创建 OAuth 客户端（`devices:write` 权限）
2. 在 ACL `tagOwners` 中定义你的标签
3. 在 Tailscale 管理后台启用 HTTPS（DNS → Enable HTTPS）以获得证书支持

```bash
# .env
TS_AUTHKEY=tskey-client-xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TS_TAG=tag:server
```

```bash
./setup.sh tailscale
```

Tailscale 状态持久化在 `./tailscale-state/` — 重启后设备无需重新认证。

**openclaw 配置 Tailscale** — 添加 `allowTailscale` 让 gateway 信任 Tailscale 身份头信息（tailnet 成员免 token 访问 Web UI）：

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

> API 端点（`/v1/*`）无论 `allowTailscale` 如何设置，始终需要 token。

## 代理

Node.js 原生 `fetch`（undici）不识别 `HTTPS_PROXY`。本项目使用 **proxychains4** 在 socket 层透明代理 openclaw 的所有流量。

在 `.env` 中设置单个变量：

```env
# HTTP 代理
PROXY=http://192.168.1.1:7890

# 带账号密码的 HTTP 代理
PROXY=http://user:pass@192.168.1.1:7890

# SOCKS5（推荐，原因见下）
PROXY=socks5://192.168.1.1:1080
```

初次安装和热更新时的 `npm install` 同样走代理。

**推荐 SOCKS5，而非 HTTP 代理。** HTTP CONNECT 代理是为 HTTPS（443 端口）设计的，通常会拦截或无法正确处理其他端口的连接（如 SSH 的 22 端口）。某些 npm 包依赖通过 SSH 拉取的私有 git 仓库 — 使用 HTTP 代理时，这类安装会以 `Permission denied (publickey)` 报错失败，误导性很强。SOCKS5 在 TCP 层透明隧道，不区分端口，SSH git 依赖可以正常工作。

**DNS 劫持。** proxychains4 启用了 `proxy_dns`，DNS 解析也会经由代理服务器进行。这可以防止 DNS 污染/劫持（在国内及部分企业网络中常见）导致的隐性失败 — 这类失败往往伪装成认证报错，难以排查。

## 从备份恢复

在运行 `setup.sh` **之前**恢复已有配置：

```bash
rsync -av /path/to/backup/ ./openclaw-config/

# 如果工作区有 git remote
git clone <remote-url> ./openclaw-workspace

./setup.sh ports
```

## 备份

`backup.sh` 将 `openclaw-config/` 快照为 `.tar.gz`，并将 `openclaw-workspace/` 提交到自己的 git 历史。

```bash
./backup.sh

# 通过 cron 定时执行（每小时）
0 * * * * /path/to/openclaw-docker-gateway/backup.sh >> /tmp/openclaw-backup.log 2>&1
```

**推送工作区到远程**（可选 — 配置后 `backup.sh` 会自动推送）：

```bash
cd openclaw-workspace && git remote add origin <your-private-repo-url>
```

## 更新 OpenClaw

```bash
./update.sh ports            # 最新版
./update.sh ports 2026.3.1   # 指定版本
```

热替换二进制文件到 `toolchain/` 卷并重启 gateway — 无需重建镜像。

## 多 Workspace

openclaw 支持为每个 agent 配置独立的 workspace 路径。额外的 workspace 存放在宿主机的 `./openclaw-workspaces/` 目录，挂载到容器内 `/home/node/workspaces`。

按 agent 建子目录：

```bash
mkdir -p openclaw-workspaces/agent-a openclaw-workspaces/agent-b
```

在 openclaw 配置中将各 agent 的 workspace 路径指向 `/home/node/workspaces/agent-a` 即可。主 workspace（`./openclaw-workspace`）不受影响。

## 架构说明

### supervisord 作为 PID 1

`supervisord` 管理 `openclaw gateway` 进程，关键影响：

- 容器不会因 openclaw 崩溃而退出 — supervisord 会自动重启（最多 5 次）
- `restart: unless-stopped` 实际上不参与 openclaw 的恢复，这一层由 supervisord 处理
- `./restart.sh` 只重启 openclaw 进程，不影响容器

### 健康检查

健康检查探测 18789 端口。检查失败**不会**触发容器重启 — Docker 的重启策略基于容器退出码，而非健康检查状态。`unhealthy` 状态仅作参考，openclaw 恢复后会自动变回 `healthy`。

### 首次启动

首次启动时，`launcher.sh` 通过 `npm install -g` 安装 openclaw，约需 2 分钟。二进制文件缓存在 `./toolchain/` — 后续启动很快。
