#!/bin/bash
# ============================================
# 停止 OpenClaw 容器
# 用法: bash stop-openclaw.sh
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.prod.yml"
COMPOSE_FILE_DEV="$SCRIPT_DIR/docker-compose.yml"
CONTAINER_NAME="custom_qq_client-openclaw-1"
PORT=18789
GRACE_PERIOD=15
FORCE_AFTER=30

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[stop]${NC} $*"; }
warn()  { echo -e "${YELLOW}[stop]${NC} $*"; }
die()   { echo -e "${RED}[stop]${NC} $*" >&2; exit 1; }

# --- 检查是否在运行 ---
RUNNING=false
RUNNING_COMPOSE=""
for cf in "$COMPOSE_FILE" "$COMPOSE_FILE_DEV"; do
    if [[ -f "$cf" ]]; then
        if docker compose -f "$cf" ps --status running 2>/dev/null | grep -q openclaw; then
            RUNNING=true
            RUNNING_COMPOSE="$cf"
            break
        fi
    fi
done

# 兜底：通过容器名或端口查找
if ! $RUNNING; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$CONTAINER_NAME"; then
        RUNNING=true
    fi
fi
if ! $RUNNING; then
    PORT_PID=$(ss -tlnp 2>/dev/null | grep ":${PORT}" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
    if [[ -z "${PORT_PID:-}" ]]; then
        info "OpenClaw 未运行，无需停止"
        exit 0
    fi
    warn "检测到端口 ${PORT} 被 PID=${PORT_PID} 占用（非容器），将尝试终止..."
    kill "$PORT_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$PORT_PID" 2>/dev/null || true
    info "已终止进程 $PORT_PID"
    exit 0
fi

# --- 优雅停止 ---
info "正在停止 OpenClaw..."
if [[ -n "$RUNNING_COMPOSE" ]]; then
    docker compose -f "$RUNNING_COMPOSE" stop -t "$GRACE_PERIOD" 2>&1 || true
else
    docker stop -t "$GRACE_PERIOD" "$CONTAINER_NAME" 2>&1 || true
fi

# --- 等待退出 ---
info "等待容器退出（最长 ${FORCE_AFTER}s）..."
WAITED=0
while [[ $WAITED -lt $FORCE_AFTER ]]; do
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$CONTAINER_NAME"; then
        info "容器已停止"
        exit 0
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

# --- 强制停止 ---
warn "优雅停止超时，正在强制终止..."
docker kill "$CONTAINER_NAME" 2>/dev/null || true
sleep 2

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$CONTAINER_NAME"; then
    die "无法停止容器 $CONTAINER_NAME，请手动处理"
fi

info "容器已强制停止"
