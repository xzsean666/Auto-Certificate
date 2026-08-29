#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - tests/run_all.sh
# Comprehensive Test Suite Runner & End-to-End Integration Verification
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
T_GREEN="\033[0;32m"
T_RED="\033[0;31m"
T_YELLOW="\033[0;33m"
T_BLUE="\033[0;34m"
T_BOLD="\033[1m"
T_RESET="\033[0m"

echo -e "${T_BOLD}${T_BLUE}======================================================================${T_RESET}"
echo -e "${T_BOLD}       ngx-cert-manager 全自动化测试套件与端到端集成验证              ${T_RESET}"
echo -e "${T_BOLD}${T_BLUE}======================================================================${T_RESET}"

SUITES_TOTAL=0
SUITES_PASSED=0
SUITES_FAILED=0

# Unit Test Suites
UNIT_TESTS=(
    "test_ui.sh"
    "test_env.sh"
    "test_nginx.sh"
    "test_domain.sh"
    "test_cert.sh"
    "test_proxy.sh"
    "test_systemd.sh"
    "test_remote.sh"
    "test_main_cli.sh"
)

for t in "${UNIT_TESTS[@]}"; do
    test_path="$SCRIPT_DIR/$t"
    if [ -f "$test_path" ]; then
        SUITES_TOTAL=$((SUITES_TOTAL + 1))
        echo ""
        echo -e "${T_YELLOW}>>> 正在运行单元测试套件: ${t} ...${T_RESET}"
        if bash "$test_path"; then
            echo -e "${T_GREEN}✔ 套件 ${t} 测试全部通过${T_RESET}"
            SUITES_PASSED=$((SUITES_PASSED + 1))
        else
            echo -e "${T_RED}✖ 套件 ${t} 测试失败${T_RESET}"
            SUITES_FAILED=$((SUITES_FAILED + 1))
        fi
    fi
done

# End-to-End Integration Scenario Test
echo ""
echo -e "${T_YELLOW}>>> 正在运行端到端 (E2E) 综合链路集成测试 ...${T_RESET}"
SUITES_TOTAL=$((SUITES_TOTAL + 1))

source "$SCRIPT_DIR/test_helper.sh"
E2E_SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$E2E_SANDBOX"' EXIT

export LOG_FILE="$E2E_SANDBOX/e2e.log"
export NO_COLOR=1
export ACME_WEBROOT_DIR="$E2E_SANDBOX/var/www/certbot"
export NGINX_CONF_DIR="$E2E_SANDBOX/etc/nginx/conf.d"
export NGINX_MAIN_CONF="$E2E_SANDBOX/etc/nginx/nginx.conf"
export NGINX_BACKUP_DIR="$E2E_SANDBOX/etc/nginx/conf.d/.backup"
export LETSENCRYPT_LIVE_DIR="$E2E_SANDBOX/etc/letsencrypt/live"
export SYSTEMD_SYSTEM_DIR="$E2E_SANDBOX/etc/systemd/system"
export CRON_D_DIR="$E2E_SANDBOX/etc/cron.d"

# Mock binaries
MOCK_BIN="$E2E_SANDBOX/bin"
mkdir -p "$MOCK_BIN" "$NGINX_CONF_DIR" "$ACME_WEBROOT_DIR" "$SYSTEMD_SYSTEM_DIR" "$CRON_D_DIR"

cat << 'EOF' > "$MOCK_BIN/nginx"
#!/usr/bin/env bash
if [ "$1" = "-v" ]; then echo "nginx version: nginx/1.26.1" >&2; exit 0; fi
if [ "$1" = "-t" ]; then exit 0; fi
if [ "$1" = "-s" ]; then exit 0; fi
exit 0
EOF
chmod +x "$MOCK_BIN/nginx"
export NGINX_BIN="$MOCK_BIN/nginx"

cat << 'EOF' > "$MOCK_BIN/certbot"
#!/usr/bin/env bash
if [ "$1" = "certonly" ]; then
    prev=""
    domain=""
    for i in "$@"; do
        if [ "$prev" = "-d" ]; then domain="$i"; fi
        prev="$i"
    done
    td="$LETSENCRYPT_LIVE_DIR/$domain"
    mkdir -p "$td"
    touch "$td/fullchain.pem" "$td/privkey.pem"
    # Generate valid dummy x509 cert
    openssl req -x509 -nodes -days 90 -newkey rsa:2048 -keyout "$td/privkey.pem" -out "$td/fullchain.pem" -subj "/CN=$domain" 2>/dev/null
    exit 0
