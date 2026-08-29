#!/usr/bin/env bash
# ==============================================================================
# 示例 1: 标准 HTTPS 生产反向代理配置
# 适用场景:
#   - 独立公网服务器，拥有域名直接指向本机公网 IP。
#   - 自动化申请 Let's Encrypt 证书 + 配置 HTTPS 443 + 开启 HTTP 301 强制重定向。
#   - 开启现代安全 HSTS 头部与 WebSocket 支持。
# ==============================================================================

set -euo pipefail

# 1. 设置业务参数
DOMAIN="api.example.com"
UPSTREAM="127.0.0.1:8080"       # 本地后端服务端口 (例如: SpringBoot / Go / Node.js)
EMAIL="admin@example.com"       # Let's Encrypt 证书到期通知邮箱
MAX_BODY_SIZE="100m"            # 允许上传的最大文件大小

echo ">>> [1/2] 正在为 ${DOMAIN} 申请 SSL 证书并配置生产级 HTTPS 反向代理..."

# 2. 调用 ngx-cert-manager 进行全自动配置 (支持 ngx-cert-manager 或短别名 ngx-cert)
CMD="ngx-cert-manager"
if ! command -v ngx-cert-manager >/dev/null 2>&1; then
    # 若未安装至系统路径，尝试使用当前仓库路径
    CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ngx-cert-manager"
fi

sudo "$CMD" site add \
    --domain "$DOMAIN" \
    --upstream "$UPSTREAM" \
    --email "$EMAIL" \
    --hsts \
    --ws \
    --body-size "$MAX_BODY_SIZE"

echo ">>> [2/2] 部署完成！查看当前站点列表与证书状态："
sudo "$CMD" site list
