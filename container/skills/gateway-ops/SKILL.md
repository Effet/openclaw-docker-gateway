---
name: gateway-ops
description: Manage this OpenClaw Docker Gateway — backup workspaces and bare git repos.
---

# Gateway Operations

你运行在一个 Docker 容器中。以下脚本挂载在 `/home/node/scripts/`，可直接执行。

## 备份与同步

### 快照备份（宿主机执行）

在宿主机运行，将所有数据目录打包为 tar.gz：

```bash
./backup.sh
```

### Workspace 同步（容器内执行）

将 workspace 变更 commit 并 push 到本地 bare repo：

```bash
/home/node/scripts/sync.sh
```

- 自动初始化 bare repo（如不存在）
- 自动配置 remote origin（如未配置）
- 支持未来迁移到真实 git remote server（已有 remote 不会被覆盖）

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
