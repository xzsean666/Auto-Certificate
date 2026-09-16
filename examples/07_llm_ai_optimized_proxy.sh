#!/usr/bin/env bash
# ==============================================================================
# 示例 7: 大语言模型 (LLM/AI) 专属反向代理与深度调优
# 适用场景:
#   - 反向代理 Ollama、vLLM、LocalAI、Open-WebUI、Text-Generation-WebUI 等大模型后端。
#   - 深度思考模型（如 Qwen3.5、DeepSeek-R1）推理耗时长（数分钟），普通反代易发生 504 Gateway Time-out。
#   - 前端或 API 客户端使用 Server-Sent Events (SSE) 逐字流式打字，需禁用 Nginx 8KB 缓冲区。
#   - 结合 --auth-bearer 自动保护无鉴权后端，并保存密钥至 .tokens/。
#
# 优化项说明 (--optimize-llm):
#   1. 超长超时支持: 自动设置 proxy_read_timeout 600s; proxy_send_timeout 600s; (杜绝长思考 504 Gateway Time-out)
#   2. 零缓冲流式响应: proxy_buffering off; proxy_request_buffering off; chunked_transfer_encoding on;
#   3. 低延迟网络加速: tcp_nodelay on; 并下发 X-Accel-Buffering no;
#   4. 大上下文体支持: client_max_body_size 100m; (方便文档向量、图像等多模态上传)
#   5. Lua 极速直出加速: 当 Nginx 包含 Lua 模块时，自动注入 access_by_lua_block；若请求未显式要求深度思考，
#      自动注入 {"reasoning_effort":"none"}，让各类前端与第三方客户端无感零开销直出！
# ==============================================================================

set -euo pipefail

# 1. 设置业务参数
DOMAIN="llm.example.com"
UPSTREAM="127.0.0.1:11434"           # Ollama 默认端口 (或 10001、8000 等)
EMAIL="admin@example.com"

echo ">>> [1/2] 正在为 ${DOMAIN} 配置大模型专属反向代理 (开启 --optimize-llm 与 --auth-bearer)..."

# 2. 定位执行入口
CMD="ngx-cert-manager"
if ! command -v ngx-cert-manager >/dev/null 2>&1; then
    CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ngx-cert-manager"
fi

# 3. 执行部署
# --optimize-llm 自动配置 600s 超时、关闭响应/请求缓冲、启用 SSE 低延迟流式传输
# --auth-bearer  自动生成高强度 Token 并存入 .tokens/ 目录 (权限 600, 已入 .gitignore)
# 如需纯 HTTP 或配合 Cloudflare Flexible 代理，追加 --no-ssl
sudo "$CMD" site add \
    --domain "$DOMAIN" \
    --upstream "$UPSTREAM" \
    --email "$EMAIL" \
    --optimize-llm \
    --auth-bearer \
    --hsts \
    --ws

# 读取保存的 Token
TOKEN_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.tokens/${DOMAIN}.token"
ACTUAL_TOKEN=""
if [ -f "$TOKEN_FILE" ]; then
    ACTUAL_TOKEN="$(cat "$TOKEN_FILE")"
fi

echo ""
echo ">>> [2/2] 部署完成！"
[ -n "$ACTUAL_TOKEN" ] && echo "已保存凭据: $TOKEN_FILE (Token: $ACTUAL_TOKEN)"
echo ""
echo "测试 SSE 实时流式响应 (打字机效果，秒级首字响应):"
echo "  curl -N -s -H \"Authorization: Bearer ${ACTUAL_TOKEN:-<your-token>}\" \\"
echo "       -H \"Content-Type: application/json\" \\"
echo "       https://${DOMAIN}/v1/chat/completions \\"
echo "       -d '{\"model\":\"qwen3.5:2b\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}],\"stream\":true}'"
