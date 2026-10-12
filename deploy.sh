#!/bin/bash
# ============================================
# OpenClaw + QQ Bot 一键部署脚本 (Ubuntu 公网服务器，直接部署)
# 用法：git clone 仓库 → 填写 openclaw-config/.env → bash deploy.sh
# ============================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/openclaw-config/.env"
ENV_EXAMPLE="$SCRIPT_DIR/openclaw-config/.env.example"
OPENCLAW_DATA="$SCRIPT_DIR/openclaw-data"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo ""
echo "============================================"
echo "  OpenClaw + QQ Bot 一键部署 (直接部署)"
echo "============================================"
echo ""

# ===== 1. 检测 Node.js =====
info "[1/6] 检测 Node.js..."
if ! command -v node &>/dev/null; then
    info "Node.js 未安装，正在通过 nvm 安装..."
    export NVM_DIR="$HOME/.nvm"
    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi
    source "$NVM_DIR/nvm.sh"
    nvm install 22
    nvm use 22
fi
info "Node.js: $(node --version)"

# ===== 2. 安装 OpenClaw =====
info "[2/6] 安装 OpenClaw..."
if command -v openclaw &>/dev/null; then
    info "OpenClaw 已安装: $(openclaw --version)"
    info "更新到最新版本..."
    npm install -g openclaw@latest
else
    npm install -g openclaw@latest
    info "OpenClaw 安装完成: $(openclaw --version)"
fi

# ===== 3. 安装 Python 依赖 =====
info "[3/6] 安装 Python 依赖..."
pip install httpx click tomli 2>/dev/null || pip3 install httpx click tomli 2>/dev/null
info "qq-client (Python) 已就绪"

# ===== 4. 检查/生成配置 =====
info "[4/6] 检查配置..."

# 加载 .env（如果存在）
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
fi

DASHSCOPE_KEY="${DASHSCOPE_API_KEY:-}"
DEEPSEEK_KEY="${DEEPSEEK_API_KEY:-}"

# 读取现有的 openclaw.json（迭代部署时保留）
if [[ -f "$OPENCLAW_DATA/openclaw.json" ]]; then
    info "检测到已有 openclaw-data/openclaw.json，保留现有配置"
    # 同步到运行目录
    cp "$OPENCLAW_DATA/openclaw.json" ~/.openclaw/openclaw.json
