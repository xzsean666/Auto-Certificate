#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for ngx-cert-manager CLI interface
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_main.log"
export NO_COLOR=1

# Override paths into sandbox
export ACME_WEBROOT_DIR="$SANDBOX/var/www/certbot"
export NGINX_CONF_DIR="$SANDBOX/etc/nginx/conf.d"
export NGINX_MAIN_CONF="$SANDBOX/etc/nginx/nginx.conf"
export NGINX_BACKUP_DIR="$SANDBOX/etc/nginx/conf.d/.backup"
export LETSENCRYPT_LIVE_DIR="$SANDBOX/etc/letsencrypt/live"
export SYSTEMD_SYSTEM_DIR="$SANDBOX/etc/systemd/system"
export CRON_D_DIR="$SANDBOX/etc/cron.d"

MAIN_BIN="$PROJECT_ROOT/ngx-cert-manager"
WRAPPER_BIN="$PROJECT_ROOT/main.sh"

# Test 1: --version and -v on both ngx-cert-manager and main.sh
test_case "ngx-cert-manager and main.sh --version outputs version string"
ver_out="$("$MAIN_BIN" --version)"
assert_contains "$ver_out" "ngx-cert-manager v1.0.0" "--version output valid on binary"

ver_wrapper="$("$WRAPPER_BIN" -v)"
assert_contains "$ver_wrapper" "ngx-cert-manager v1.0.0" "-v output valid on main.sh wrapper"

# Test 2: --help and -h
test_case "ngx-cert-manager --help outputs comprehensive CLI usage"
help_out="$("$MAIN_BIN" --help)"
assert_contains "$help_out" "使用方法:" "Help contains usage section"
assert_contains "$help_out" "site add" "Help contains site add subcommand"
assert_contains "$help_out" "cert issue" "Help contains cert issue subcommand"
assert_contains "$help_out" "--ssh" "Help contains --ssh option"
assert_contains "$help_out" "--ssh-key" "Help contains --ssh-key option"
assert_contains "$help_out" "--dns-cf" "Help contains --dns-cf option"

# Test 3: site list subcommand
test_case "ngx-cert-manager site list runs successfully"
mkdir -p "$NGINX_CONF_DIR"
site_out="$("$MAIN_BIN" site list)"
assert_contains "$site_out" "当前受管反向代理站点列表" "site list renders header"

# Test 4: cert list subcommand
test_case "ngx-cert-manager cert list runs successfully"
mkdir -p "$LETSENCRYPT_LIVE_DIR"
cert_out="$("$MAIN_BIN" cert list)"
assert_contains "$cert_out" "受管 Let's Encrypt 证书大盘" "cert list renders header"

# Test 5: nginx status subcommand
test_case "ngx-cert-manager nginx status runs successfully"
ngx_out="$("$MAIN_BIN" nginx status)"
assert_contains "$ngx_out" "Nginx 状态:" "nginx status output valid"

# Test 6: timer status subcommand
test_case "ngx-cert-manager timer status runs successfully"
mkdir -p "$CRON_D_DIR"
timer_out="$("$MAIN_BIN" timer status || true)"
assert_contains "$timer_out" "自动化续期守护状态" "timer status renders header"

# Test 7: diagnose subcommand
test_case "ngx-cert-manager diagnose runs system health check"
diag_out="$("$MAIN_BIN" diagnose)"
assert_contains "$diag_out" "系统与运行环境" "diagnose includes system section"
assert_contains "$diag_out" "Nginx 服务状态" "diagnose includes Nginx section"
assert_contains "$diag_out" "网络与端口占用检测" "diagnose includes network section"

# Test 8: Invalid subcommand handling
test_case "ngx-cert-manager rejects invalid subcommand"
err_code=0
"$MAIN_BIN" non_existent_subcmd 2>&1 || err_code=$?
assert_status_code "$err_code" 1 "ngx-cert-manager exited with code 1 on unknown subcommand"

test_summary
