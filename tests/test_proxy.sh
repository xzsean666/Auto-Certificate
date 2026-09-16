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

# Test 10: proxy_render_config with custom https_port
test_case "proxy_render_config and proxy_add_site supports custom and auto-detected https_port"
rendered_custom="$(proxy_render_config "custom-port.example.com" "127.0.0.1:5000" "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "1" "50m" "1" "8443")"
assert_contains "$rendered_custom" "listen 8443 ssl;" "Contains custom listen 8443 ssl;"

proxy_add_site "custom-port.example.com" "127.0.0.1:5000" "admin@example.com" "1" "50m" "1" "0" "1" "1" "1" "dns_cf" "token_123" "8443"
assert_file_exists "$NGINX_CONF_DIR/custom-port.example.com.conf" "Custom port site conf created"
conf_custom="$(cat "$NGINX_CONF_DIR/custom-port.example.com.conf")"
assert_contains "$conf_custom" "listen 8443 ssl;" "Site config contains listen 8443 ssl;"

# Test 11: Bearer Token authentication rendering
test_case "proxy_render_config and proxy_render_http_config generate Bearer auth directives"
rendered_auth="$(proxy_render_config "secure-api.example.com" "127.0.0.1:8000" "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "1" "50m" "1" "443" "sk-secret-token-123")"
assert_contains "$rendered_auth" 'set $auth_valid 0;' "Contains auth_valid initialization"
assert_contains "$rendered_auth" 'Bearer\s+(sk-secret-token-123)' "Contains Bearer token regex check"
assert_contains "$rendered_auth" '$request_method = OPTIONS' "Contains OPTIONS CORS preflight bypass"
assert_contains "$rendered_auth" 'return 401' "Contains 401 Unauthorized return"
assert_contains "$rendered_auth" 'WWW-Authenticate' "Contains WWW-Authenticate response header"

# Multi-token rendering
rendered_multi="$(proxy_render_config "multi-auth.example.com" "127.0.0.1:8000" "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "1" "50m" "1" "443" "token1, token2, token3")"
assert_contains "$rendered_multi" 'Bearer\s+(token1|token2|token3)' "Contains multi-token alternation regex"

# HTTP-only with Bearer auth
rendered_http_auth="$(proxy_render_http_config "http-auth.example.com" "127.0.0.1:8000" "50m" "1" "sk-http-123")"
assert_contains "$rendered_http_auth" 'Bearer\s+(sk-http-123)' "Contains Bearer auth in HTTP mode"

# Test 12: proxy_add_site with Bearer Token auth
test_case "proxy_add_site persists Bearer Token authentication into nginx config and .tokens file"
export NGX_TOKENS_DIR="$SANDBOX/.tokens"
proxy_add_site "bearer-site.example.com" "127.0.0.1:9090" "admin@example.com" "1" "50m" "1" "0" "1" "1" "1" "dns_cf" "token_xyz" "443" "sk-prod-super-secret"
assert_file_exists "$NGINX_CONF_DIR/bearer-site.example.com.conf" "Bearer auth site conf created"
conf_bearer="$(cat "$NGINX_CONF_DIR/bearer-site.example.com.conf")"
assert_contains "$conf_bearer" 'Bearer\s+(sk-prod-super-secret)' "Site config contains Bearer check"
assert_contains "$conf_bearer" 'return 401' "Site config returns 401 when unauthenticated"
assert_file_exists "$NGX_TOKENS_DIR/bearer-site.example.com.token" "Custom token saved to .tokens/ directory"

