#!/usr/bin/env bash
# ==============================================================================
# Unit Tests for lib/env.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/test_helper.sh"

SANDBOX="$(create_test_sandbox)"
trap 'cleanup_test_sandbox "$SANDBOX"' EXIT

export LOG_FILE="$SANDBOX/test_env.log"
export NO_COLOR=1

source "$PROJECT_ROOT/config.env"
source "$PROJECT_ROOT/lib/ui.sh"
source "$PROJECT_ROOT/lib/env.sh"

# Test 1: Ubuntu os-release parsing
test_case "env_detect_os correctly identifies Ubuntu"
cat << 'EOF' > "$SANDBOX/os_ubuntu"
NAME="Ubuntu"
VERSION="22.04.3 LTS (Jammy Jellyfish)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 22.04.3 LTS"
VERSION_ID="22.04"
EOF
env_detect_os "$SANDBOX/os_ubuntu"
assert_eq "$OS_ID" "ubuntu" "Ubuntu OS_ID detected"
assert_eq "$OS_FAMILY" "debian" "Ubuntu OS_FAMILY is debian"
assert_eq "$OS_VERSION_ID" "22.04" "Ubuntu VERSION_ID parsed"

# Test 2: Rocky Linux os-release parsing
test_case "env_detect_os correctly identifies Rocky Linux"
cat << 'EOF' > "$SANDBOX/os_rocky"
NAME="Rocky Linux"
VERSION="9.2 (Blue Onyx)"
ID="rocky"
ID_LIKE="rhel centos fedora"
VERSION_ID="9.2"
PLATFORM_ID="platform:el9"
PRETTY_NAME="Rocky Linux 9.2 (Blue Onyx)"
EOF
env_detect_os "$SANDBOX/os_rocky"
assert_eq "$OS_ID" "rocky" "Rocky OS_ID detected"
assert_eq "$OS_FAMILY" "rhel" "Rocky OS_FAMILY is rhel"
assert_eq "$OS_VERSION_ID" "9.2" "Rocky VERSION_ID parsed"

# Test 3: Alpine Linux os-release parsing
test_case "env_detect_os correctly identifies Alpine Linux"
cat << 'EOF' > "$SANDBOX/os_alpine"
NAME="Alpine Linux"
ID=alpine
VERSION_ID=3.18.4
PRETTY_NAME="Alpine Linux v3.18"
EOF
env_detect_os "$SANDBOX/os_alpine"
assert_eq "$OS_ID" "alpine" "Alpine OS_ID detected"
assert_eq "$OS_FAMILY" "alpine" "Alpine OS_FAMILY is alpine"

# Test 4: Arch Linux os-release parsing
test_case "env_detect_os correctly identifies Arch Linux"
cat << 'EOF' > "$SANDBOX/os_arch"
NAME="Arch Linux"
PRETTY_NAME="Arch Linux"
ID=arch
BUILD_ID=rolling
EOF
env_detect_os "$SANDBOX/os_arch"
assert_eq "$OS_ID" "arch" "Arch OS_ID detected"
assert_eq "$OS_FAMILY" "arch" "Arch OS_FAMILY is arch"

# Test 5: Generic ID_LIKE fallback
test_case "env_detect_os handles derivative distros via ID_LIKE"
cat << 'EOF' > "$SANDBOX/os_custom_deb"
NAME="Deepin"
ID=deepin
ID_LIKE="debian"
VERSION_ID="20.9"
EOF
env_detect_os "$SANDBOX/os_custom_deb"
assert_eq "$OS_FAMILY" "debian" "Derived distro mapped to debian via ID_LIKE"

# Test 6: Root status check
test_case "env_check_root reports correct status"
env_check_root || is_root_res=$?
is_root_res="${is_root_res:-0}"
if [ "${EUID:-$(id -u)}" -eq 0 ]; then
    assert_eq "$IS_ROOT" "1" "Root user flagged as 1"
    assert_eq "$is_root_res" "0" "env_check_root returned 0 for root"
else
    assert_eq "$IS_ROOT" "0" "Non-root user flagged as 0"
    assert_eq "$is_root_res" "1" "env_check_root returned 1 for non-root"
fi

# Test 7: Package check utility
test_case "pkg_is_installed accurately finds installed binaries"
if pkg_is_installed bash; then
    assert_eq "0" "0" "bash is detected as installed"
else
    assert_eq "1" "0" "bash should be detected"
fi

if ! pkg_is_installed definitely_non_existent_binary_xyz123; then
    assert_eq "0" "0" "non-existent binary is detected as not installed"
else
    assert_eq "1" "0" "non-existent binary was wrongly detected"
fi

# Test 8: Init system detection
test_case "env_detect_init sets INIT_SYSTEM to systemd or cron"
env_detect_init
if [ "$INIT_SYSTEM" = "systemd" ] || [ "$INIT_SYSTEM" = "cron" ]; then
    assert_eq "0" "0" "INIT_SYSTEM is valid ($INIT_SYSTEM)"
else
    assert_eq "1" "0" "INIT_SYSTEM invalid: $INIT_SYSTEM"
fi

# Test 9: env_summary output
test_case "env_summary outputs formatted diagnostics"
summary_out="$(env_summary)"
assert_contains "$summary_out" "操作系统:" "Summary contains OS info"
assert_contains "$summary_out" "IPv6支持:" "Summary contains IPv6 info"
assert_contains "$summary_out" "守护体系:" "Summary contains Init system info"

test_summary
