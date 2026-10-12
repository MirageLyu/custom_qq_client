#!/bin/bash
# ============================================
# 启动 OpenClaw（systemd 服务）
# 用法: bash start-openclaw.sh
# ============================================
set -euo pipefail

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

SERVICE="openclaw-gateway.service"

# --- 检查是否已在运行 ---
if systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
    if curl -s -o /dev/null -w '%{http_code}' "$HEALTH_URL" 2>/dev/null | grep -qE '^(200|301|302|304)$'; then
        info "OpenClaw 已在运行且健康，无需重复启动"
        info "访问地址: ${HEALTH_URL}"
        exit 0
    fi
    info "服务运行中但网关未响应，正在重启..."
    systemctl --user restart "$SERVICE"
else
    info "启动 OpenClaw 服务..."
    systemctl --user start "$SERVICE"
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
    die "启动超时（${MAX_WAIT}s），请检查日志: journalctl --user -u $SERVICE -n 50"
fi

info "服务状态: $(systemctl --user is-active "$SERVICE")"
info "查看日志: journalctl --user -u $SERVICE -f"
