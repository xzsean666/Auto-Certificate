#!/usr/bin/env bash
# ==============================================================================
# 示例 4: Unix Domain Socket (UDS) 高性能本地反向代理
# 适用场景:
#   - Python (Gunicorn / Uvicorn / FastAPI / Django)
#   - PHP-FPM / Ruby Puma
#   - 使用 Unix Socket 替代 TCP 端口通信，减少 TCP 握手开销，提高并发吞吐量与安全性。
# ==============================================================================

set -euo pipefail

DOMAIN="app-socket.example.com"
SOCKET_PATH="unix:/run/gunicorn.sock:"       # Nginx Unix Socket 格式 (末尾冒号)
EMAIL="admin@example.com"

CMD="ngx-cert-manager"
if ! command -v ngx-cert-manager >/dev/null 2>&1; then
    CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ngx-cert-manager"
fi

echo ">>> 正在配置 Unix Domain Socket 反向代理: ${DOMAIN} -> ${SOCKET_PATH}..."

sudo "$CMD" site add \
    --domain "$DOMAIN" \
    --upstream "$SOCKET_PATH" \
    --email "$EMAIL" \
    --hsts \
    --ws

echo ">>> Unix Socket 反代站点配置成功！"
sudo "$CMD" site get --domain "$DOMAIN"
