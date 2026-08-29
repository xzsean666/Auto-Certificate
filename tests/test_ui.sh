#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for lib/ui.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_app.log"
export NO_COLOR=1 # For deterministic string comparisons

source "$PROJECT_ROOT/config.env"
source "$PROJECT_ROOT/lib/ui.sh"

# Test 1: ui_strip_ansi
test_case "ui_strip_ansi removes ANSI color codes"
raw_str="\033[0;31mError text\033[0m with \033[1mBold\033[0m"
clean_str="$(ui_strip_ansi "$raw_str")"
assert_eq "$clean_str" "Error text with Bold" "ANSI escape codes stripped correctly"

# Test 2: Logging functionality
test_case "ui_log creates log file and appends message"
ui_log "TEST_LEVEL" "This is a test audit log message"
assert_file_exists "$LOG_FILE" "Log file created"
log_content="$(cat "$LOG_FILE")"
assert_contains "$log_content" "[TEST_LEVEL] This is a test audit log message" "Log message correctly written"

# Test 3: Output functions (info, success, warn, error)
test_case "Notification outputs and logging"
info_out="$(ui_info "Testing info message")"
assert_contains "$info_out" "[INFO] Testing info message" "ui_info output contains tag"

success_out="$(ui_success "Operation succeeded")"
assert_contains "$success_out" "[OK]   Operation succeeded" "ui_success output contains tag"

warn_out="$(ui_warn "Low disk warning")"
assert_contains "$warn_out" "[WARN] Low disk warning" "ui_warn output contains tag"

error_out="$(ui_error "Critical error occurred" 2>&1)"
assert_contains "$error_out" "[ERROR] Critical error occurred" "ui_error output contains tag"

# Check log file contains all entries
log_content="$(cat "$LOG_FILE")"
assert_contains "$log_content" "[INFO] Testing info message" "Info logged"
assert_contains "$log_content" "[SUCCESS] Operation succeeded" "Success logged"
assert_contains "$log_content" "[WARN] Low disk warning" "Warn logged"
assert_contains "$log_content" "[ERROR] Critical error occurred" "Error logged"

# Test 4: ui_prompt with default value and custom value
test_case "ui_prompt handles defaults and inputs"
# Simulate empty input (press Enter)
res_default="$(echo "" | ui_prompt "Enter domain" "example.com")"
assert_eq "$res_default" "example.com" "Default value returned on empty input"

# Simulate custom input
res_custom="$(echo "custom.domain.org" | ui_prompt "Enter domain" "example.com")"
assert_eq "$res_custom" "custom.domain.org" "Custom input returned correctly"

# Test 5: ui_confirm
test_case "ui_confirm handles yes/no and defaults"
if echo "y" | ui_confirm "Proceed?"; then
    assert_eq "0" "0" "ui_confirm returned 0 for 'y'"
else
    assert_eq "1" "0" "ui_confirm should return 0 for 'y'"
fi

if echo "n" | ui_confirm "Proceed?"; then
    assert_eq "0" "1" "ui_confirm should return 1 for 'n'"
else
    assert_eq "0" "0" "ui_confirm returned 1 for 'n'"
fi

if echo "" | ui_confirm "Proceed with default Y?" "Y"; then
    assert_eq "0" "0" "ui_confirm returned 0 for default Y on empty input"
else
    assert_eq "1" "0" "ui_confirm failed on default Y"
fi

if echo "" | ui_confirm "Proceed with default N?" "N"; then
    assert_eq "0" "1" "ui_confirm should return 1 for default N on empty input"
else
    assert_eq "0" "0" "ui_confirm returned 1 for default N on empty input"
fi

# Test 6: ui_badge_status
test_case "ui_badge_status generates appropriate badges"
badge_run="$(ui_badge_status "running")"
assert_contains "$badge_run" "正常/有效" "Running badge contains 正常/有效"

badge_exp="$(ui_badge_status "expiring")"
assert_contains "$badge_exp" "即将到期" "Expiring badge contains 即将到期"

badge_stop="$(ui_badge_status "stopped")"
assert_contains "$badge_stop" "异常/停止" "Stopped badge contains 异常/停止"

# Test 7: ui_select
test_case "ui_select parses valid option selection"
choice="$(echo "2" | ui_select "Choose an action" "Start" "Stop" "Restart")"
assert_eq "$choice" "2" "ui_select successfully parsed numeric choice 2"

# Test 8: ui_spinner with background task
test_case "ui_spinner waits for background task and captures exit code"
(sleep 0.1 && exit 0) &
bg_pid=$!
ui_spinner "$bg_pid" "Simulating background operation"
spinner_res=$?
assert_status_code "$spinner_res" 0 "ui_spinner returned 0 for successful process"

(sleep 0.1 && exit 42) &
bg_pid_err=$!
err_code=0
ui_spinner "$bg_pid_err" "Simulating failing background operation" || err_code=$?
assert_status_code "$err_code" 42 "ui_spinner returned error code 42 for failed process"

test_summary
