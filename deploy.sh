#!/bin/bash
# Ubuntu 公网服务器一键部署脚本
# 用法：git clone 仓库 → 填写 openclaw-config/.env → bash deploy.sh
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
info "[1/9] 检测 Docker..."

# 国内镜像优先，官方源作为 fallback
DOCKER_MIRRORS=(
    "https://mirrors.aliyun.com/docker-ce"
    "https://mirrors.tencent.com/docker-ce"
    "https://download.docker.com"
)

install_docker_from_mirror() {
    local mirror="$1"
    info "尝试从 ${mirror} 安装 Docker..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo rm -f /etc/apt/keyrings/docker.gpg

    if ! curl -fsSL --connect-timeout 10 "${mirror}/linux/ubuntu/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null; then
        warn "  GPG 密钥下载失败: ${mirror}"
        return 1
    fi
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] ${mirror}/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"
    info "Docker 已安装。如果后续命令报权限错误，请执行 'newgrp docker' 或重新登录。"
    return 0
}

install_docker() {
    for mirror in "${DOCKER_MIRRORS[@]}"; do
        if install_docker_from_mirror "$mirror"; then
            return 0
        fi
        warn "镜像 ${mirror} 失败，尝试下一个..."
    done
    error "所有 Docker 安装源均失败。请手动安装 Docker：\n  curl -fsSL https://get.docker.com | bash"
}

if ! command -v docker &>/dev/null; then
    info "Docker 未安装，正在自动安装..."
    install_docker
else
    info "Docker 已安装: $(docker --version)"
fi

if ! docker compose version &>/dev/null; then
    warn "未检测到 'docker compose' 插件，正在安装..."
    install_docker
    if ! docker compose version &>/dev/null; then
        error "无法使用 'docker compose'，请手动安装：\n  sudo apt-get install -y docker-compose-plugin\n  或参考 https://docs.docker.com/engine/install/ubuntu/"
    fi
fi
info "Docker Compose: $(docker compose version --short 2>/dev/null || echo 'ok')"

# 配置 Docker Hub 镜像加速（国内服务器拉取 docker.io 镜像经常超时）
DAEMON_JSON="/etc/docker/daemon.json"
if [[ ! -f "$DAEMON_JSON" ]] || ! grep -q "registry-mirrors" "$DAEMON_JSON" 2>/dev/null; then
    info "配置 Docker Hub 镜像加速..."
    sudo mkdir -p /etc/docker
    sudo tee "$DAEMON_JSON" > /dev/null <<'DAEMONJSON'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://hub-mirror.c.163.com",
    "https://docker.mirrors.ustc.edu.cn"
  ]
}
DAEMONJSON
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    info "Docker Hub 镜像加速已配置"
fi

# ===== 2. 检查 .env 文件 =====
info "[2/9] 检查环境配置..."
if [[ ! -f "$ENV_FILE" ]]; then
    if [[ -f "$ENV_EXAMPLE" ]]; then
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        warn ".env 不存在，已从 .env.example 复制。请编辑后重新运行："
        warn "  vim $ENV_FILE"
        exit 1
    else
        error "未找到 $ENV_FILE 和 $ENV_EXAMPLE，请先创建 .env 文件"
    fi
fi

set -a
source "$ENV_FILE"
set +a

HAS_LLM_KEY=false
for key in OPENAI_API_KEY ANTHROPIC_API_KEY DEEPSEEK_API_KEY; do
    val="${!key:-}"
    if [[ -n "$val" && "$val" != sk-xxx* && "$val" != "sk-ant-xxx" ]]; then
        HAS_LLM_KEY=true
        break
    fi
done
if [[ "$HAS_LLM_KEY" == "false" ]]; then
    warn "未检测到有效的 LLM API Key（OPENAI_API_KEY / ANTHROPIC_API_KEY / DEEPSEEK_API_KEY）"
    warn "OpenClaw 将无法回复消息，请在 .env 中配置后重启容器。"
fi

# ===== 3. 生成 gateway token =====
info "[3/9] 生成 OpenClaw gateway 配置..."
GATEWAY_TOKEN=$(openssl rand -hex 24)

mkdir -p "$OPENCLAW_DATA/skills/bilibili-dynamics"
mkdir -p "$SCRIPT_DIR/data"