else
    GATEWAY_TOKEN=$(openssl rand -hex 24)
    SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || echo "0.0.0.0")

    # 选择默认模型提供商
    if [[ -n "$DEEPSEEK_KEY" ]]; then
        MODEL_PROVIDER="deepseek"
        MODEL_KEY="$DEEPSEEK_KEY"
        DEFAULT_MODEL="deepseek-v4-pro"
    elif [[ -n "$DASHSCOPE_KEY" ]]; then
        MODEL_PROVIDER="dashscope"
        MODEL_KEY="$DASHSCOPE_KEY"
        DEFAULT_MODEL="qwen3.5-plus"
    else
        warn "未检测到模型 API Key，请填写 openclaw-config/.env"
        MODEL_PROVIDER="deepseek"
        MODEL_KEY="YOUR_API_KEY"
        DEFAULT_MODEL="deepseek-v4-pro"
    fi

    # 根据提供商生成配置
    if [[ "$MODEL_PROVIDER" == "dashscope" ]]; then
        cat > ~/.openclaw/openclaw.json <<ENDJSON
{
  "agents": {
    "defaults": {
      "model": "dashscope/${DEFAULT_MODEL}",
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 },
      "compaction": { "mode": "safeguard" }
    }
  },
  "models": {
    "providers": {
      "dashscope": {
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
        "apiKey": "${MODEL_KEY}",
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
      "token": "${GATEWAY_TOKEN}"
    },
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": ["http://${SERVER_IP}:18789"]
    }
  },
  "plugins": {
    "allow": ["openclaw-qqbot"],
    "load": {
      "paths": ["/root/custom_qq_client/openclaw-data/plugins/@tencent-connect/openclaw-qqbot"]
    },
    "entries": {
      "openclaw-qqbot": { "enabled": true, "config": {} }
    }
  },
  "channels": {
    "qqbot": {
      "enabled": true,
      "allowFrom": ["*"],
      "appId": "${QQBOT_APPID:-}",
      "clientSecret": "${QQBOT_SECRET:-}"
    }
  }
}
ENDJSON
    else
        cat > ~/.openclaw/openclaw.json <<ENDJSON
{
  "agents": {
    "defaults": {
      "model": "deepseek/${DEFAULT_MODEL}",
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 },
      "compaction": { "mode": "safeguard" }
    }
  },
  "models": {
    "providers": {
      "deepseek": {
        "baseUrl": "https://api.deepseek.com",
        "apiKey": "${MODEL_KEY}",
        "api": "openai-completions",
        "models": [
          { "id": "deepseek-v4-pro", "name": "DeepSeek V4 Pro" },
          { "id": "deepseek-v4-flash", "name": "DeepSeek V4 Flash" }
        ]
      }
    }
  },
  "gateway": {
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "${GATEWAY_TOKEN}"
    },
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": ["http://${SERVER_IP}:18789"]
    }
  },
  "plugins": {
    "allow": ["openclaw-qqbot"],
    "load": {
      "paths": ["/root/custom_qq_client/openclaw-data/plugins/@tencent-connect/openclaw-qqbot"]
    },
    "entries": {
      "openclaw-qqbot": { "enabled": true, "config": {} }
    }
  },
  "channels": {
    "qqbot": {
      "enabled": true,
      "allowFrom": ["*"],
      "appId": "${QQBOT_APPID:-}",
      "clientSecret": "${QQBOT_SECRET:-}"
    }
  }
}
ENDJSON
    fi

    # 也保存到 openclaw-data
    mkdir -p "$OPENCLAW_DATA"
    cp ~/.openclaw/openclaw.json "$OPENCLAW_DATA/openclaw.json"
    info "已生成 openclaw.json (Token: ${GATEWAY_TOKEN})"
fi

# --- 同步 SOUL.md ---
# 注意：OpenClaw 实际从 agent workspace 目录读取人格文件：
#   <HOME>/.openclaw/workspace/SOUL.md
# 放到 state 根目录（~/.openclaw/SOUL.md）不会被读取。
if [[ -f "$SCRIPT_DIR/openclaw-config/SOUL.md" ]]; then
    mkdir -p ~/.openclaw/workspace
    cp "$SCRIPT_DIR/openclaw-config/SOUL.md" ~/.openclaw/workspace/SOUL.md
    info "已同步 SOUL.md → ~/.openclaw/workspace/SOUL.md"
fi

# --- 同步 skills ---
if [[ -d "$SCRIPT_DIR/skills/bilibili-dynamics" ]]; then
    mkdir -p ~/.openclaw/skills/bilibili-dynamics
    cp -r "$SCRIPT_DIR/skills/bilibili-dynamics/"* ~/.openclaw/skills/bilibili-dynamics/
    # 也同步到 openclaw-data
    mkdir -p "$OPENCLAW_DATA/skills/bilibili-dynamics"
    cp -r "$SCRIPT_DIR/skills/bilibili-dynamics/"* "$OPENCLAW_DATA/skills/bilibili-dynamics/"
    info "已同步 skills"
fi

# --- 修复插件所有权 ---
if [[ -d "$OPENCLAW_DATA/plugins" ]]; then
    chown -R root:root "$OPENCLAW_DATA/plugins" 2>/dev/null || true
    info "已修复插件所有权"
fi

# --- 修复插件 symlink ---
PLUGIN_DIR="$OPENCLAW_DATA/plugins/@tencent-connect/openclaw-qqbot"
if [[ -d "$PLUGIN_DIR" ]]; then
    rm -f "$PLUGIN_DIR/node_modules/openclaw"
    ln -sfn /usr/lib/node_modules/openclaw "$PLUGIN_DIR/node_modules/openclaw"
    info "已修复插件 symlink"
