#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for lib/remote.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_remote.log"
export NO_COLOR=1

source "$PROJECT_ROOT/config.env"
source "$PROJECT_ROOT/lib/ui.sh"
source "$PROJECT_ROOT/lib/remote.sh"

# Test 1: Package Bundle Generation
test_case "remote_pack_bundle creates valid archive containing toolkit"
tar_output="$SANDBOX/bundle.tar.gz"
remote_pack_bundle "$PROJECT_ROOT" "$tar_output"
assert_file_exists "$tar_output" "Archive bundle was generated"

# Extract archive into a test directory and verify files
extract_dir="$SANDBOX/unpacked"
mkdir -p "$extract_dir"
tar -xzf "$tar_output" -C "$extract_dir"

assert_file_exists "$extract_dir/ngx-cert-manager" "Unpacked bundle contains ngx-cert-manager"
assert_file_exists "$extract_dir/config.env" "Unpacked bundle contains config.env"
assert_file_exists "$extract_dir/lib/ui.sh" "Unpacked bundle contains lib/ui.sh"
assert_file_exists "$extract_dir/templates/proxy-ssl.conf.tpl" "Unpacked bundle contains templates"

# Ensure tests and git directories were excluded
if [ ! -d "$extract_dir/tests" ] && [ ! -d "$extract_dir/.git" ]; then
    assert_eq "0" "0" "Archive excluded tests and .git directories as expected"
else
    assert_eq "1" "0" "Archive should not include tests or .git"
fi

# Test 2: SSH Target & Port Parsing
test_case "remote_parse_ssh_target correctly parses target and port"
eval "$(remote_parse_ssh_target "root@192.168.1.100")"
assert_eq "$USER_HOST" "root@192.168.1.100" "Simple target parsed"
assert_eq "$PORT" "" "Port is empty when not specified"

eval "$(remote_parse_ssh_target "admin@vps.example.com:2222")"
assert_eq "$USER_HOST" "admin@vps.example.com" "Host parsed from host:port"
assert_eq "$PORT" "2222" "Custom port 2222 extracted"

# Test 3: Remote Command Construction with Trap
test_case "remote_build_remote_command generates trap and execution string"
cmd_str="$(remote_build_remote_command "/tmp/.ngx-test" "site" "list")"
assert_contains "$cmd_str" "mkdir -p '/tmp/.ngx-test'" "Command creates remote dir"
assert_contains "$cmd_str" "trap 'rm -rf \"/tmp/.ngx-test\"' EXIT INT TERM" "Command registers self-cleaning trap"
assert_contains "$cmd_str" "ngx-cert-manager" "Command launches ngx-cert-manager"

# Test 4: Verify config.env in bundle contains Cloudflare configuration
test_case "config.env inside unpacked bundle preserves Cloudflare settings"
assert_contains "$(cat "$extract_dir/config.env")" "CF_DNS_API_TOKEN" "Preserves CF_DNS_API_TOKEN"
assert_contains "$(cat "$extract_dir/config.env")" "DEFAULT_CERT_MODE" "Preserves DEFAULT_CERT_MODE"

test_summary
