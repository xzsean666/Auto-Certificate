#!/usr/bin/env bash
# ==============================================================================
# 示例 8: 根据域名更新、轮转或移除 Bearer Token 访问鉴权
# 适用场景:
#   - 密钥定期轮转安全要求 (Secret Rotation)。
#   - 密钥泄露时一键紧急重新生成并平滑生效 (Zero Downtime)。
#   - 自定义更换为特定 API Key (支持多个 Token，逗号分隔)。
#   - 取消鉴权保护 (恢复纯透明反向代理)。
#   - 查询与导出已保存的域名 Token 凭证。
# ==============================================================================

set -euo pipefail

# 1. 设置业务参数
DOMAIN="server-10001.002788.xyz"

# 2. 定位执行入口
CMD="ngx-cert-manager"
if ! command -v ngx-cert-manager >/dev/null 2>&1; then
    CMD="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ngx-cert-manager"
fi

echo "================================================================================"
echo " 域名 Bearer Token 动态轮转与更新运维示例"
echo " 目标域名: ${DOMAIN}"
echo "================================================================================"

echo ""
echo ">>> [步骤 1] 查看当前域名的 Bearer Token 凭证:"
sudo "$CMD" token get --domain "$DOMAIN"

echo ""
echo ">>> [步骤 2] 自动轮转生成全新的高强度 Bearer Token (热重载生效，零中断):"
sudo "$CMD" site update-bearer --domain "$DOMAIN"

echo ""
echo ">>> [步骤 3] 查看轮转后更新的新 Token:"
sudo "$CMD" token get --domain "$DOMAIN"

echo ""
echo ">>> [步骤 4] (可选) 手动更新为指定的自定义 Token:"
CUSTOM_TOKEN="sk-custom-secret-key-$(date +%s)"
echo "正在将 ${DOMAIN} 的 Token 更换为: ${CUSTOM_TOKEN}"
sudo "$CMD" site update-bearer --domain "$DOMAIN" --token "$CUSTOM_TOKEN"

echo ""
echo ">>> [步骤 5] 列出系统中所有反代站点配置的 Bearer Token 凭据大盘:"
sudo "$CMD" token list

echo ""
echo "================================================================================"
echo "✔ 演示完成！"
echo "提示:"
echo "  - 若要彻底移除 ${DOMAIN} 的鉴权保护，可执行:"
echo "    sudo ${CMD} site update-bearer --domain ${DOMAIN} --remove"
echo "    或: sudo ${CMD} token delete --domain ${DOMAIN}"
echo "================================================================================"
