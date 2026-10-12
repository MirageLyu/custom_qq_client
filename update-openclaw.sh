#!/bin/bash
# ============================================
# 更新 OpenClaw 到最新版本并自动重启
# 用法: bash update-openclaw.sh
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

info()  { echo -e "${GREEN}[update]${NC} $*"; }
warn()  { echo -e "${YELLOW}[update]${NC} $*"; }
die()   { echo -e "${RED}[update]${NC} $*" >&2; exit 1; }

SERVICE="openclaw-gateway.service"

# --- 记录旧版本 ---
OLD_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
info "当前版本: $OLD_VERSION"

# --- 查看最新版本 ---
info "检查最新版本..."
LATEST_VERSION=$(npm view openclaw version 2>/dev/null || echo "")
if [[ -z "$LATEST_VERSION" ]]; then
    die "无法获取最新版本信息"
fi

if [[ "$OLD_VERSION" == "$LATEST_VERSION" ]]; then
    info "已是最新版本 ($LATEST_VERSION)，无需更新"
    # 确保服务在运行
    if ! systemctl --user is-active --quiet "$SERVICE" 2>/dev/null; then
        info "服务未运行，正在启动..."
        systemctl --user start "$SERVICE"
    fi
    exit 0
fi

# --- 更新 ---
info "发现新版本: $LATEST_VERSION，正在更新..."
npm install -g openclaw@latest || die "npm 更新失败"

# --- 清理旧插件 symlink（如有需要） ---
PLUGIN_DIR="/root/custom_qq_client/openclaw-data/plugins/@tencent-connect/openclaw-qqbot"
if [[ -d "$PLUGIN_DIR/node_modules" ]]; then
    rm -f "$PLUGIN_DIR/node_modules/openclaw"
    ln -sfn /usr/lib/node_modules/openclaw "$PLUGIN_DIR/node_modules/openclaw"
    info "已更新插件 symlink"
fi

# --- 重启 ---
info "重启服务..."
systemctl --user restart "$SERVICE"

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
    warn "journalctl --user -u $SERVICE -n 50"
    exit 1
fi

NEW_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
info "更新完成！版本: $OLD_VERSION → $NEW_VERSION"
info "查看日志: journalctl --user -u $SERVICE -f"
