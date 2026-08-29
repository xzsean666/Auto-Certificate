#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for lib/cert.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_cert.log"
export NO_COLOR=1

# Override paths into the sandbox
export ACME_WEBROOT_DIR="$SANDBOX/var/www/certbot"
export NGINX_CONF_DIR="$SANDBOX/etc/nginx/conf.d"
export LETSENCRYPT_LIVE_DIR="$SANDBOX/etc/letsencrypt/live"

source "$PROJECT_ROOT/config.env"
source "$PROJECT_ROOT/lib/ui.sh"
source "$PROJECT_ROOT/lib/env.sh"
source "$PROJECT_ROOT/lib/nginx.sh"
source "$PROJECT_ROOT/lib/cert.sh"

# Helper: generate self-signed cert with specified validity days
create_test_cert() {
    local domain="$1"
    local days="$2"
    local dir="$LETSENCRYPT_LIVE_DIR/$domain"
    mkdir -p "$dir"
    openssl req -x509 -nodes -days "$days" -newkey rsa:2048 \
        -keyout "$dir/privkey.pem" \
        -out "$dir/fullchain.pem" \
        -subj "/CN=$domain" 2>/dev/null
    cp "$dir/fullchain.pem" "$dir/cert.pem"
}

# Test 1: Certificate Remaining Days & Expiration Date
test_case "cert_get_remaining_days accurately calculates remaining days"
create_test_cert "valid.example.com" 90
days_left="$(cert_get_remaining_days "$LETSENCRYPT_LIVE_DIR/valid.example.com/fullchain.pem")"
if [ "$days_left" -ge 88 ] && [ "$days_left" -le 91 ]; then
    assert_eq "0" "0" "Remaining days around 90 days ($days_left days left)"
else
    assert_eq "1" "0" "Remaining days should be ~90, got: $days_left"
fi

exp_date="$(cert_get_expire_date "$LETSENCRYPT_LIVE_DIR/valid.example.com/fullchain.pem")"
assert_contains "$exp_date" "20" "Expiration date formatted with year"

# Test 2: Status Level & Badge mapping
test_case "cert_get_status_level correctly classifies thresholds"
assert_eq "$(cert_get_status_level 60)" "safe" "60 days is safe"
assert_eq "$(cert_get_status_level 25)" "warning" "25 days is warning"
assert_eq "$(cert_get_status_level 10)" "critical" "10 days is critical"
assert_eq "$(cert_get_status_level 0)" "expired" "0 days is expired"
assert_eq "$(cert_get_status_level -5)" "expired" "-5 days is expired"

# Test 3: cert_exists_and_valid
test_case "cert_exists_and_valid identifies fresh certificates"
if cert_exists_and_valid "valid.example.com"; then
    assert_eq "0" "0" "valid.example.com identified as existing and valid"
else
    assert_eq "1" "0" "valid.example.com should be valid"
fi

create_test_cert "expiring.example.com" 10
if ! cert_exists_and_valid "expiring.example.com"; then
    assert_eq "0" "0" "expiring.example.com (<30 days) identified as needing renewal"
else
    assert_eq "1" "0" "expiring.example.com should not be considered fully valid"
fi

# Test 4: cert_list Dashboard
test_case "cert_list renders formatted certificate dashboard"
dashboard_out="$(cert_list)"
assert_contains "$dashboard_out" "valid.example.com" "Dashboard lists valid domain"
assert_contains "$dashboard_out" "expiring.example.com" "Dashboard lists expiring domain"
assert_contains "$dashboard_out" "共计 2 张受管 SSL 证书" "Dashboard shows total count"

# Test 5: cert_issue_webroot with mock certbot
test_case "cert_issue_webroot builds correct certbot command"
mock_bin_dir="$SANDBOX/bin"
mkdir -p "$mock_bin_dir"
cat << 'EOF' > "$mock_bin_dir/certbot"
#!/usr/bin/env bash
echo "CERTBOT_ARGS: $*"
if [ "$1" = "certonly" ]; then
    # Extract domain after -d
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
if [ "$1" = "renew" ]; then
    echo "Simulated renewal success"
    exit 0
fi
if [ "$1" = "revoke" ]; then
    echo "Simulated revocation success"
    exit 0
fi
exit 0
EOF
chmod +x "$mock_bin_dir/certbot"
export CERTBOT_BIN="$mock_bin_dir/certbot"

issue_out="$(cert_issue_webroot "new.example.com" "admin@example.com" "1" "1")"
assert_contains "$issue_out" "SSL_CERT_PATH=$LETSENCRYPT_LIVE_DIR/new.example.com/fullchain.pem" "Output returns cert path"
assert_file_exists "$LETSENCRYPT_LIVE_DIR/new.example.com/fullchain.pem" "Fullchain cert created"

# Test 6: cert_renew and cert_revoke
test_case "cert_renew and cert_revoke work with certbot wrapper"
if cert_renew; then
    assert_eq "0" "0" "cert_renew succeeded"
else
    assert_eq "1" "0" "cert_renew failed"
fi

if cert_revoke "new.example.com"; then
    assert_eq "0" "0" "cert_revoke succeeded"
else
    assert_eq "1" "0" "cert_revoke failed"
fi

test_summary
