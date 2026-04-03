# qq-client

基于 OpenClaw + QQ Bot 插件的游戏动态助手。部署完成后，你可以：

- 在 QQ 里直接和机器人对话
- 通过 `bilibili_dynamics` skill 查询原神、崩坏：星穹铁道、绝区零的最新 B 站动态
- 打开 OpenClaw 控制台查看网关与通道状态

## 项目组成

- `qq-client`：Rust 命令行工具，负责拉取并整理 B 站动态
- `skills/bilibili-dynamics`：OpenClaw skill，负责让 Agent 在合适的时候调用 `qq-client`
- `openclaw-config/SOUL.md`：Agent 行为定义
- `docker-compose.yml`：启动 OpenClaw 控制台与运行环境

## 快速开始

1. 复制环境变量模板：

```bash
cp openclaw-config/.env.example openclaw-config/.env
```

2. 编辑 `openclaw-config/.env`，至少填入：

- 一个可用的 LLM API Key
- `QQBOT_APPID`
- `QQBOT_SECRET`

3. 执行部署脚本：

```bash
bash ./setup-openclaw.sh
```

4. 打开控制台：

```bash
bash ./open-openclaw-console.sh
```

控制台地址固定为 [http://localhost:18789](http://localhost:18789)。

## QQ 验证

完成部署后，在 QQ 中打开你创建的机器人，测试下面两类消息：

- `/bot-ping`
- `原神最近有什么新动态`

如果 `/bot-ping` 返回正常，说明 QQ 通道已经打通；如果动态类问题能正常回复，说明 Skill 和 `qq-client` 命令链路已经可用。

## 手动命令

### 查询三款游戏各 2 条最新动态

```bash
cargo run -- latest --all --count 2
```

### 查询指定游戏

```bash
cargo run -- latest --game 原神 --count 5 --format json
```

### 查看数据库统计

```bash
cargo run -- stats
```

## 说明

- `docker-compose.yml` 已持久化 `/root/.openclaw`，插件、频道配置和缓存不会在容器重建后丢失
- `latest` 子命令默认会过滤抽奖/开奖类低价值转发动态
- 如果拉取 B 站动态时遇到 `412 Precondition Failed`，请在 `config.toml` 的 `bilibili.cookie` 中填入浏览器导出的 Cookie，建议至少包含 `SESSDATA`
- 如需查看更多历史动态，可为 `latest` 增加 `--pages 3 --include-forwards`
