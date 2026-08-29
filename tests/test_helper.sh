#!/usr/bin/env bash
# ==============================================================================
# Test Helper & Assertion Framework for ngx-cert-manager
# ==============================================================================

TESTS_PASSED=0
TESTS_FAILED=0
TEST_CURRENT_NAME=""

# Colors
T_GREEN="\033[0;32m"
T_RED="\033[0;31m"
T_YELLOW="\033[0;33m"
T_BLUE="\033[0;34m"
T_RESET="\033[0m"

test_case() {
    TEST_CURRENT_NAME="$1"
    echo -e "${T_BLUE}[TEST CASE]${T_RESET} $TEST_CURRENT_NAME"
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-Values should be equal}"

    if [ "$actual" = "$expected" ]; then
        echo -e "  ${T_GREEN}PASS${T_RESET}: $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${T_RED}FAIL${T_RESET}: $msg"
        echo -e "    Expected: '$expected'"
        echo -e "    Actual:   '$actual'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "  ${T_GREEN}PASS${T_RESET}: $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${T_RED}FAIL${T_RESET}: $msg"
        echo -e "    Haystack: '$haystack'"
        echo -e "    Missing Needle: '$needle'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-String should not contain substring}"

    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "  ${T_GREEN}PASS${T_RESET}: $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${T_RED}FAIL${T_RESET}: $msg"
        echo -e "    Haystack: '$haystack'"
        echo -e "    Unexpected Needle: '$needle'"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_file_exists() {
    local file="$1"
    local msg="${2:-File should exist: $file}"

    if [ -f "$file" ]; then
        echo -e "  ${T_GREEN}PASS${T_RESET}: $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${T_RED}FAIL${T_RESET}: $msg (File not found: $file)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_dir_exists() {
    local dir="$1"
    local msg="${2:-Directory should exist: $dir}"

    if [ -d "$dir" ]; then
        echo -e "  ${T_GREEN}PASS${T_RESET}: $msg"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${T_RED}FAIL${T_RESET}: $msg (Directory not found: $dir)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

assert_status_code() {
    local actual="$1"
    local expected="$2"
    local msg="${3:-Exit code should match}"

    if [ "$actual" -eq "$expected" ]; then
        echo -e "  ${T_GREEN}PASS${T_RESET}: $msg (Code: $actual)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "  ${T_RED}FAIL${T_RESET}: $msg"
        echo -e "    Expected code: $expected"
        echo -e "    Actual code:   $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

test_summary() {
    echo "--------------------------------------------------------"
    echo -e "Test Results: ${T_GREEN}${TESTS_PASSED} passed${T_RESET}, ${T_RED}${TESTS_FAILED} failed${T_RESET}"
    if [ "$TESTS_FAILED" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Create a clean mock sandbox directory with safe non-interactive mocks
create_test_sandbox() {
    local base_dir
    base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/tests/tmp/sandbox_$$"
    local mock_bin="$base_dir/bin"
    mkdir -p "$mock_bin"

    # Mock safe dummy systemctl that never asks for password
    cat << 'EOF' > "$mock_bin/systemctl"
#!/usr/bin/env bash
if [ "$1" = "is-active" ]; then exit 0; fi
if [ "$1" = "status" ]; then exit 0; fi
if [ "$1" = "list-timers" ]; then exit 0; fi
exit 0
EOF
    chmod +x "$mock_bin/systemctl"

    # Mock safe dummy journalctl
    cat << 'EOF' > "$mock_bin/journalctl"
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$mock_bin/journalctl"

    export PATH="$mock_bin:$PATH"
    export SUDO_ASKPASS="/bin/false"
    export SYSTEMD_PAGER="cat"
    export SYSTEMD_COLORS="0"

    echo "$base_dir"
}

cleanup_test_sandbox() {
    local sandbox_dir="$1"
    if [ -n "$sandbox_dir" ] && [ -d "$sandbox_dir" ]; then
        rm -rf "$sandbox_dir"
    fi
}
