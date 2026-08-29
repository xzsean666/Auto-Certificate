#!/usr/bin/env bash
# ==============================================================================
# 示例 2: 纯 HTTP 80 端口反向代理 (Cloudflare CDN / 边缘 SSL 代理场景)
# 适用场景:
#   - 域名开启了 Cloudflare 小黄云代理 (Proxied / CDN)。
#   - Cloudflare SSL 模式设置为 "Flexible" (访客到 CF 走 HTTPS，CF 到源站走 HTTP 80)。
#   - 或者内网服务器仅需 HTTP 80 端口转发，无需在源站申请 SSL 证书。
# ==============================================================================

set -euo pipefail

# 1. 设置业务参数
DOMAIN="cf-app.example.com"
UPSTREAM="127.0.0.1:3000"       # 本地 Web 服务 (例如: Next.js / Vue / React / Docker)
MAX_BODY_SIZE="50m"

echo ">>> [1/2] 正在配置纯 HTTP 80 反向代理站点: ${DOMAIN} (无需申请源站证书)..."

CMD="ngx-cert-manager"
if ! command -v ngx-cert-manager >/dev/null 2>&1; then
    CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ngx-cert-manager"
fi

# 2. 传入 --no-ssl (或 --http-only)
sudo "$CMD" site add \
    --domain "$DOMAIN" \
    --upstream "$UPSTREAM" \
    --body-size "$MAX_BODY_SIZE" \
    --ws \
    --no-ssl

echo ">>> [2/2] HTTP 模式反向代理配置成功！"
echo "提示: 源站仍保留了 /.well-known/acme-challenge/ 穿透，日后如需切换至 Cloudflare Full (Strict) SSL，直接再次运行申请证书即可无缝升级。"
