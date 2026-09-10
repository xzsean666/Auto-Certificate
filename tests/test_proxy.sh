#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for lib/proxy.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_proxy.log"
export NO_COLOR=1

# Override paths into sandbox
export ACME_WEBROOT_DIR="$SANDBOX/var/www/certbot"
export NGINX_CONF_DIR="$SANDBOX/etc/nginx/conf.d"
export NGINX_MAIN_CONF="$SANDBOX/etc/nginx/nginx.conf"
export NGINX_BACKUP_DIR="$SANDBOX/etc/nginx/conf.d/.backup"
export LETSENCRYPT_LIVE_DIR="$SANDBOX/etc/letsencrypt/live"

source "$PROJECT_ROOT/config.env"
source "$PROJECT_ROOT/lib/ui.sh"
source "$PROJECT_ROOT/lib/env.sh"
source "$PROJECT_ROOT/lib/nginx.sh"
source "$PROJECT_ROOT/lib/domain.sh"
source "$PROJECT_ROOT/lib/cert.sh"
source "$PROJECT_ROOT/lib/proxy.sh"

# Mock mock binaries
mock_bin_dir="$SANDBOX/bin"
mkdir -p "$mock_bin_dir"

cat << 'EOF' > "$mock_bin_dir/nginx"
#!/usr/bin/env bash
if [ "$1" = "-v" ]; then
    echo "nginx version: nginx/1.26.0" >&2
    exit 0
fi
if [ "$1" = "-t" ]; then
    if [ -f "$TEST_FAIL_NGINX_FLAG" ]; then
        echo "nginx: [emerg] syntax error simulation in test" >&2
        exit 1
    fi
    exit 0
fi
if [ "$1" = "-s" ] && [ "$2" = "reload" ]; then
    exit 0
fi
exit 0
EOF
chmod +x "$mock_bin_dir/nginx"
export NGINX_BIN="$mock_bin_dir/nginx"
export TEST_FAIL_NGINX_FLAG="$SANDBOX/fail_nginx_test"

cat << 'EOF' > "$mock_bin_dir/certbot"
#!/usr/bin/env bash
if [ "$1" = "certonly" ]; then
    domain=""
    for i in "$@"; do
        if [ "$prev" = "-d" ]; then
            domain="$i"
        fi
        prev="$i"
    done
    target_dir="$LETSENCRYPT_LIVE_DIR/$domain"
    mkdir -p "$target_dir"
    touch "$target_dir/fullchain.pem"
    touch "$target_dir/privkey.pem"
    exit 0
fi
exit 0
EOF
chmod +x "$mock_bin_dir/certbot"
export CERTBOT_BIN="$mock_bin_dir/certbot"

# Test 1: Upstream normalization
test_case "proxy_normalize_upstream prepends http:// when missing"
assert_eq "$(proxy_normalize_upstream "127.0.0.1:8080")" "http://127.0.0.1:8080" "Plain host:port normalized"
assert_eq "$(proxy_normalize_upstream "https://upstream.internal:8443")" "https://upstream.internal:8443" "HTTPS kept"
assert_eq "$(proxy_normalize_upstream "http://unix:/run/gunicorn.sock:")" "http://unix:/run/gunicorn.sock:" "Unix socket kept"

# Test 2: Modern Nginx (>= 1.25.1) and IPv6 rendering
test_case "proxy_render_config generates modern http2 and IPv6 directives"
HAS_IPV6=1
rendered="$(proxy_render_config "api.example.com" "127.0.0.1:4000" "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "1" "100m" "1")"
assert_contains "$rendered" "server_name api.example.com;" "Contains server_name"
assert_contains "$rendered" "http2 on;" "Contains modern http2 directive"
assert_contains "$rendered" "listen 443 ssl;" "Contains modern listen 443 ssl;"
assert_contains "$rendered" "listen [::]:443 ssl;" "Contains IPv6 listen 443"
assert_contains "$rendered" "client_max_body_size 100m;" "Contains custom body size 100m"
assert_contains "$rendered" "Strict-Transport-Security" "Contains HSTS header"
assert_contains "$rendered" "proxy_pass http://127.0.0.1:4000;" "Contains normalized proxy_pass"

# Test 3: Legacy Nginx (< 1.25.1) and no IPv6
test_case "proxy_render_config generates legacy listen http2 when Nginx < 1.25.1 and omits IPv6"
# Mock legacy nginx
nginx_supports_http2_directive() { return 1; }
HAS_IPV6=0
rendered_legacy="$(proxy_render_config "legacy.example.com" "127.0.0.1:5000" "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "0" "20m" "1")"
assert_contains "$rendered_legacy" "listen 443 ssl http2;" "Contains legacy listen 443 ssl http2"
assert_not_contains "$rendered_legacy" "http2 on;" "Does NOT contain http2 directive"
assert_not_contains "$rendered_legacy" "listen [::]:443" "Does NOT contain IPv6"
assert_not_contains "$rendered_legacy" "Strict-Transport-Security" "Does NOT contain HSTS when disabled"

