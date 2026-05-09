#!/bin/bash
# ============================================
# 快速迭代：改 Rust / SOUL.md / skills 后一键验证（不重装 Docker、不重写 openclaw.json）
#
# 用法（在项目根目录）：
#   bash quick-update.sh              # 默认：编译 + 同步 + 重建镜像 + 重启容器
#   SKIP_CARGO=1 bash quick-update.sh # 只改 SOUL/skills 时用，跳过 cargo（更快）
#
# 本地若用 docker-compose.yml 而非生产 compose：
#   COMPOSE_FILE=./docker-compose.yml bash quick-update.sh
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

COMPOSE_FILE="${COMPOSE_FILE:-$SCRIPT_DIR/docker-compose.prod.yml}"
OPENCLAW_DATA="$SCRIPT_DIR/openclaw-data"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
info() { echo -e "${GREEN}[quick-update]${NC} $*"; }
warn() { echo -e "${YELLOW}[quick-update]${NC} $*"; }

[[ -f "$COMPOSE_FILE" ]] || { echo "未找到 $COMPOSE_FILE"; exit 1; }

if [[ "${SKIP_PIP:-}" != "1" ]]; then
    info "pip install -r requirements.txt ..."
    pip install -q httpx click tomli 2>/dev/null || pip3 install -q httpx click tomli 2>/dev/null
    info "qq-client (Python) 依赖已更新"
else
    info "SKIP_PIP=1，跳过 Python 依赖安装"
fi

mkdir -p "$OPENCLAW_DATA/skills/bilibili-dynamics"
if [[ -f "$SCRIPT_DIR/openclaw-config/SOUL.md" ]]; then
    cp "$SCRIPT_DIR/openclaw-config/SOUL.md" "$OPENCLAW_DATA/SOUL.md"
    info "已同步 SOUL.md"
fi
if [[ -d "$SCRIPT_DIR/skills/bilibili-dynamics" ]]; then
    cp -r "$SCRIPT_DIR/skills/bilibili-dynamics/"* "$OPENCLAW_DATA/skills/bilibili-dynamics/"
    info "已同步 skills/bilibili-dynamics"
fi

if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
    sudo chown -R 1000:1000 "$OPENCLAW_DATA"
elif [[ "$(id -u)" -eq 0 ]]; then
    chown -R 1000:1000 "$OPENCLAW_DATA" 2>/dev/null || true
else
    warn "无法无密码 sudo，若容器内报权限错误请手动: sudo chown -R 1000:1000 openclaw-data"
fi

info "docker compose build + up -d ..."
docker compose -f "$COMPOSE_FILE" build
docker compose -f "$COMPOSE_FILE" up -d

info "完成。看日志:"
echo "  docker compose -f \"$COMPOSE_FILE\" logs -f --tail 30"
