#!/bin/bash
# ============================================
# 停止 OpenClaw（systemd 服务）
# 用法: bash stop-openclaw.sh
# ============================================
set -euo pipefail

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

SERVICE="openclaw-gateway.service"

# --- 检查 systemd 服务 ---
if systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
    info "正在停止 systemd 服务..."
    systemctl --user stop "$SERVICE"

    # 等待退出
    info "等待退出（最长 ${FORCE_AFTER}s）..."
    WAITED=0
    while [[ $WAITED -lt $FORCE_AFTER ]]; do
        if ! systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
            info "服务已停止"
            break
        fi
        sleep 2
        WAITED=$((WAITED + 2))
    done

    if systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
        warn "优雅停止超时，强制终止..."
        systemctl --user kill "$SERVICE" 2>/dev/null || true
        sleep 2
    fi
fi

# --- 兜底：检查端口占用 ---
PORT_PID=$(ss -tlnp 2>/dev/null | grep ":${PORT}" | grep -oP 'pid=\K[0-9]+' | head -1 || true)
if [[ -n "${PORT_PID:-}" ]]; then
    warn "检测到端口 ${PORT} 被 PID=${PORT_PID} 占用，正在终止..."
    kill "$PORT_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$PORT_PID" 2>/dev/null || true
    info "已终止进程 $PORT_PID"
fi

if ! ss -tlnp 2>/dev/null | grep -q ":${PORT}"; then
    info "OpenClaw 已停止"
else
    die "无法停止端口 ${PORT}，请手动处理"
fi
