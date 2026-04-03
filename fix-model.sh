#!/bin/bash
set -e

cat > openclaw-data/openclaw.json <<'EOF'
{
  "agents": {
    "defaults": {
      "model": "dashscope/qwen3.5-plus",
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      },
      "compaction": {
        "mode": "safeguard"
      }
    }
  },
  "models": {
    "providers": {
      "dashscope": {
        "baseUrl": "https://dashscope.aliyuncs.com/compatible-mode/v1",
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
      "token": "aaaedf9e081bfe4cff74cd2f70dca1eadb9d933a9f52cae2"
    },
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true,
      "allowedOrigins": ["http://121.43.251.21:18789"]
    }
  }
}
EOF

# 确保 .env 里有 DASHSCOPE_API_KEY
if ! grep -q 'DASHSCOPE_API_KEY' openclaw-config/.env 2>/dev/null; then
    echo 'DASHSCOPE_API_KEY=sk-f41c96a153d6402593caae7803da1d16' >> openclaw-config/.env
    echo "已添加 DASHSCOPE_API_KEY"
fi

sudo chown -R 1000:1000 openclaw-data
docker compose -f docker-compose.prod.yml down
docker compose -f docker-compose.prod.yml up -d
sleep 5
docker compose -f docker-compose.prod.yml logs --tail 10
