#!/bin/bash
# 在 Docker Desktop 卡死、容器长期 Restarting、compose down 卡在 Stopping 时使用：
# 1) 先菜单重启 Docker Desktop（或 macOS 重启）
# 2) 再执行：bash ./force-reset-openclaw-docker.sh

set -euo pipefail
cd "$(dirname "$0")"

echo "=== 强制清理并重建 openclaw 容器 ==="

docker compose down -t 2 2>/dev/null || true
docker rm -f qq-client-openclaw-1 2>/dev/null || true

echo "=== 重新启动 ==="
docker compose up -d --build

echo "=== 状态 ==="
docker compose ps
echo ""
echo "控制台: http://localhost:18789"
echo "带 token: docker compose exec openclaw openclaw dashboard --no-open"
