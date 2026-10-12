#!/bin/bash
# ============================================
# 激活朋友的 QQ Bot（填入新的 AppID / AppSecret 后启用频道）
# 用法:
#   QQBOT_APPID=xxx QQBOT_SECRET=yyy bash activate-friend-bot.sh
# 或:
#   bash activate-friend-bot.sh <APPID> <APPSECRET>
# ============================================
set -euo pipefail

FRIEND_CONFIG=/root/qqbot-friend/.openclaw/openclaw.json
SERVICE=openclaw-gateway-friend.service

APPID="${1:-${QQBOT_APPID:-}}"
SECRET="${2:-${QQBOT_SECRET:-}}"

if [[ -z "$APPID" || -z "$SECRET" ]]; then
    echo "错误：缺少 AppID / AppSecret。" >&2
    echo "  用法: bash activate-friend-bot.sh <APPID> <APPSECRET>" >&2
    echo "  （AppID / AppSecret 在 https://q.qq.com/ 新机器人后台获取）" >&2
    exit 1
fi

python3 - "$FRIEND_CONFIG" "$APPID" "$SECRET" <<'PY'
import json, sys
path, appid, secret = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(path))
qq = cfg.setdefault("channels", {}).setdefault("qqbot", {})
qq["enabled"] = True
qq["appId"] = appid
qq["clientSecret"] = secret
json.dump(cfg, open(path, "w"), indent=2, ensure_ascii=False)
print(f"已写入 {path}: appId={appid} enabled=true")
PY

systemctl --user restart "$SERVICE"
echo "已重启 $SERVICE"

sleep 10
if curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:18790 2>/dev/null | grep -q '200'; then
    echo "✓ 朋友网关健康 (http://127.0.0.1:18790 → 200)"
else
    echo "⚠ 网关尚未就绪，请稍后检查: systemctl --user status $SERVICE" >&2
fi

echo ""
echo "下一步：到 https://q.qq.com/ 把服务器公网 IP 加入新机器人的回调白名单。"
echo "查看日志: journalctl --user -u $SERVICE -f"
