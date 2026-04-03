#!/bin/bash
set -e

# 1. 添加 MODELSTUDIO_API_KEY 到 .env（如果还没有）
if ! grep -q 'MODELSTUDIO_API_KEY' openclaw-config/.env 2>/dev/null; then
    echo 'MODELSTUDIO_API_KEY=sk-f41c96a153d6402593caae7803da1d16' >> openclaw-config/.env
    echo "已添加 MODELSTUDIO_API_KEY 到 .env"
fi

# 2. 修改 openclaw.json 中的模型名
sed -i 's|openai/qwen3.5-plus|modelstudio/qwen3.5-plus|' openclaw-data/openclaw.json
echo "已更新模型为 modelstudio/qwen3.5-plus"

# 3. 确认
grep model openclaw-data/openclaw.json

# 4. 重启容器
docker compose -f docker-compose.prod.yml down
docker compose -f docker-compose.prod.yml up -d
sleep 5
docker compose -f docker-compose.prod.yml logs --tail 5