cat > "$OPENCLAW_DATA/openclaw.json" <<ENDJSON
{
  "gateway": {
    "host": "0.0.0.0",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "$GATEWAY_TOKEN"
    },
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
ENDJSON
info "Gateway token 已生成（48 字符随机十六进制）"

# ===== 4. 复制 SOUL.md 和 skills =====
info "[4/9] 同步 SOUL.md 和 skills 到 openclaw-data/..."
if [[ -f "$SCRIPT_DIR/openclaw-config/SOUL.md" ]]; then
    cp "$SCRIPT_DIR/openclaw-config/SOUL.md" "$OPENCLAW_DATA/SOUL.md"
fi
if [[ -d "$SCRIPT_DIR/skills/bilibili-dynamics" ]]; then
    cp -r "$SCRIPT_DIR/skills/bilibili-dynamics/"* "$OPENCLAW_DATA/skills/bilibili-dynamics/"
fi

# ===== 5. 编译 qq-client（宿主机上编译，避免拉取 Docker Hub 的 rust 镜像）=====
info "[5/10] 编译 qq-client..."
if [[ -f "$SCRIPT_DIR/qq-client" ]] && [[ "$SCRIPT_DIR/qq-client" -nt "$SCRIPT_DIR/src/main.rs" ]]; then
    info "qq-client 二进制已存在且较新，跳过编译"
else
    if ! command -v rustc &>/dev/null; then
        info "安装 Rust 工具链..."
        sudo apt-get install -y -qq build-essential pkg-config libssl-dev
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
    fi
    source "$HOME/.cargo/env" 2>/dev/null || true
    info "编译 qq-client（首次编译约 3-5 分钟）..."
    cd "$SCRIPT_DIR"
    cargo build --release
    cp target/release/qq-client "$SCRIPT_DIR/qq-client"
    info "qq-client 编译完成"
fi

# ===== 6. 构建 Docker 镜像 =====
info "[6/10] 构建 Docker 镜像..."
docker compose -f "$COMPOSE_FILE" build

# ===== 6.5. 清理端口占用和修复权限 =====
info "检查端口 18789 占用情况..."
docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true

# 停止宿主机上可能存在的原生 OpenClaw 进程
if command -v openclaw &>/dev/null; then
    openclaw gateway stop 2>/dev/null || true
fi

# 杀掉占用 18789 的进程
PORT_PID=$(ss -tlnp 2>/dev/null | grep ':18789' | grep -oP 'pid=\K[0-9]+' | head -1)
if [[ -n "$PORT_PID" ]]; then
    warn "端口 18789 被 PID=$PORT_PID 占用，正在终止..."
    kill "$PORT_PID" 2>/dev/null || sudo kill "$PORT_PID" 2>/dev/null || true
    sleep 2
    # 确认是否已释放
    if ss -tlnp 2>/dev/null | grep -q ':18789'; then
        warn "强制终止..."
        kill -9 "$PORT_PID" 2>/dev/null || sudo kill -9 "$PORT_PID" 2>/dev/null || true
        sleep 1
    fi
fi

# 修复 openclaw-data 目录权限（容器内 node 用户 UID=1000）
info "修复 openclaw-data 目录权限..."
sudo chown -R 1000:1000 "$OPENCLAW_DATA"

# ===== 7. 启动容器 =====
info "[7/10] 启动 OpenClaw 容器..."
docker compose -f "$COMPOSE_FILE" up -d

# ===== 8. 等待网关就绪 =====
info "[8/10] 等待网关就绪..."
MAX_WAIT=60
WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
    if curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:18789" 2>/dev/null | grep -q '200\|301\|302\|304'; then
        info "网关已就绪（等待 ${WAITED}s）"
        break
    fi
    sleep 3
    WAITED=$((WAITED + 3))
    printf "  等待中... %ds / %ds\r" "$WAITED" "$MAX_WAIT"
done
echo ""
if [[ $WAITED -ge $MAX_WAIT ]]; then
    warn "等待超时（${MAX_WAIT}s），网关可能尚未完全启动"
    warn "请检查日志：docker compose -f docker-compose.prod.yml logs -f"
fi

# ===== 9. 安装 QQ Bot 插件（直接解压，不走 openclaw plugins install，避免吃满小服务器资源）=====
info "[9/10] 安装 QQ Bot 插件..."
PLUGIN_DIR="$OPENCLAW_DATA/plugins/@tencent-connect/openclaw-qqbot"

if [[ -d "$PLUGIN_DIR" && -f "$PLUGIN_DIR/package.json" ]]; then
    info "QQ Bot 插件已存在，跳过安装"
    PLUGIN_INSTALLED=true
else
    PLUGIN_INSTALLED=false
    TMP_TGZ="/tmp/openclaw-qqbot.tgz"

    info "下载 QQ Bot 插件包..."
    curl -sL --connect-timeout 10 --max-time 60 \
        "https://registry.npmmirror.com/@tencent-connect/openclaw-qqbot/latest" -o /tmp/qqbot-meta.json 2>/dev/null

    # 从 npmmirror 元数据中提取 tarball URL
    TARBALL_URL=""
    if [[ -f /tmp/qqbot-meta.json ]]; then
        TARBALL_URL=$(grep -o '"tarball":"[^"]*"' /tmp/qqbot-meta.json | head -1 | cut -d'"' -f4)
    fi

    if [[ -n "$TARBALL_URL" ]]; then
        info "从 $TARBALL_URL 下载..."
        curl -sL --connect-timeout 10 --max-time 60 "$TARBALL_URL" -o "$TMP_TGZ"
    fi

    # fallback: 直接拼 URL
    if [[ ! -f "$TMP_TGZ" || ! -s "$TMP_TGZ" ]]; then
        info "尝试备用下载地址..."
        curl -sL --connect-timeout 10 --max-time 60 \
            "https://registry.npmmirror.com/@tencent-connect/openclaw-qqbot/-/openclaw-qqbot-1.7.1.tgz" -o "$TMP_TGZ" 2>/dev/null || \
        curl -sL --connect-timeout 10 --max-time 60 \
            "https://registry.npmjs.org/@tencent-connect/openclaw-qqbot/-/openclaw-qqbot-1.7.1.tgz" -o "$TMP_TGZ" 2>/dev/null
    fi

    if [[ -f "$TMP_TGZ" && -s "$TMP_TGZ" ]]; then
        info "解压插件到 $PLUGIN_DIR ..."
        mkdir -p "$PLUGIN_DIR"
        tar -xzf "$TMP_TGZ" -C "$PLUGIN_DIR" --strip-components=1
        if [[ -f "$PLUGIN_DIR/package.json" ]]; then
            PLUGIN_INSTALLED=true
            info "QQ Bot 插件安装成功（直接解压，零资源消耗）"
        else
            warn "解压后未找到 package.json，插件可能不完整"
        fi
        rm -f "$TMP_TGZ" /tmp/qqbot-meta.json
    else
        warn "插件包下载失败"
    fi
fi

if [[ "$PLUGIN_INSTALLED" == "false" ]]; then
    warn "QQ Bot 插件自动安装失败，请手动下载并解压到："
    warn "  $PLUGIN_DIR"
fi

# 插件安装到宿主机的 openclaw-data/ 后需要重启容器以加载
if [[ "$PLUGIN_INSTALLED" == "true" ]]; then
    info "重启容器以加载插件..."
    docker compose -f "$COMPOSE_FILE" restart
    sleep 5
fi

# ===== 10. 配置 QQ Bot 频道 =====
info "[10/10] 配置 QQ Bot 频道..."
QQBOT_TOKEN="${QQBOT_TOKEN:-}"
if [[ -z "$QQBOT_TOKEN" && -n "${QQBOT_APPID:-}" && -n "${QQBOT_SECRET:-}" ]]; then
    QQBOT_TOKEN="${QQBOT_APPID}:${QQBOT_SECRET}"
fi

if [[ -z "$QQBOT_TOKEN" || "$QQBOT_TOKEN" == *"你的"* ]]; then
    warn "未检测到有效的 QQ Bot 凭证，跳过频道配置。"
    warn "请在 .env 中填写 QQBOT_APPID 和 QQBOT_SECRET 后执行："
    warn "  docker compose -f docker-compose.prod.yml exec openclaw openclaw channels add --channel qqbot --token \"AppID:AppSecret\""
    warn "  docker compose -f docker-compose.prod.yml exec openclaw openclaw gateway restart"
else
    docker compose -f "$COMPOSE_FILE" exec -T -e QQBOT_TOKEN="$QQBOT_TOKEN" openclaw \
        sh -c 'openclaw channels add --channel qqbot --token "$QQBOT_TOKEN" || true'
    docker compose -f "$COMPOSE_FILE" exec -T openclaw openclaw gateway restart 2>/dev/null || true
    info "QQ Bot 频道已配置"
fi

# ===== 完成，输出信息 =====
SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || echo "<服务器IP>")