# Test 13: proxy_add_site auto-generates Bearer token when token is 'auto' and stores to gitignored .tokens/
test_case "proxy_add_site auto-generates Bearer Token into .tokens directory"
proxy_add_site "auto-bearer.example.com" "127.0.0.1:9091" "admin@example.com" "1" "50m" "1" "0" "1" "1" "1" "dns_cf" "token_xyz" "443" "auto"
assert_file_exists "$NGINX_CONF_DIR/auto-bearer.example.com.conf" "Auto-bearer site conf created"
assert_file_exists "$NGX_TOKENS_DIR/auto-bearer.example.com.token" "Token saved in .tokens directory"
gen_tok="$(cat "$NGX_TOKENS_DIR/auto-bearer.example.com.token")"
assert_contains "$gen_tok" "sk-" "Generated token has sk- prefix"
conf_auto="$(cat "$NGINX_CONF_DIR/auto-bearer.example.com.conf")"
assert_contains "$conf_auto" "$gen_tok" "Nginx config contains the auto-generated token"

# Test 14: proxy_render_config and proxy_render_http_config with optimize_llm
test_case "proxy_render_config with optimize_llm enables zero-buffering, 600s timeouts, and 100m body size"
rendered_llm="$(proxy_render_config "llm-api.example.com" "127.0.0.1:11434" "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "1" "" "1" "443" "sk-test" "1")"
assert_contains "$rendered_llm" "LLM-Optimization: enabled" "SSL config header contains LLM-Optimization enabled"
assert_contains "$rendered_llm" "proxy_buffering off;" "SSL config disables proxy_buffering"
assert_contains "$rendered_llm" "proxy_request_buffering off;" "SSL config disables proxy_request_buffering"
assert_contains "$rendered_llm" "tcp_nodelay on;" "SSL config enables tcp_nodelay"
assert_contains "$rendered_llm" "proxy_read_timeout 600s;" "SSL config sets 600s read timeout"
assert_contains "$rendered_llm" "proxy_send_timeout 600s;" "SSL config sets 600s send timeout"
assert_contains "$rendered_llm" "client_max_body_size 100m;" "SSL config defaults to 100m client body size in LLM mode"

# HTTP mode with LLM optimization
rendered_http_llm="$(proxy_render_http_config "llm-http.example.com" "127.0.0.1:10001" "" "1" "" "1")"
assert_contains "$rendered_http_llm" "LLM-Optimization: enabled" "HTTP config contains LLM-Optimization enabled"
assert_contains "$rendered_http_llm" "proxy_buffering off;" "HTTP config disables proxy_buffering"
assert_contains "$rendered_http_llm" "proxy_read_timeout 600s;" "HTTP config sets 600s read timeout"

# Test 15: proxy_render_config with optimize_llm=0 uses standard buffering and 60s timeouts
test_case "proxy_render_config without optimize_llm preserves standard buffering and 60s timeouts"
rendered_std="$(proxy_render_config "standard.example.com" "127.0.0.1:3000" "/etc/ssl/cert.pem" "/etc/ssl/key.pem" "1" "50m" "1" "443" "" "0")"
assert_contains "$rendered_std" "LLM-Optimization: disabled" "Config header contains LLM-Optimization disabled"
assert_contains "$rendered_std" "proxy_buffering on;" "Standard config keeps proxy_buffering on"
assert_contains "$rendered_std" "proxy_read_timeout 60s;" "Standard config keeps 60s read timeout"

# Test 16: proxy_add_site with optimize_llm and custom timeout
test_case "proxy_add_site applies LLM optimization and custom timeout"
proxy_add_site "llm-site.example.com" "127.0.0.1:10001" "admin@example.com" "1" "" "1" "0" "1" "1" "1" "dns_cf" "token_xyz" "443" "auto" "1" "1200s"
assert_file_exists "$NGINX_CONF_DIR/llm-site.example.com.conf" "LLM site conf created"
conf_llm="$(cat "$NGINX_CONF_DIR/llm-site.example.com.conf")"
assert_contains "$conf_llm" "LLM-Optimization: enabled" "Site conf contains LLM-Optimization enabled"
assert_contains "$conf_llm" "proxy_buffering off;" "Site conf contains proxy_buffering off"
assert_contains "$conf_llm" "proxy_read_timeout 1200s;" "Site conf respects custom 1200s timeout"

test_summary
