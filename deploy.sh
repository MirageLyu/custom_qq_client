#!/bin/bash
# ============================================
# OpenClaw + QQ Bot 一键部署脚本 (Ubuntu 公网服务器)
# 用法：git clone 仓库 → 填写 openclaw-config/.env → bash deploy.sh
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/openclaw-config/.env"
ENV_EXAMPLE="$SCRIPT_DIR/openclaw-config/.env.example"
OPENCLAW_DATA="$SCRIPT_DIR/openclaw-data"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.prod.yml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "============================================"
echo "  OpenClaw + QQ Bot 一键部署 (Ubuntu)"
echo "============================================"
echo ""

# ===== 1. 检测并安装 Docker =====
info "[1/8] 检测 Docker..."

DOCKER_MIRRORS=(
    "https://mirrors.aliyun.com/docker-ce"
    "https://mirrors.tencent.com/docker-ce"
    "https://download.docker.com"
)

install_docker_from_mirror() {
    local mirror="$1"
    info "  尝试从 ${mirror} ..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo rm -f /etc/apt/keyrings/docker.gpg
    if ! curl -fsSL --connect-timeout 10 "${mirror}/linux/ubuntu/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
        return 1
    fi
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${mirror}/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER" 2>/dev/null || true
    return 0
}

if ! command -v docker &>/dev/null; then
    info "Docker 未安装，正在自动安装..."
    INSTALLED=false
    for mirror in "${DOCKER_MIRRORS[@]}"; do
        if install_docker_from_mirror "$mirror"; then
            INSTALLED=true; break
        fi
        warn "  ${mirror} 失败，尝试下一个..."
    done
    [[ "$INSTALLED" == "false" ]] && error "Docker 安装失败，请手动安装后重试"
else
    info "Docker 已安装: $(docker --version)"
fi

if ! docker compose version &>/dev/null; then
    error "docker compose 不可用，请安装 docker-compose-plugin"
fi

# ===== 2. 检查 .env =====
info "[2/8] 检查环境配置..."
if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "$ENV_EXAMPLE" ]]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        warn ".env 不存在，已从模板复制。请填写后重新运行："
        warn "  vim $ENV_FILE"
        exit 1
    else
        error "未找到 $ENV_FILE，请先创建"
    fi
fi

set -a; source "$ENV_FILE"; set +a

DASHSCOPE_KEY="${DASHSCOPE_API_KEY:-}"
[[ -z "$DASHSCOPE_KEY" || "$DASHSCOPE_KEY" == *"你的"* ]] && error "请在 .env 中填写 DASHSCOPE_API_KEY"

QQBOT_APPID="${QQBOT_APPID:-}"
QQBOT_SECRET="${QQBOT_SECRET:-}"
QQBOT_TOKEN="${QQBOT_TOKEN:-}"
if [[ -z "$QQBOT_TOKEN" && -n "$QQBOT_APPID" && -n "$QQBOT_SECRET" ]]; then
    QQBOT_TOKEN="${QQBOT_APPID}:${QQBOT_SECRET}"
fi

# ===== 3. 编译 qq-client =====
info "[3/8] 编译 qq-client..."
if [[ -f "$SCRIPT_DIR/qq-client" ]] && [[ "$SCRIPT_DIR/qq-client" -nt "$SCRIPT_DIR/src/main.rs" ]]; then
    info "  二进制已存在且较新，跳过编译"
else
    if ! command -v rustc &>/dev/null; then
        info "  安装 Rust 工具链..."
        sudo apt-get install -y -qq build-essential pkg-config libssl-dev
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    source "$HOME/.cargo/env" 2>/dev/null || true
    info "  编译中（首次约 3-5 分钟）..."
    cd "$SCRIPT_DIR" && cargo build --release
    cp target/release/qq-client "$SCRIPT_DIR/qq-client"
    info "  编译完成"
fi

# ===== 4. 构建 Docker 镜像 =====
info "[4/8] 构建 Docker 镜像..."
docker compose -f "$COMPOSE_FILE" build

# ===== 5. 清理端口 + 权限 =====
info "[5/8] 准备启动环境..."
docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true

if command -v openclaw &>/dev/null; then
    openclaw gateway stop 2>/dev/null || true
fi
# 停止残留的原生 OpenClaw systemd 服务
if [[ -f "$HOME/.config/systemd/user/openclaw-gateway.service" ]]; then
    systemctl --user stop openclaw-gateway 2>/dev/null || true
    systemctl --user disable openclaw-gateway 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/openclaw-gateway.service" 2>/dev/null || true
fi

PORT_PID=$(ss -tlnp 2>/dev/null | grep ':18789' | grep -oP 'pid=\K[0-9]+' | head -1 || true)
if [[ -n "${PORT_PID:-}" ]]; then
    warn "端口 18789 被 PID=$PORT_PID 占用，正在终止..."
    kill "$PORT_PID" 2>/dev/null || sudo kill "$PORT_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$PORT_PID" 2>/dev/null || sudo kill -9 "$PORT_PID" 2>/dev/null || true
    sleep 1
