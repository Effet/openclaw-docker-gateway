---
name: gateway-ops
description: Manage this OpenClaw Docker Gateway — backup workspaces and bare git repos.
---

# Gateway Operations

你运行在一个 Docker 容器中。以下脚本挂载在 `/home/node/scripts/`，可直接执行。

## 备份 Workspace

将 workspace 和 workspaces 目录的变更提交到各自的 git 历史：

```bash
/home/node/scripts/backup.sh
```

- `/home/node/.openclaw/workspace` — 主 workspace
- `/home/node/workspaces/` — 多 agent workspace 根目录

若目录尚未初始化为 git repo，脚本会自动执行 `git init`。若已配置 `origin` remote，会自动 push。

## Workspace 管理

额外的 agent workspace 位于 `/home/node/workspaces/`，每个子目录对应一个 agent：

```bash
# 查看已有 workspace
ls /home/node/workspaces/

# 在 openclaw 配置中将 agent workspace 路径设为：
/home/node/workspaces/<agent-name>
```

## Bare Repo 管理

Bare repo 位于 `/home/node/repos/`，可作为各 agent 之间共享知识的 git remote。

```bash
# 列出所有 bare repo
/home/node/scripts/repos.sh list

# 初始化新 bare repo
/home/node/scripts/repos.sh init <name>

# 删除 bare repo
/home/node/scripts/repos.sh delete <name>
```

在任意 workspace 中使用 bare repo 作为 remote：

```bash
git remote add origin /home/node/repos/<name>.git
git push origin main

# 另一个 agent clone
git clone /home/node/repos/<name>.git
```
