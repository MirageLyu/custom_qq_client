#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/openclaw-config/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
else
  echo "未找到 $ENV_FILE"
  echo "请先执行：cp openclaw-config/.env.example openclaw-config/.env"
  exit 1
fi

if [[ -z "$QQBOT_TOKEN" && -n "$QQBOT_APPID" && -n "$QQBOT_SECRET" ]]; then
  QQBOT_TOKEN="${QQBOT_APPID}:${QQBOT_SECRET}"
fi

echo "=== OpenClaw + QQ Bot 部署脚本 ==="
echo ""

echo "[1/5] 构建 Docker 镜像（含 Rust qq-client 编译）..."
docker compose build

echo "[2/5] 启动 OpenClaw..."
docker compose up -d

echo "[3/5] 等待 OpenClaw 启动..."
sleep 5

echo "[4/5] 安装 / 更新 QQ Bot 插件..."
docker compose exec openclaw openclaw plugins install @tencent-connect/openclaw-qqbot@latest

echo "[5/5] 配置 QQ Bot 频道..."
if [[ -z "$QQBOT_TOKEN" || "$QQBOT_TOKEN" == "你的AppID:你的AppSecret" ]]; then
  echo "未检测到 QQ Bot 凭证，已跳过频道配置。"
  echo "请编辑 openclaw-config/.env，填写 QQBOT_APPID / QQBOT_SECRET 后重新执行本脚本。"
else
  docker compose exec -e QQBOT_TOKEN="$QQBOT_TOKEN" openclaw sh -lc 'openclaw channels add --channel qqbot --token "$QQBOT_TOKEN" || true'
  docker compose exec openclaw openclaw gateway restart
fi

echo ""
echo "=== 部署完成 ==="
echo "OpenClaw 控制面板: http://localhost:18789"
echo ""
echo "接下来："
echo "  1. 打开控制台确认 Gateway 正常运行"
echo "  2. 在 QQ 中打开你的机器人，私聊测试：原神最近有什么新动态"
echo "  3. 也可以发送 /bot-ping 检查 QQ 通道是否已经联通"
