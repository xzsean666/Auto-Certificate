#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - lib/env.sh
# System Environment Perception, Multi-distro Adapter & IPv6 Probe
# ==============================================================================

# Prevent multiple inclusions
if [ -n "${_NGX_LIB_ENV_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_NGX_LIB_ENV_LOADED=1

# Global Environment State
OS_ID="unknown"
OS_NAME="Linux"
OS_VERSION_ID=""
OS_FAMILY="unknown" # debian, rhel, alpine, arch, unknown
PKG_MANAGER="unknown"
HAS_IPV6=0
INIT_SYSTEM="cron" # systemd or cron
IS_ROOT=0

# Ensure UI library is loaded
if [ -z "${_NGX_LIB_UI_LOADED:-}" ]; then
    _SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$_SCRIPT_DIR/ui.sh" ]; then
        # shellcheck source=lib/ui.sh
        source "$_SCRIPT_DIR/ui.sh"
    elif [ -f "$_SCRIPT_DIR/../lib/ui.sh" ]; then
        # shellcheck source=lib/ui.sh
        source "$_SCRIPT_DIR/../lib/ui.sh"
    fi
fi

# 1. Check Root Privileges
env_check_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        IS_ROOT=1
        return 0
    fi

    IS_ROOT=0
    return 1
}

# Require Root (Exit or warn if not root)
env_require_root() {
    if ! env_check_root; then
        ui_error "本套件的核心操作（Nginx配置/证书签发/服务管理）需要 Root 权限。"
        ui_info "请使用 'sudo $0' 或切换至 root 用户后再运行。"
        return 1
    fi
    return 0
}

# 2. Detect Operating System & Distro Family
# Takes optional os_release_file for testing/mocking
env_detect_os() {
    local os_file="${1:-/etc/os-release}"

    if [ -f "$os_file" ]; then
        # Parse standard os-release file
        local id_val="" name_val="" version_val="" id_like_val=""
        
        # Read key-values safely
        while IFS='=' read -r key val || [ -n "$key" ]; do
            # Strip comments and trim quotes
            [[ "$key" =~ ^#.*$ ]] && continue
            val="${val%\"}"
            val="${val#\"}"
            val="${val%\'}"
            val="${val#\'}"

            case "$key" in
                ID) id_val="$(echo "$val" | tr '[:upper:]' '[:lower:]')" ;;
                NAME) name_val="$val" ;;
                VERSION_ID) version_val="$val" ;;
                ID_LIKE) id_like_val="$(echo "$val" | tr '[:upper:]' '[:lower:]')" ;;
            esac
        done < "$os_file"

        OS_ID="${id_val:-unknown}"
        OS_NAME="${name_val:-Linux}"
        OS_VERSION_ID="${version_val:-}"

        # Classify distro family
        case "$OS_ID" in
            ubuntu|debian|raspbian|kali|linuxmint|pop)
                OS_FAMILY="debian"
                ;;
            centos|rhel|rocky|almalinux|fedora|ol|amzn)
                OS_FAMILY="rhel"
                ;;
            alpine)
                OS_FAMILY="alpine"
                ;;
            arch|manjaro|endeavouros)
                OS_FAMILY="arch"
                ;;
            *)
                # Check ID_LIKE fallback
                if [[ "$id_like_val" == *"debian"* ]] || [[ "$id_like_val" == *"ubuntu"* ]]; then
                    OS_FAMILY="debian"
                elif [[ "$id_like_val" == *"rhel"* ]] || [[ "$id_like_val" == *"fedora"* ]] || [[ "$id_like_val" == *"centos"* ]]; then
                    OS_FAMILY="rhel"
                elif [[ "$id_like_val" == *"arch"* ]]; then
                    OS_FAMILY="arch"
                else
                    OS_FAMILY="unknown"
                fi
                ;;
        esac
    elif [ -f "/etc/redhat-release" ]; then
        OS_ID="rhel"
        OS_FAMILY="rhel"
        OS_NAME="$(cat /etc/redhat-release)"
    elif [ -f "/etc/debian_version" ]; then
        OS_ID="debian"
        OS_FAMILY="debian"
        OS_NAME="Debian $(cat /etc/debian_version)"
    elif [ -f "/etc/alpine-release" ]; then
        OS_ID="alpine"
        OS_FAMILY="alpine"
        OS_NAME="Alpine Linux $(cat /etc/alpine-release)"
    elif [ -f "/etc/arch-release" ]; then
        OS_ID="arch"
        OS_FAMILY="arch"
        OS_NAME="Arch Linux"
    else
        OS_ID="unknown"
        OS_FAMILY="unknown"
        OS_NAME="Generic Linux"
    fi

    # Map package manager based on family
    env_detect_pkg_manager
}

