#!/bin/bash
# OpenClaw 原生安装脚本 - Ubuntu 22.04
# 适用于非 Docker 环境，直接在本机安装 OpenClaw + QQ Bot + qq-client

set -e

# ========== 配置区（可按需修改）==========
OPENCLAW_HOME="${HOME}/.openclaw"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 若需代理（如国内服务器访问 npm/github 慢），取消下行注释：
# export HTTPS_PROXY=http://127.0.0.1:7890
# export HTTP_PROXY=http://127.0.0.1:7890

echo "=== OpenClaw 原生安装脚本 (Ubuntu 22.04) ==="
echo "项目目录: $PROJECT_DIR"
echo ""

# ========== 1. 系统依赖 ==========
echo "[1/8] 更新系统并安装依赖..."
sudo apt update
sudo apt install -y curl wget git build-essential libssl-dev pkg-config

# ========== 2. Node.js 22 ==========
echo "[2/8] 安装 Node.js 22..."
if command -v node &>/dev/null && [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -ge 22 ]]; then
    echo "  Node.js $(node -v) 已满足要求，跳过安装"
else
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt install -y nodejs
fi
node -v
npm -v

# ========== 3. 安装 OpenClaw ==========
echo "[3/8] 安装 OpenClaw..."
sudo npm install -g openclaw@latest

# ========== 4. 安装 Rust（用于编译 qq-client）==========
echo "[4/8] 安装 Rust 并编译 qq-client..."
if ! command -v rustc &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
fi
source "$HOME/.cargo/env" 2>/dev/null || true

cd "$PROJECT_DIR"
cargo build --release
sudo cp target/release/qq-client /usr/local/bin/
sudo chmod +x /usr/local/bin/qq-client
echo "  qq-client 已安装到 /usr/local/bin/qq-client"
cd - >/dev/null

# ========== 5. OpenClaw 初始化（首次安装需交互）==========
echo "[5/8] OpenClaw 初始化..."
if [[ ! -f "$OPENCLAW_HOME/openclaw.json" ]]; then
    echo "  首次安装，请按向导完成配置（工作区、安全设置等，模型可稍后配置）"
    openclaw onboard --install-daemon
else
    echo "  已检测到 OpenClaw 配置，跳过 onboard"
fi

# ========== 6. 复制项目配置到 OpenClaw ==========
echo "[6/8] 复制项目配置..."
mkdir -p "$OPENCLAW_HOME/skills"
mkdir -p "$PROJECT_DIR/data"

# 技能
if [[ -d "$PROJECT_DIR/skills" ]]; then
    cp -r "$PROJECT_DIR/skills/"* "$OPENCLAW_HOME/skills/" 2>/dev/null || true
    echo "  已复制 skills"
fi

# SOUL.md
if [[ -f "$PROJECT_DIR/openclaw-config/SOUL.md" ]]; then
    cp "$PROJECT_DIR/openclaw-config/SOUL.md" "$OPENCLAW_HOME/"
    echo "  已复制 SOUL.md"
fi

# config.toml（B站等配置）
if [[ -f "$PROJECT_DIR/config.toml" ]]; then
    mkdir -p "$OPENCLAW_HOME/data"
    cp "$PROJECT_DIR/config.toml" "$OPENCLAW_HOME/config.toml" 2>/dev/null || cp "$PROJECT_DIR/config.toml" "$OPENCLAW_HOME/"
    echo "  已复制 config.toml"
fi

# ========== 7. 安装 QQ Bot 插件并添加频道 ==========
echo "[7/8] 安装 QQ Bot 插件..."
openclaw plugins install @tencent-connect/openclaw-qqbot@latest 2>/dev/null || true

# 从 .env 读取 QQ Bot Token（若有）
QQBOT_TOKEN=""
if [[ -f "$PROJECT_DIR/openclaw-config/.env" ]]; then
    QQBOT_TOKEN=$(grep -E '^QQBOT_TOKEN=' "$PROJECT_DIR/openclaw-config/.env" | cut -d= -f2- | tr -d '"' | tr -d "'")
fi
if [[ -z "$QQBOT_TOKEN" || "$QQBOT_TOKEN" == "你的AppID:你的AppSecret" ]]; then
    echo ""
    echo "  请配置 QQ Bot Token："
    echo "    1. 编辑 $PROJECT_DIR/openclaw-config/.env"
    echo "    2. 将 QQBOT_TOKEN=你的AppID:你的AppSecret 改为实际值"
    echo "    3. 然后执行: openclaw channels add --channel qqbot --token \"AppID:AppSecret\""
    echo "    4. 执行: openclaw gateway restart"
else
    openclaw channels add --channel qqbot --token "$QQBOT_TOKEN" 2>/dev/null || echo "  频道可能已存在，跳过"
fi

# ========== 8. 启动网关 ==========
echo "[8/8] 重启 OpenClaw 网关..."
openclaw gateway restart 2>/dev/null || openclaw gateway start

echo ""
echo "=== 安装完成 ==="
echo "OpenClaw 控制面板: http://localhost:18789"
echo ""
echo "后续步骤："
echo "  1. 若未配置 QQ Bot：编辑 openclaw-config/.env 填入 QQBOT_TOKEN，再执行："
echo "     openclaw channels add --channel qqbot --token \"AppID:AppSecret\""
echo "     openclaw gateway restart"
echo "  2. 若需配置 AI 模型（阿里云百炼等）："
echo "     编辑 ~/.openclaw/openclaw.json 添加 models.providers"
echo "  3. 在 QQ 中搜索并添加机器人为好友，私聊测试"
echo ""
echo "常用命令："
echo "  openclaw gateway start   # 启动网关"
echo "  openclaw gateway status  # 查看状态"
echo "  openclaw doctor         # 环境诊断"
echo ""