fi

# ===== 6. 生成配置 =====
info "[6/8] 生成 OpenClaw 配置..."
# 迭代部署时保留已有 gateway token，避免书签里的 #token= 失效
if [[ -f "$OPENCLAW_DATA/openclaw.json" ]]; then
    GATEWAY_TOKEN=$(grep -oP '"token"\s*:\s*"\K[^"]+' "$OPENCLAW_DATA/openclaw.json" 2>/dev/null | head -1 || true)
fi
[[ -z "${GATEWAY_TOKEN:-}" ]] && GATEWAY_TOKEN=$(openssl rand -hex 24)

SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || echo "0.0.0.0")

mkdir -p "$OPENCLAW_DATA/skills/bilibili-dynamics"
mkdir -p "$SCRIPT_DIR/data"

cat > "$OPENCLAW_DATA/openclaw.json" <<ENDJSON
{
  "agents": {
    "defaults": {
      "model": "dashscope/qwen3.5-plus",
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 },
      "compaction": { "mode": "safeguard" }
    }
  },
  "models": {
    "providers": {
      "dashscope": {
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "apiKey": "$DASHSCOPE_KEY",
        "api": "openai-completions",
        "models": [
          { "id": "qwen3.5-plus", "name": "Qwen 3.5 Plus" },
          { "id": "qwen-plus", "name": "Qwen Plus" },
          { "id": "qwen-turbo", "name": "Qwen Turbo" },
          { "id": "qwen-max", "name": "Qwen Max" }
        ]
      }
    }
  },
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    },
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": ["http://$SERVER_IP:18789"]
    }
  }
}
ENDJSON

if [[ -f "$SCRIPT_DIR/openclaw-config/SOUL.md" ]]; then
    cp "$SCRIPT_DIR/openclaw-config/SOUL.md" "$OPENCLAW_DATA/SOUL.md"
fi
if [[ -d "$SCRIPT_DIR/skills/bilibili-dynamics" ]]; then
    cp -r "$SCRIPT_DIR/skills/bilibili-dynamics/"* "$OPENCLAW_DATA/skills/bilibili-dynamics/"
fi

sudo chown -R 1000:1000 "$OPENCLAW_DATA"

# ===== 7. 启动容器 =====
info "[7/8] 启动容器..."
docker compose -f "$COMPOSE_FILE" up -d

info "  等待网关就绪..."
MAX_WAIT=60; WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
    if curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:18789" 2>/dev/null | grep -q '200\|301\|302\|304'; then
        info "  网关已就绪（${WAITED}s）"
        break
    fi
    sleep 3; WAITED=$((WAITED + 3))
done
[[ $WAITED -ge $MAX_WAIT ]] && warn "等待超时，请检查日志：docker compose -f docker-compose.prod.yml logs -f"

# ===== 8. 配置 QQ Bot 频道 =====
info "[8/8] 配置 QQ Bot 频道..."
if [[ -n "$QQBOT_TOKEN" && "$QQBOT_TOKEN" != *"你的"* ]]; then
    docker compose -f "$COMPOSE_FILE" exec -T -e QQBOT_TOKEN="$QQBOT_TOKEN" openclaw \
        sh -c 'openclaw channels add --channel qqbot --token "$QQBOT_TOKEN" 2>/dev/null || true'
    info "  QQ Bot 频道已配置"
else
    warn "未检测到 QQ Bot 凭证，跳过。请填写 .env 后手动添加："
    warn "  docker compose -f docker-compose.prod.yml exec openclaw openclaw channels add --channel qqbot --token \"AppID:AppSecret\""
fi

# ===== 完成 =====
echo ""
echo "============================================"
echo -e "  ${GREEN}部署完成！${NC}"
echo "============================================"
echo ""
echo "控制面板："
echo -e "  ${GREEN}http://${SERVER_IP}:18789/#token=${GATEWAY_TOKEN}${NC}"
echo ""
echo "Gateway Token："
echo "  $GATEWAY_TOKEN"
echo ""
echo "常用命令："
echo "  docker compose -f docker-compose.prod.yml logs -f      # 查看日志"
echo "  docker compose -f docker-compose.prod.yml restart      # 重启"
echo "  docker compose -f docker-compose.prod.yml down         # 停止"
echo ""
if [[ -n "$QQBOT_TOKEN" && "$QQBOT_TOKEN" != *"你的"* ]]; then
    echo -e "${YELLOW}重要：请在 https://q.qq.com/ 添加服务器 IP 到白名单${NC}"
    echo -e "  服务器 IP: ${GREEN}${SERVER_IP}${NC}"
    echo ""
fi
echo "验证："
echo "  1. 浏览器打开上方控制面板 URL"
echo "  2. 在控制台对话测试模型"
echo "  3. QQ 上 @机器人 发消息"
echo "  4. 发送「原神最新动态」测试 skills"
echo ""