# 3. Detect Package Manager
env_detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
    elif command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
    elif command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    else
        PKG_MANAGER="unknown"
    fi
}

# Package Management Operations
pkg_is_installed() {
    local pkg="$1"
    command -v "$pkg" >/dev/null 2>&1
}

pkg_update() {
    ui_info "正在刷新系统软件包索引缓存 ($PKG_MANAGER)..."
    case "$PKG_MANAGER" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -y -q >/dev/null 2>&1 || return 1
            ;;
        dnf)
            dnf check-update -q >/dev/null 2>&1 || true
            ;;
        yum)
            yum check-update -q >/dev/null 2>&1 || true
            ;;
        apk)
            apk update -q >/dev/null 2>&1 || return 1
            ;;
        pacman)
            pacman -Sy --noconfirm >/dev/null 2>&1 || return 1
            ;;
        *)
            ui_warn "未识别的包管理器，跳过更新步骤。"
            return 0
            ;;
    esac
    return 0
}

pkg_install() {
    local packages=("$@")
    if [ "${#packages[@]}" -eq 0 ]; then
        return 0
    fi

    ui_info "正在安装系统依赖: ${packages[*]}..."
    case "$PKG_MANAGER" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}" >/dev/null 2>&1 || return 1
            ;;
        dnf)
            dnf install -y "${packages[@]}" >/dev/null 2>&1 || return 1
            ;;
        yum)
            yum install -y "${packages[@]}" >/dev/null 2>&1 || return 1
            ;;
        apk)
            apk add --no-cache "${packages[@]}" >/dev/null 2>&1 || return 1
            ;;
        pacman)
            pacman -S --noconfirm --needed "${packages[@]}" >/dev/null 2>&1 || return 1
            ;;
        *)
            ui_error "未识别的包管理器，无法自动安装依赖: ${packages[*]}"
            return 1
            ;;
    esac
    return 0
}

# 4. Probe IPv6 Capability (Core Anti-Crash Mechanism)
# Checks if kernel allows socket binding to [::]
env_check_ipv6() {
    HAS_IPV6=0

    # Check 1: Check sysctl disable_ipv6 if readable
    if [ -f "/proc/sys/net/ipv6/conf/all/disable_ipv6" ]; then
        local disabled
        disabled="$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "1")"
        if [ "$disabled" = "1" ]; then
            HAS_IPV6=0
            ui_debug "IPv6 disabled by kernel sysctl (net.ipv6.conf.all.disable_ipv6 = 1)"
            return 1
        fi
    fi

    # Check 2: Check /proc/net/if_inet6
    if [ -f "/proc/net/if_inet6" ]; then
        # If file has contents, interfaces have IPv6 assigned
        local count
        count="$(grep -v "lo$" /proc/net/if_inet6 2>/dev/null | wc -l || echo "0")"
        if [ "$count" -gt 0 ]; then
            HAS_IPV6=1
            ui_debug "IPv6 interface detected with active addresses ($count entries)"
            return 0
        fi
    fi

    # Check 3: Fallback check with ip -6 addr or ping6
    if command -v ip >/dev/null 2>&1; then
        local ip6_addrs
        ip6_addrs="$(ip -6 addr show scope global 2>/dev/null | wc -l || echo "0")"
        if [ "$ip6_addrs" -gt 0 ]; then
            HAS_IPV6=1
            return 0
        fi
    fi

    HAS_IPV6=0
    return 1
}

# 5. Detect Init System (Systemd vs Cron/OpenRC)
env_detect_init() {
    if [ -d "/run/systemd/system" ] && command -v systemctl >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
    else
        INIT_SYSTEM="cron"
    fi
}

# 6. Overall Environment Initialization & Summary
env_init() {
    env_check_root || true
    env_detect_os
    env_check_ipv6 || true
    env_detect_init
}

env_summary() {
    local root_str="否 (普通用户)"
    [ "$IS_ROOT" -eq 1 ] && root_str="是 (Root用户)"

    local ipv6_str="不支持/未启用 (自动安全剔除 [::] 监听)"
    [ "$HAS_IPV6" -eq 1 ] && ipv6_str="支持 (已启用 IPv6 双栈监听)"

    echo "操作系统: ${OS_NAME} (${OS_ID})"
    echo "发行分支: ${OS_FAMILY} (包管理器: ${PKG_MANAGER})"
    echo "Root权限: ${root_str}"
    echo "IPv6支持: ${ipv6_str}"
    echo "守护体系: ${INIT_SYSTEM}"
}

# Auto-detect on source
env_init
