#!/usr/bin/env bash
# ==============================================================================
# 示例 6: 无鉴权后端添加 Nginx Bearer Token 访问鉴权
# 适用场景:
#   - 反代本地无鉴权的后端服务 (例如: 本地 Ollama LLM、Prometheus、Node/Python 内部接口)。
#   - 在 Nginx 边缘网关层强制校验 Authorization: Bearer <token> 请求头。
#   - 未携带 Token 或 Token 错误时直接返回 HTTP 401 Unauthorized (含 JSON 错误信息)。
#   - 自动放行浏览器 CORS OPTIONS 预检请求，避免跨域前端访问被拦截。
#   - 支持单 Token (sk-xxxx) 或多 Token 逗号分隔 (token1, token2)。
# ==============================================================================

set -euo pipefail

# 1. 设置业务参数
DOMAIN="ai.example.com"
UPSTREAM="127.0.0.1:11434"           # 本地无鉴权服务 (例如: 本地 Ollama)
# 若留空或填 "auto"，系统会自动生成高强度随机 Token 并保存至 .tokens/ 目录 (已加入 .gitignore)
BEARER_TOKEN="auto"                  # 可填 "auto" 自动生成，亦可填自定义如 "sk-my-secret-token"
EMAIL="admin@example.com"

echo ">>> [1/2] 正在为 ${DOMAIN} 配置带 Bearer 鉴权的 HTTPS 反向代理 (未指定 Token 将自动生成并写入 .tokens/)..."

# 2. 定位执行入口
CMD="ngx-cert-manager"
if ! command -v ngx-cert-manager >/dev/null 2>&1; then
    CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ngx-cert-manager"
fi

# 3. 部署带 Bearer 鉴权的反向代理站点
# 使用 --auth-bearer (不传值或传 auto) 自动生成并存入 .tokens/ 目录
# 若为纯 HTTP / Cloudflare 边缘代理模式，可追加 --no-ssl
sudo "$CMD" site add \
    --domain "$DOMAIN" \
    --upstream "$UPSTREAM" \
    --email "$EMAIL" \
    --auth-bearer "$BEARER_TOKEN" \
    --hsts \
    --ws

# 读取保存的 Token 密钥
TOKEN_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.tokens/${DOMAIN}.token"
ACTUAL_TOKEN=""
if [ -f "$TOKEN_FILE" ]; then
    ACTUAL_TOKEN="$(cat "$TOKEN_FILE")"
fi

echo ""
echo ">>> [2/2] 部署完成！"
[ -n "$ACTUAL_TOKEN" ] && echo "已保存凭据: $TOKEN_FILE (Token: $ACTUAL_TOKEN)"
echo "测试鉴权效果:"
echo "  1. 未携带 Token 请求 (预期返回 HTTP 401 Unauthorized):"
echo "     curl -i https://${DOMAIN}/api/tags"
echo ""
echo "  2. 携带正确 Bearer Token 请求 (预期正常代理至后端 200 OK):"
echo "     curl -i -H \"Authorization: Bearer ${ACTUAL_TOKEN:-sk-token}\" https://${DOMAIN}/api/tags"
