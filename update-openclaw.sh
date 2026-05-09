#!/bin/bash
# ============================================
# 更新 OpenClaw 到最新版本并自动重启
# 用法: bash update-openclaw.sh
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="$SCRIPT_DIR/docker-compose.prod.yml"
ENV_FILE="$SCRIPT_DIR/openclaw-config/.env"
BASE_IMAGE="ghcr.io/openclaw/openclaw:latest"
CONTAINER_NAME="custom_qq_client-openclaw-1"
PORT=18789
HEALTH_URL="http://127.0.0.1:${PORT}"
MAX_WAIT=60
POLL_INTERVAL=3
PULL_RETRIES=3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[update]${NC} $*"; }
warn()  { echo -e "${YELLOW}[update]${NC} $*"; }
die()   { echo -e "${RED}[update]${NC} $*" >&2; exit 1; }

# --- 前置检查 ---
command -v docker &>/dev/null || die "docker 未安装"
docker compose version &>/dev/null || die "docker compose 不可用"

[[ -f "$COMPOSE_FILE" ]] || die "未找到 $COMPOSE_FILE"
[[ -f "$ENV_FILE" ]] || die "未找到 $ENV_FILE，请先创建并填写环境变量"

# --- 记录旧版本 ---
OLD_IMAGE_ID=""
OLD_DIGEST=""
if docker image inspect "$BASE_IMAGE" &>/dev/null; then
    OLD_IMAGE_ID=$(docker image inspect -f '{{.Id}}' "$BASE_IMAGE" 2>/dev/null || true)
    OLD_DIGEST=$(docker image inspect -f '{{index .RepoDigests 0}}' "$BASE_IMAGE" 2>/dev/null || true)
    info "当前基础镜像: ${OLD_DIGEST:-$OLD_IMAGE_ID}"
fi

# --- 拉取最新基础镜像（带重试） ---
info "拉取最新基础镜像 $BASE_IMAGE ..."
for i in $(seq 1 $PULL_RETRIES); do
    if docker pull "$BASE_IMAGE"; then
        break
    fi
    if [[ $i -eq $PULL_RETRIES ]]; then
        die "拉取镜像失败，已重试 ${PULL_RETRIES} 次"
    fi
    warn "第 $i 次拉取失败，${PULL_RETRIES} 秒后重试..."
    sleep "$PULL_RETRIES"
done

NEW_IMAGE_ID=$(docker image inspect -f '{{.Id}}' "$BASE_IMAGE" 2>/dev/null || true)
NEW_DIGEST=$(docker image inspect -f '{{index .RepoDigests 0}}' "$BASE_IMAGE" 2>/dev/null || true)
info "最新基础镜像: ${NEW_DIGEST:-$NEW_IMAGE_ID}"

if [[ -n "$OLD_IMAGE_ID" && "$OLD_IMAGE_ID" == "$NEW_IMAGE_ID" ]]; then
    info "基础镜像未变化，无需更新"
    # 但容器可能没跑，确保它在运行
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$CONTAINER_NAME"; then
        info "容器未运行，正在启动..."
        docker compose -f "$COMPOSE_FILE" up -d
    else
        HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
        info "容器状态: $HEALTH，无需操作"
        exit 0
    fi
else
    # --- 重建镜像 ---
    info "基础镜像有更新，正在重建..."
    docker compose -f "$COMPOSE_FILE" build || die "镜像构建失败"

    # --- 重启容器 ---
    info "用新镜像重启容器..."
    docker compose -f "$COMPOSE_FILE" up -d --force-recreate
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
    warn "启动超时（${MAX_WAIT}s），请检查日志"
    warn "docker compose -f $COMPOSE_FILE logs --tail 50"
    exit 1
fi

# --- 清理旧镜像 ---
docker image prune -f 2>/dev/null || true

# --- 最终状态 ---
HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
info "更新完成！容器状态: $HEALTH"
info "新镜像: ${NEW_DIGEST:-$NEW_IMAGE_ID}"
info "日志: docker compose -f $COMPOSE_FILE logs -f --tail 30"
