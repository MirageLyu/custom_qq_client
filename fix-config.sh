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
    "disabled": [
      "anthropic",
      "anthropic-vertex",
      "amazon-bedrock",
      "byteplus",
      "chutes",
      "cloudflare-ai-gateway",
      "copilot-proxy",
      "deepseek",
      "fal",
      "github-copilot",
      "google",
      "huggingface",
      "kilocode",
      "kimi",
      "litellm",
      "microsoft-foundry",
      "minimax",
      "mistral",
      "moonshot",
      "nvidia",
      "ollama",
      "opencode",
      "opencode-go",
      "openrouter",
      "qianfan",
      "sglang",
      "synthetic",
      "together",
      "venice",
      "vercel-ai-gateway",
      "vllm",
      "volcengine",
      "xai",
      "xiaomi",
      "zai"
    ]
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
