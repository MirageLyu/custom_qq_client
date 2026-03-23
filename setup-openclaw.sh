#!/bin/bash
set -e

echo "=== OpenClaw + QQ Bot 部署脚本 ==="
echo ""

echo "[1/4] 构建 Docker 镜像（含 Rust qq-client 编译）..."
docker compose build

echo "[2/4] 启动 OpenClaw..."
docker compose up -d

echo "[3/4] 等待 OpenClaw 启动..."
sleep 5

echo "[4/4] 安装 QQ Bot 插件并配置..."
docker compose exec openclaw openclaw plugins install @tencent-connect/openclaw-qqbot@latest
docker compose exec openclaw openclaw channels add --channel qqbot --token "102133076:IGEDCBA987777777789ABCDEFHJLNPRT"
docker compose exec openclaw openclaw gateway restart

echo ""
echo "=== 部署完成 ==="
echo "OpenClaw 控制面板: http://localhost:18789"
echo ""
echo "接下来："
echo "  1. 在 QQ 中搜索并添加你的机器人为好友"
echo "  2. 私聊发送「查看最新动态」测试"
