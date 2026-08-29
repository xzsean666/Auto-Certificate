#!/usr/bin/env bash
# ==============================================================================
# 示例 3: 单台服务器托管与管理多个独立网站 (Multi-Tenancy)
# 架构原理:
#   - ngx-cert-manager 采用解耦的 `/etc/nginx/conf.d/<domain>.conf` 架构。
#   - 每个域名独立配置、独立证书、独立 upstream，增删改查任何一个站点都不会影响其他运行中的服务。
# ==============================================================================

set -euo pipefail

CMD="ngx-cert-manager"
if ! command -v ngx-cert-manager >/dev/null 2>&1; then
    CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ngx-cert-manager"
fi

ADMIN_EMAIL="devops@example.com"

echo "================================================================================"
echo ">>> 开始批量部署与配置多个独立业务站点..."
echo "================================================================================"

# 站点 1: 主站官网 (HTTPS + Node SSR 前端服务 3000 端口)
echo ">>> [1/3] 配置主站官网: www.example.com -> 127.0.0.1:3000"
sudo "$CMD" site add \
    --domain "www.example.com" \
    --upstream "127.0.0.1:3000" \
    --email "$ADMIN_EMAIL" \
    --hsts \
    --ws

# 站点 2: 后端 API 接口平台 (HTTPS + Go/Java 后端服务 8080 端口，开启 100M 上传)
echo ">>> [2/3] 配置后端 API 平台: api.example.com -> 127.0.0.1:8080"
sudo "$CMD" site add \
    --domain "api.example.com" \
    --upstream "127.0.0.1:8080" \
    --email "$ADMIN_EMAIL" \
    --body-size "100m" \
    --hsts \
    --ws

# 站点 3: 内部监控/管理后台 (通过 Cloudflare CDN 代理，HTTP 模式 -> 9090 端口)
echo ">>> [3/3] 配置内部管理后台: admin.example.com -> 127.0.0.1:9090"
sudo "$CMD" site add \
    --domain "admin.example.com" \
    --upstream "127.0.0.1:9090" \
    --no-ssl

echo ""
echo "================================================================================"
echo ">>> 所有站点配置完毕！查看当前多站点综合大盘："
echo "================================================================================"
sudo "$CMD" site list
