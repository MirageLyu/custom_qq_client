#!/bin/bash
# ============================================
# 快速迭代：改 qq_client / SOUL.md / skills 后一键同步并重启
#
# 用法（在项目根目录）：
#   bash quick-update.sh              # 完整：pip + 同步 + 重启
#   SKIP_PIP=1 bash quick-update.sh   # 只改 SOUL/skills，跳过 pip
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[quick-update]${NC} $*"; }
warn() { echo -e "${YELLOW}[quick-update]${NC} $*"; }

SERVICE="openclaw-gateway.service"

# --- Python 依赖 ---
if [[ "${SKIP_PIP:-}" != "1" ]]; then
    info "pip install -r requirements.txt ..."
    pip install -q httpx click tomli 2>/dev/null || pip3 install -q httpx click tomli 2>/dev/null
    info "qq-client (Python) 依赖已更新"
else
    info "SKIP_PIP=1，跳过 Python 依赖安装"
fi

# --- 同步 SOUL.md ---
if [[ -f "$SCRIPT_DIR/openclaw-config/SOUL.md" ]]; then
    mkdir -p ~/.openclaw
    cp "$SCRIPT_DIR/openclaw-config/SOUL.md" ~/.openclaw/SOUL.md
    info "已同步 SOUL.md"
fi

# --- 同步 skills ---
if [[ -d "$SCRIPT_DIR/skills/bilibili-dynamics" ]]; then
    mkdir -p ~/.openclaw/skills/bilibili-dynamics
    cp -r "$SCRIPT_DIR/skills/bilibili-dynamics/"* ~/.openclaw/skills/bilibili-dynamics/
    info "已同步 skills/bilibili-dynamics"
fi

# --- 同步 openclaw-data 中的 skills（兼容旧路径） ---
OPENCLAW_DATA="$SCRIPT_DIR/openclaw-data"
if [[ -d "$OPENCLAW_DATA" ]]; then
    mkdir -p "$OPENCLAW_DATA/skills/bilibili-dynamics"
    if [[ -d "$SCRIPT_DIR/skills/bilibili-dynamics" ]]; then
        cp -r "$SCRIPT_DIR/skills/bilibili-dynamics/"* "$OPENCLAW_DATA/skills/bilibili-dynamics/"
        info "已同步 skills 到 openclaw-data"
    fi
fi

# --- 重启服务 ---
info "重启 systemd 服务..."
systemctl --user restart "$SERVICE"

sleep 3
if systemctl --user is-active --quiet "$SERVICE"; then
    info "完成！服务已重启。查看日志:"
    echo "  journalctl --user -u $SERVICE -f"
else
    warn "服务可能启动失败，请检查:"
    echo "  journalctl --user -u $SERVICE -n 30"
fi
