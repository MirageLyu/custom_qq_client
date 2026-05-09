#!/bin/bash
# ============================================
# 启动 OpenClaw 容器
# 用法: bash start-openclaw.sh
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.prod.yml"
ENV_FILE="$SCRIPT_DIR/openclaw-config/.env"
CONTAINER_NAME="custom_qq_client-openclaw-1"
PORT=18789
HEALTH_URL="http://127.0.0.1:${PORT}"
MAX_WAIT=60
POLL_INTERVAL=3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[start]${NC} $*"; }
warn()  { echo -e "${YELLOW}[start]${NC} $*"; }
die()   { echo -e "${RED}[start]${NC} $*" >&2; exit 1; }

# --- 前置检查 ---
command -v docker &>/dev/null || die "docker 未安装"
docker compose version &>/dev/null || die "docker compose 不可用"

[[ -f "$COMPOSE_FILE" ]] || die "未找到 $COMPOSE_FILE"
[[ -f "$ENV_FILE" ]] || die "未找到 $ENV_FILE，请先创建并填写环境变量"

# --- 检查是否已在运行 ---
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$CONTAINER_NAME"; then
    STATUS=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
    if [[ "$STATUS" == "healthy" ]]; then
        info "OpenClaw 已在运行且健康，无需重复启动"
        info "访问地址: ${HEALTH_URL}"
        exit 0
    fi
    info "容器已存在但状态为 [$STATUS]，尝试重启..."
    docker compose -f "$COMPOSE_FILE" up -d --force-recreate
else
    info "启动 OpenClaw 容器..."
    docker compose -f "$COMPOSE_FILE" up -d
fi

# --- 等待就绪 ---
info "等待网关就绪（最长 ${MAX_WAIT}s）..."
WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
    if curl -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" 2>/dev/null | grep -qE '^(200|301|302|304)$'; then
        info "网关已就绪（耗时 ${WAITED}s）"
        break
    fi
    sleep "$POLL_INTERVAL"
    WAITED=$((WAITED + POLL_INTERVAL))
done

if [[ $WAITED -ge $MAX_WAIT ]]; then
    die "启动超时（${MAX_WAIT}s），请检查日志: docker compose -f $COMPOSE_FILE logs --tail 50"
fi

# --- 最终状态 ---
HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
info "容器状态: $HEALTH"
info "日志: docker compose -f $COMPOSE_FILE logs -f --tail 30"
