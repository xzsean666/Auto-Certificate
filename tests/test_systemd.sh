#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for lib/systemd.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_systemd.log"
export NO_COLOR=1

# Override paths into sandbox
export ACME_WEBROOT_DIR="$SANDBOX/var/www/certbot"
export SYSTEMD_SYSTEM_DIR="$SANDBOX/etc/systemd/system"
export CRON_D_DIR="$SANDBOX/etc/cron.d"

source "$PROJECT_ROOT/config.env"
source "$PROJECT_ROOT/lib/ui.sh"
source "$PROJECT_ROOT/lib/env.sh"
source "$PROJECT_ROOT/lib/cert.sh"
source "$PROJECT_ROOT/lib/systemd.sh"

# Test 1: Systemd Service & Timer Generation
test_case "systemd_setup_timer renders service and timer with randomized jitter"
systemd_setup_timer
service_path="$SYSTEMD_SYSTEM_DIR/certbot-renew.service"
timer_path="$SYSTEMD_SYSTEM_DIR/certbot-renew.timer"

assert_file_exists "$service_path" "certbot-renew.service rendered"
assert_file_exists "$timer_path" "certbot-renew.timer rendered"

s_content="$(cat "$service_path")"
assert_contains "$s_content" "renew --webroot -w $ACME_WEBROOT_DIR" "Service contains webroot renewal command"
assert_contains "$s_content" "--post-hook" "Service contains post-hook directive"

t_content="$(cat "$timer_path")"
assert_contains "$t_content" "RandomizedDelaySec=3600" "Timer contains 3600s randomized delay jitter"
assert_contains "$t_content" "OnCalendar=*-*-* 03,15:30:00" "Timer contains 12h renewal schedule"

# Test 2: Cron Fallback Injection
test_case "cron_setup_renew generates valid /etc/cron.d entry"
mkdir -p "$CRON_D_DIR"
cron_setup_renew
cron_file="$CRON_D_DIR/certbot-renew"
assert_file_exists "$cron_file" "cron.d/certbot-renew created"

cron_content="$(cat "$cron_file")"
assert_contains "$cron_content" "30 3,15 * * *" "Cron schedule set to 03:30 and 15:30"
assert_contains "$cron_content" "$ACME_WEBROOT_DIR" "Cron contains webroot path"

# Test 3: timer_status_summary
test_case "timer_status_summary outputs current operational state"
status_systemd="$(timer_status_summary)"
assert_contains "$status_systemd" "Systemd Timer: certbot-renew.timer 已激活" "Summary reflects active timer"

# Remove systemd timer to test cron fallback status
rm -f "$timer_path"
status_cron="$(timer_status_summary)"
assert_contains "$status_cron" "Cron 自动续期守护中" "Summary reflects Cron status"

rm -f "$cron_file"
status_inactive="$(timer_status_summary)"
assert_contains "$status_inactive" "未激活" "Summary reflects unconfigured status"

test_summary