fi

# ===== 5. 安装/启动 systemd 服务 =====
info "[5/6] 配置 systemd 服务..."

mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/openclaw-gateway.service <<'ENDUNIT'
[Unit]
Description=OpenClaw Gateway (v2026.5.7)
After=network-online.target
Wants=network-online.target
StartLimitBurst=5
StartLimitIntervalSec=60

[Service]
ExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 18789
Restart=always
RestartSec=5
RestartPreventExitStatus=78
TimeoutStopSec=30
TimeoutStartSec=30
SuccessExitStatus=0 143
KillMode=control-group
Environment=HOME=/root
Environment=TMPDIR=/tmp
Environment=PATH=/usr/bin:/root/.local/bin:/root/.npm-global/bin:/root/bin:/root/.nix-profile/bin:/root/.local/share/pnpm:/usr/local/bin:/bin:/root/.bun/bin
Environment=OPENCLAW_GATEWAY_PORT=18789
Environment=OPENCLAW_SYSTEMD_UNIT=openclaw-gateway.service
Environment=OPENCLAW_SERVICE_MARKER=openclaw
Environment=OPENCLAW_SERVICE_KIND=gateway
Environment=OPENCLAW_SERVICE_VERSION=2026.5.7

[Install]
WantedBy=default.target
ENDUNIT

systemctl --user daemon-reload
systemctl --user enable openclaw-gateway.service

# 停止可能存在的旧进程
systemctl --user stop openclaw-gateway.service 2>/dev/null || true
PORT_PID=$(ss -tlnp 2>/dev/null | grep ':18789' | grep -oP 'pid=\K[0-9]+' | head -1 || true)
if [[ -n "${PORT_PID:-}" ]]; then
    warn "端口 18789 被 PID=$PORT_PID 占用，正在终止..."
    kill "$PORT_PID" 2>/dev/null || true
    sleep 2
    kill -9 "$PORT_PID" 2>/dev/null || true
fi

# 启动服务
info "启动 OpenClaw 服务..."
systemctl --user start openclaw-gateway.service

# 等待就绪
info "等待网关就绪..."
MAX_WAIT=60; WAITED=0
while [[ $WAITED -lt $MAX_WAIT ]]; do
    if curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:18789" 2>/dev/null | grep -q '200\|301\|302\|304'; then
        info "  网关已就绪（${WAITED}s）"
        break
    fi
    sleep 3; WAITED=$((WAITED + 3))
done
[[ $WAITED -ge $MAX_WAIT ]] && warn "等待超时，请检查日志：journalctl --user -u openclaw-gateway.service -n 50"

# ===== 6. 检查 QQ Bot 状态 =====
info "[6/6] 检查 QQ Bot 频道..."

# 读取当前 token
GATEWAY_TOKEN=$(grep -oP '"token"\s*:\s*"\K[^"]+' ~/.openclaw/openclaw.json 2>/dev/null | head -1 || echo "")
SERVER_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || curl -s --max-time 5 icanhazip.com 2>/dev/null || echo "0.0.0.0")

# ===== 完成 =====
echo ""
echo "============================================"
echo -e "  ${GREEN}部署完成！${NC}"
echo "============================================"
echo ""
echo "控制面板："
echo -e "  ${GREEN}http://${SERVER_IP}:18789/#token=${GATEWAY_TOKEN}${NC}"
echo ""
echo "常用命令："
echo "  systemctl --user status openclaw-gateway       # 查看状态"
echo "  systemctl --user restart openclaw-gateway       # 重启"
echo "  systemctl --user stop openclaw-gateway          # 停止"
echo "  journalctl --user -u openclaw-gateway -f        # 查看日志"
echo "  bash start-openclaw.sh                          # 启动"
echo "  bash stop-openclaw.sh                           # 停止"
echo "  bash update-openclaw.sh                         # 更新"
echo "  bash quick-update.sh                            # 快速迭代"
echo ""
if [[ -n "${QQBOT_APPID:-}" && -n "${QQBOT_SECRET:-}" ]]; then
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