fi
if [ "$1" = "renew" ]; then exit 0; fi
exit 0
EOF
chmod +x "$MOCK_BIN/certbot"
export CERTBOT_BIN="$MOCK_BIN/certbot"

# E2E Step 1: Bootstrap Nginx Environment
test_case "[E2E Step 1] Nginx 全局环境 Bootstrap 初始化"
"$PROJECT_ROOT/ngx-cert-manager" nginx bootstrap
assert_file_exists "$NGINX_CONF_DIR/000-default-acme.conf" "Global ACME conf initialized"
assert_file_exists "$NGINX_CONF_DIR/000-websocket-map.conf" "Global WebSocket map initialized"

# E2E Step 2: Add Reverse Proxy Site (CLI flow)
test_case "[E2E Step 2] CLI 一键新增 SSL 反向代理站点"
"$PROJECT_ROOT/ngx-cert-manager" site add \
    --domain "e2e-api.example.com" \
    --upstream "127.0.0.1:9000" \
    --email "admin@example.com" \
    --hsts \
    --ws \
    --skip-dns-check \
    --staging

assert_file_exists "$NGINX_CONF_DIR/e2e-api.example.com.conf" "Site configuration successfully generated"
assert_file_exists "$LETSENCRYPT_LIVE_DIR/e2e-api.example.com/fullchain.pem" "Certificate was acquired"

# E2E Step 3: Verify Site Listing & Details
test_case "[E2E Step 3] 验证站点列表与配置检索"
site_list_res="$("$PROJECT_ROOT/ngx-cert-manager" site list)"
assert_contains "$site_list_res" "e2e-api.example.com" "Site listed in active dashboard"

site_get_res="$("$PROJECT_ROOT/ngx-cert-manager" site get --domain e2e-api.example.com)"
assert_contains "$site_get_res" "proxy_pass http://127.0.0.1:9000;" "Config contains upstream proxy"
assert_contains "$site_get_res" "Strict-Transport-Security" "Config contains HSTS"

# E2E Step 4: Register Timer
test_case "[E2E Step 4] 注册并激活自动续期守护"
"$PROJECT_ROOT/ngx-cert-manager" timer setup
if [ -f "$SYSTEMD_SYSTEM_DIR/certbot-renew.timer" ]; then
    assert_file_exists "$SYSTEMD_SYSTEM_DIR/certbot-renew.timer" "Renewal systemd timer created"
elif [ -f "$CRON_D_DIR/certbot-renew" ]; then
    assert_file_exists "$CRON_D_DIR/certbot-renew" "Renewal cron entry created"
else
    assert_eq "0" "1" "Neither timer nor cron file was created"
fi

# E2E Step 5: Execute Diagnostics
test_case "[E2E Step 5] 全栈系统与服务体检"
diag_res="$("$PROJECT_ROOT/ngx-cert-manager" diagnose)"
assert_contains "$diag_res" "系统与运行环境" "Diagnostics executed cleanly"

test_summary
if [ $? -eq 0 ]; then
    echo -e "${T_GREEN}✔ E2E 综合集成测试通过${T_RESET}"
    SUITES_PASSED=$((SUITES_PASSED + 1))
else
    echo -e "${T_RED}✖ E2E 综合集成测试失败${T_RESET}"
    SUITES_FAILED=$((SUITES_FAILED + 1))
fi

echo ""
echo -e "${T_BOLD}${T_BLUE}======================================================================${T_RESET}"
echo -e "${T_BOLD}测试执行汇总: 共计 ${SUITES_TOTAL} 个套件 | ${T_GREEN}${SUITES_PASSED} 个通过${T_RESET} | ${T_RED}${SUITES_FAILED} 个失败${T_RESET}"
echo -e "${T_BOLD}${T_BLUE}======================================================================${T_RESET}"

if [ "$SUITES_FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
