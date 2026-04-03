#!/bin/bash
set -e

cat > openclaw-data/openclaw.json <<'EOF'
{
  "agents": {
    "defaults": {
      "model": "openai/qwen3.5-plus",
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      },
      "compaction": {
        "mode": "safeguard"
      }
    }
  },
  "plugins": {
    "entries": {
      "anthropic": { "enabled": false },
      "anthropic-vertex": { "enabled": false },
      "amazon-bedrock": { "enabled": false },
      "byteplus": { "enabled": false },
      "chutes": { "enabled": false },
      "cloudflare-ai-gateway": { "enabled": false },
      "copilot-proxy": { "enabled": false },
      "deepseek": { "enabled": false },
      "fal": { "enabled": false },
      "github-copilot": { "enabled": false },
      "google": { "enabled": false },
      "huggingface": { "enabled": false },
      "kilocode": { "enabled": false },
      "kimi": { "enabled": false },
      "litellm": { "enabled": false },
      "microsoft-foundry": { "enabled": false },
      "minimax": { "enabled": false },
      "mistral": { "enabled": false },
      "moonshot": { "enabled": false },
      "nvidia": { "enabled": false },
      "ollama": { "enabled": false },
      "opencode": { "enabled": false },
      "opencode-go": { "enabled": false },
      "openrouter": { "enabled": false },
      "qianfan": { "enabled": false },
      "sglang": { "enabled": false },
      "synthetic": { "enabled": false },
      "together": { "enabled": false },
      "venice": { "enabled": false },
      "vercel-ai-gateway": { "enabled": false },
      "vllm": { "enabled": false },
      "volcengine": { "enabled": false },
      "xai": { "enabled": false },
      "xiaomi": { "enabled": false },
      "zai": { "enabled": false }
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

sudo chown -R 1000:1000 openclaw-data
docker compose -f docker-compose.prod.yml restart
sleep 5
docker compose -f docker-compose.prod.yml logs --tail 5