# Test 4: Transactional Write & Atomic Rollback - Success Case
test_case "proxy_apply_site_config successfully writes config file and reloads"
rm -f "$TEST_FAIL_NGINX_FLAG"
nginx_supports_http2_directive() { return 0; }
content_valid="$(proxy_render_config "app.test.com" "127.0.0.1:8000" "/tmp/c.pem" "/tmp/k.pem")"

if proxy_apply_site_config "app.test.com" "$content_valid"; then
    assert_eq "0" "0" "proxy_apply_site_config succeeded"
else
    assert_eq "1" "0" "proxy_apply_site_config should succeed"
fi

assert_file_exists "$NGINX_CONF_DIR/app.test.com.conf" "app.test.com.conf created"

# Test 5: Transactional Write & Atomic Rollback - Failure Case
test_case "proxy_apply_site_config rolls back when nginx_test fails"
# Save original content
echo "ORIGINAL_WORKING_CONFIG" > "$NGINX_CONF_DIR/app.test.com.conf"
# Trigger syntax failure
touch "$TEST_FAIL_NGINX_FLAG"

apply_ret=0
proxy_apply_site_config "app.test.com" "BROKEN_NEW_CONFIG" || apply_ret=$?
assert_status_code "$apply_ret" 1 "proxy_apply_site_config returned 1 on syntax failure"

# Verify rollback restored original file
restored_content="$(cat "$NGINX_CONF_DIR/app.test.com.conf")"
assert_eq "$restored_content" "ORIGINAL_WORKING_CONFIG" "Original config restored from backup"

# Test 6: Site Listing & Query
test_case "proxy_list_sites and proxy_get_site display configured sites"
rm -f "$TEST_FAIL_NGINX_FLAG"
# Write a valid test site
proxy_apply_site_config "portal.example.com" "$content_valid"
list_out="$(proxy_list_sites)"
assert_contains "$list_out" "portal.example.com" "List output contains portal.example.com"

get_out="$(proxy_get_site "portal.example.com")"
assert_contains "$get_out" "server_name" "Get site output returns config"

# Test 7: Delete site
test_case "proxy_delete_site archives and deletes site configuration"
proxy_delete_site "portal.example.com"
if [ ! -f "$NGINX_CONF_DIR/portal.example.com.conf" ]; then
    assert_eq "0" "0" "Site configuration removed"
else
    assert_eq "1" "0" "Site configuration should have been deleted"
fi

# Test 8: HTTP-Only / Cloudflare Proxy Configuration
test_case "proxy_render_http_config and proxy_add_site --no-ssl generates HTTP-only reverse proxy"
rendered_http="$(proxy_render_http_config "cf-app.example.com" "127.0.0.1:3000" "30m" "1")"
assert_contains "$rendered_http" "server_name cf-app.example.com;" "Contains HTTP server_name"
assert_contains "$rendered_http" "listen 80;" "Contains listen 80"
assert_not_contains "$rendered_http" "listen 443" "Does not contain listen 443"
assert_not_contains "$rendered_http" "ssl_certificate" "Does not contain ssl directives"
assert_contains "$rendered_http" "proxy_pass http://127.0.0.1:3000;" "Contains HTTP proxy_pass"

# Add site in HTTP mode
proxy_add_site "cf-app.example.com" "127.0.0.1:3000" "" "0" "30m" "1" "1" "0" "1" "0"
assert_file_exists "$NGINX_CONF_DIR/cf-app.example.com.conf" "HTTP-only site conf created"

# Test 9: proxy_add_site with Cloudflare DNS-01 mode
test_case "proxy_add_site with Cloudflare DNS-01 acquires cert and creates SSL proxy"
proxy_add_site "cf-dns.example.com" "127.0.0.1:10101" "admin@example.com" "1" "50m" "1" "0" "1" "1" "1" "dns_cf" "token_xyz_456"
assert_file_exists "$NGINX_CONF_DIR/cf-dns.example.com.conf" "SSL site conf created with DNS-01 mode"
conf_cf="$(cat "$NGINX_CONF_DIR/cf-dns.example.com.conf")"
assert_contains "$conf_cf" "proxy_pass http://127.0.0.1:10101;" "Contains upstream target"
assert_contains "$conf_cf" "ssl_certificate" "Contains SSL directives"

test_summary