echo ""
echo "============================================"
echo -e "  ${GREEN}部署完成！${NC}"
echo "============================================"
echo ""
echo "OpenClaw 控制面板："
echo -e "  ${GREEN}http://${SERVER_IP}:18789/#token=${GATEWAY_TOKEN}${NC}"
echo ""
echo "Gateway Token（已保存到 openclaw-data/openclaw.json）："
echo "  $GATEWAY_TOKEN"
echo ""
echo "常用命令："
echo "  docker compose -f docker-compose.prod.yml logs -f    # 查看日志"
echo "  docker compose -f docker-compose.prod.yml restart    # 重启服务"
echo "  docker compose -f docker-compose.prod.yml down       # 停止服务"
echo ""

if [[ -n "$QQBOT_TOKEN" && "$QQBOT_TOKEN" != *"你的"* ]]; then
    echo -e "${YELLOW}重要提醒：${NC}"
    echo "  请在 https://q.qq.com/ 的机器人设置中添加服务器公网 IP 到白名单"
    echo -e "  服务器公网 IP: ${GREEN}${SERVER_IP}${NC}"
    echo ""
fi

echo "验证部署："
echo "  1. 浏览器打开上方控制面板 URL，确认 Gateway 正常运行"
echo "  2. 在 QQ 上 @机器人 发消息验证回复"
echo "  3. 发送「原神最新动态」验证 skills 工作"
echo ""
