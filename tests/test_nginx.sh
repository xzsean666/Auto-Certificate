#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for lib/nginx.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_nginx.log"
export NO_COLOR=1

# Override paths to point inside the sandbox
export ACME_WEBROOT_DIR="$SANDBOX/var/www/certbot"
export NGINX_CONF_DIR="$SANDBOX/etc/nginx/conf.d"
export NGINX_MAIN_CONF="$SANDBOX/etc/nginx/nginx.conf"
export NGINX_BACKUP_DIR="$SANDBOX/etc/nginx/conf.d/.backup"

source "$PROJECT_ROOT/config.env"
source "$PROJECT_ROOT/lib/ui.sh"
source "$PROJECT_ROOT/lib/env.sh"
source "$PROJECT_ROOT/lib/nginx.sh"

# Test 1: Version comparison logic
test_case "nginx_version_ge correctly compares semver strings"
if nginx_version_ge "1.25.1" "1.24.0"; then
    assert_eq "0" "0" "1.25.1 >= 1.24.0 is true"
else
    assert_eq "1" "0" "1.25.1 should be >= 1.24.0"
fi

if nginx_version_ge "1.25.1" "1.25.1"; then
    assert_eq "0" "0" "1.25.1 >= 1.25.1 is true"
else
    assert_eq "1" "0" "1.25.1 should be >= 1.25.1"
fi

if ! nginx_version_ge "1.24.0" "1.25.1"; then
    assert_eq "0" "0" "1.24.0 >= 1.25.1 is false"
else
    assert_eq "1" "0" "1.24.0 should not be >= 1.25.1"
fi

# Test 2: Ensure directories creation
test_case "nginx_ensure_dirs creates required folder hierarchy"
nginx_ensure_dirs
assert_dir_exists "$ACME_WEBROOT_DIR" "Webroot dir created"
assert_dir_exists "$NGINX_CONF_DIR" "Conf.d dir created"
assert_dir_exists "$NGINX_BACKUP_DIR" "Backup dir created"

# Test 3: Setup Global ACME Webroot with HAS_IPV6=1
test_case "nginx_setup_global_acme renders with IPv6 listen when HAS_IPV6=1"
HAS_IPV6=1
nginx_setup_global_acme
acme_conf="$NGINX_CONF_DIR/000-default-acme.conf"
assert_file_exists "$acme_conf" "000-default-acme.conf created"
content="$(cat "$acme_conf")"
assert_contains "$content" "listen 80 default_server;" "Contains listen 80"
assert_contains "$content" "listen [::]:80 default_server;" "Contains listen [::]:80"
assert_contains "$content" "$ACME_WEBROOT_DIR" "Contains ACME webroot path"

# Test 4: Setup Global ACME Webroot with HAS_IPV6=0
test_case "nginx_setup_global_acme omits IPv6 listen when HAS_IPV6=0"
HAS_IPV6=0
nginx_setup_global_acme
content="$(cat "$acme_conf")"
assert_contains "$content" "listen 80 default_server;" "Contains listen 80"
assert_not_contains "$content" "listen [::]:80 default_server;" "Does NOT contain [::]:80"

# Test 5: Setup WebSocket Map
test_case "nginx_setup_websocket_map installs connection upgrade mapping"
nginx_setup_websocket_map
ws_conf="$NGINX_CONF_DIR/000-websocket-map.conf"
assert_file_exists "$ws_conf" "000-websocket-map.conf created"
ws_content="$(cat "$ws_conf")"
assert_contains "$ws_content" "map \$http_upgrade \$connection_upgrade" "Contains websocket map directive"

# Test 6: Ensure include conf.d/*.conf in main nginx.conf
test_case "nginx_ensure_include_conf_d injects include directive safely"
mkdir -p "$(dirname "$NGINX_MAIN_CONF")"
cat << 'EOF' > "$NGINX_MAIN_CONF"
user nginx;
worker_processes auto;
events {
    worker_connections 1024;
}
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
}
EOF

# Create a mock nginx binary that returns 0 for -t
mock_bin_dir="$SANDBOX/bin"
mkdir -p "$mock_bin_dir"
cat << 'EOF' > "$mock_bin_dir/nginx"
#!/usr/bin/env bash
if [ "$1" = "-v" ]; then
    echo "nginx version: nginx/1.26.1" >&2
    exit 0
fi
if [ "$1" = "-t" ]; then
    exit 0
fi
if [ "$1" = "-s" ] && [ "$2" = "reload" ]; then
    exit 0
fi
exit 0
EOF
chmod +x "$mock_bin_dir/nginx"
export NGINX_BIN="$mock_bin_dir/nginx"

nginx_ensure_include_conf_d
updated_main="$(cat "$NGINX_MAIN_CONF")"
assert_contains "$updated_main" "include $NGINX_CONF_DIR/*.conf;" "Include directive was inserted"

# Test 7: Mock nginx version detection and HTTP/2 directive check
test_case "nginx_get_version extracts version from mock binary"
ver="$(nginx_get_version)"
assert_eq "$ver" "1.26.1" "Version 1.26.1 extracted correctly"

if nginx_supports_http2_directive; then
    assert_eq "0" "0" "Version 1.26.1 supports http2 directive"
else
    assert_eq "1" "0" "Version 1.26.1 should support http2 directive"
fi

# Test 8: Nginx reload blocking on syntax error
test_case "nginx_reload blocks execution when syntax test fails"
# Create a failing mock nginx binary
cat << 'EOF' > "$mock_bin_dir/nginx_broken"
#!/usr/bin/env bash
if [ "$1" = "-t" ]; then
    echo "nginx: [emerg] unknown directive 'invalid_directive' in /etc/nginx/conf.d/test.conf:1" >&2
    exit 1
fi
exit 0
EOF
chmod +x "$mock_bin_dir/nginx_broken"
export NGINX_BIN="$mock_bin_dir/nginx_broken"

reload_ret=0
nginx_reload || reload_ret=$?
assert_status_code "$reload_ret" 1 "nginx_reload strictly blocked and returned 1 on syntax failure"

# Test 9: nginx_detect_https_port with explicit port
test_case "nginx_detect_https_port respects explicit custom port"
assert_eq "$(nginx_detect_https_port "8443")" "8443" "Explicit 8443 respected"
assert_eq "$(HTTPS_PORT=9443 nginx_detect_https_port)" "9443" "HTTPS_PORT env respected"

# Test 10: nginx_detect_https_port defaults to 443 when no stream multiplexing
test_case "nginx_detect_https_port defaults to 443 in standard configuration"
cat << 'EOF' > "$NGINX_MAIN_CONF"
events { worker_connections 1024; }
http {
    include mime.types;
}
EOF
assert_eq "$(nginx_detect_https_port)" "443" "Defaults to standard 443"

# Test 11: nginx_detect_https_port auto-detects stream 443 multiplexing
test_case "nginx_detect_https_port auto-detects stream 443 multiplexing backend port"
cat << 'EOF' > "$NGINX_MAIN_CONF"
events { worker_connections 1024; }
stream {
    upstream web_backend {
        server 127.0.0.1:8443;
    }
    upstream ssh_backend {
        server 127.0.0.1:22;
    }
    map $ssl_preread_protocol $upstream {
        "" ssh_backend;
        default web_backend;
    }
    server {
        listen 443;
        proxy_pass $upstream;
        ssl_preread on;
    }
}
http {
    include mime.types;
}
EOF
assert_eq "$(nginx_detect_https_port)" "8443" "Auto-detected 8443 from stream web_backend"

test_summary
