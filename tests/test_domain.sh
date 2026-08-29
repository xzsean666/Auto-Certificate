#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for lib/domain.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_domain.log"
export NO_COLOR=1

source "$PROJECT_ROOT/config.env"
source "$PROJECT_ROOT/lib/ui.sh"
source "$PROJECT_ROOT/lib/env.sh"
source "$PROJECT_ROOT/lib/domain.sh"

# Test 1: IPv4 Regex & Value Validation
test_case "domain_is_valid_ipv4 validates IPv4 format and ranges"
if domain_is_valid_ipv4 "192.168.1.1"; then
    assert_eq "0" "0" "192.168.1.1 is valid"
else
    assert_eq "1" "0" "192.168.1.1 should be valid"
fi

if domain_is_valid_ipv4 "8.8.8.8"; then
    assert_eq "0" "0" "8.8.8.8 is valid"
else
    assert_eq "1" "0" "8.8.8.8 should be valid"
fi

if ! domain_is_valid_ipv4 "256.0.0.1"; then
    assert_eq "0" "0" "256.0.0.1 (octet > 255) is invalid"
else
    assert_eq "1" "0" "256.0.0.1 should be invalid"
fi

if ! domain_is_valid_ipv4 "not_an_ip"; then
    assert_eq "0" "0" "'not_an_ip' is invalid"
else
    assert_eq "1" "0" "'not_an_ip' should be invalid"
fi

# Test 2: Cloudflare CDN IP Recognition
test_case "domain_is_cloudflare_ip identifies Cloudflare CDN ranges"
if domain_is_cloudflare_ip "104.16.123.45"; then
    assert_eq "0" "0" "104.16.x.x identified as Cloudflare"
else
    assert_eq "1" "0" "104.16.x.x should be Cloudflare"
fi

if domain_is_cloudflare_ip "172.64.10.20"; then
    assert_eq "0" "0" "172.64.x.x identified as Cloudflare"
else
    assert_eq "1" "0" "172.64.x.x should be Cloudflare"
fi

if ! domain_is_cloudflare_ip "8.8.8.8"; then
    assert_eq "0" "0" "8.8.8.8 is NOT Cloudflare"
else
    assert_eq "1" "0" "8.8.8.8 should not be Cloudflare"
fi

# Test 3: Skip check flag behavior
test_case "domain_verify_dns respects skip flag"
if domain_verify_dns "unresolvable.invalid" "1"; then
    assert_eq "0" "0" "domain_verify_dns returned 0 when skip_check is 1"
else
    assert_eq "1" "0" "domain_verify_dns failed with skip flag"
fi

# Test 4: Mocked matching DNS check
test_case "domain_verify_dns passes when DNS resolves to server public IP"
# Mock domain_get_public_ipv4 and domain_resolve_ipv4
domain_get_public_ipv4() {
    echo "203.0.113.10"
}
domain_resolve_ipv4() {
    echo "203.0.113.10"
}

if domain_verify_dns "app.example.com" "0" "1"; then
    assert_eq "0" "0" "domain_verify_dns succeeded on IP match"
else
    assert_eq "1" "0" "domain_verify_dns failed on matching IP"
fi

# Test 5: Mocked Cloudflare CDN DNS check
test_case "domain_verify_dns detects Cloudflare proxy and warns without blocking"
domain_resolve_ipv4() {
    echo "104.16.50.60"
}

if domain_verify_dns "cf.example.com" "0" "1"; then
    assert_eq "0" "0" "domain_verify_dns handled Cloudflare CDN proxy without hard blocking"
else
    assert_eq "1" "0" "domain_verify_dns should accept CF proxy with warning"
fi

# Test 6: Mocked mismatched DNS in non-interactive mode
test_case "domain_verify_dns fails with code 3 on mismatch in non-interactive mode"
export DNS_MAX_RETRIES=1
export DNS_RETRY_INTERVAL=0
domain_resolve_ipv4() {
    echo "198.51.100.99"
}

verify_ret=0
domain_verify_dns "wrong.example.com" "0" "1" || verify_ret=$?
assert_status_code "$verify_ret" 3 "domain_verify_dns returned error code 3 on mismatched IP"

# Test 7: Port 80 check when unoccupied
test_case "domain_check_port_80 returns 0 when port 80 is not occupied"
# Redefine ss and lsof to return empty for mock
ss() { return 0; }
lsof() { return 0; }
netstat() { return 0; }

if domain_check_port_80; then
    assert_eq "0" "0" "Port 80 confirmed free"
else
    assert_eq "1" "0" "Port 80 should be free"
fi

# Test 8: Port 80 check when occupied by Apache
test_case "domain_check_port_80 detects Apache2 conflict"
ss() {
    echo 'LISTEN 0 511 0.0.0.0:80 0.0.0.0:* users:(("apache2",pid=9988,fd=4))'
}

port_conflict_ret=0
out_conflict="$(domain_check_port_80)" || port_conflict_ret=$?
assert_status_code "$port_conflict_ret" 1 "domain_check_port_80 returned 1 for conflict"
assert_contains "$out_conflict" "OCCUPIED_PID=9988" "Extracted conflicting PID"
assert_contains "$out_conflict" "OCCUPIED_NAME=apache2" "Extracted conflicting process name"

test_summary
