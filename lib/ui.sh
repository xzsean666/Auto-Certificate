#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - lib/ui.sh
# Terminal UI Rendering Engine & Multi-level Logging Subsystem
# ==============================================================================

# Prevent multiple inclusions
if [ -n "${_NGX_LIB_UI_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_NGX_LIB_UI_LOADED=1

# Color Definitions (Default initialized, dynamically toggled in ui_init)
UI_CLR_RESET="\033[0m"
UI_CLR_BOLD="\033[1m"
UI_CLR_DIM="\033[2m"
UI_CLR_RED="\033[0;31m"
UI_CLR_GREEN="\033[0;32m"
UI_CLR_YELLOW="\033[0;33m"
UI_CLR_BLUE="\033[0;34m"
UI_CLR_MAGENTA="\033[0;35m"
UI_CLR_CYAN="\033[0;36m"
UI_CLR_WHITE="\033[0;37m"
UI_CLR_BG_BLUE="\033[44m"
UI_CLR_BG_DARK="\033[40m"

# Initialize UI environment & color support
ui_init() {
    # If NO_COLOR is set or output is not a terminal, disable ANSI color codes
    if [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; then
        UI_CLR_RESET=""
        UI_CLR_BOLD=""
        UI_CLR_DIM=""
        UI_CLR_RED=""
        UI_CLR_GREEN=""
        UI_CLR_YELLOW=""
        UI_CLR_BLUE=""
        UI_CLR_MAGENTA=""
        UI_CLR_CYAN=""
        UI_CLR_WHITE=""
        UI_CLR_BG_BLUE=""
        UI_CLR_BG_DARK=""
    fi

    # Ensure log destination is writable, else fallback
    _ui_ensure_log_file
}

# Helper to remove ANSI escape sequences
ui_strip_ansi() {
    local text="$1"
    # Strip ANSI color and cursor codes using sed
    echo -e "$text" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g"
}

# Internal function to resolve and ensure log file is writable
_ui_ensure_log_file() {
    local target_log="${LOG_FILE:-/var/log/ngx-cert-manager.log}"
    local log_dir
    log_dir="$(dirname "$target_log")"

    if [ -w "$log_dir" ] || { [ ! -d "$log_dir" ] && mkdir -p "$log_dir" 2>/dev/null; }; then
        LOG_FILE="$target_log"
    else
        # Fallback to home or tmp
        local fallback_dir="${LOG_FALLBACK_DIR:-$HOME/.ngx-cert-manager}"
        mkdir -p "$fallback_dir" 2>/dev/null || fallback_dir="/tmp/.ngx-cert-manager"
        mkdir -p "$fallback_dir" 2>/dev/null || true
        LOG_FILE="$fallback_dir/ngx-cert-manager.log"
    fi
}

# Unified Logging Function
ui_log() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"

    _ui_ensure_log_file

    if [ -n "$LOG_FILE" ]; then
        local clean_msg
        clean_msg="$(ui_strip_ansi "$message")"
        echo "[$timestamp] [$level] $clean_msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# Colored Notification Outputs
ui_info() {
    local msg="$*"
    echo -e "${UI_CLR_BLUE}ℹ [INFO]${UI_CLR_RESET} ${msg}"
    ui_log "INFO" "$msg"
}

ui_success() {
    local msg="$*"
    echo -e "${UI_CLR_GREEN}✔ [OK]${UI_CLR_RESET}   ${msg}"
    ui_log "SUCCESS" "$msg"
}

ui_warn() {
    local msg="$*"
    echo -e "${UI_CLR_YELLOW}⚠ [WARN]${UI_CLR_RESET} ${msg}"
    ui_log "WARN" "$msg"
}

ui_error() {
    local msg="$*"
    echo -e "${UI_CLR_RED}✖ [ERROR]${UI_CLR_RESET} ${msg}" >&2
    ui_log "ERROR" "$msg"
}

ui_debug() {
    if [ "${DEBUG:-0}" = "1" ]; then
        local msg="$*"
        echo -e "${UI_CLR_MAGENTA}⚙ [DEBUG]${UI_CLR_RESET} ${msg}"
        ui_log "DEBUG" "$msg"
    fi
}

# Section Header
ui_section() {
    local title="$1"
    echo ""
    echo -e "${UI_CLR_BOLD}${UI_CLR_CYAN}─── [ ${title} ] ──────────────────────────────────────────${UI_CLR_RESET}"
}

# Banner Header
ui_banner() {
    local ip="${1:-Unknown IP}"
    local os="${2:-Linux}"
    local version="${NGX_CERT_MANAGER_VERSION:-1.0.0}"

    echo -e "${UI_CLR_CYAN}================================================================================${UI_CLR_RESET}"
    echo -e "${UI_CLR_BOLD}              Nginx & SSL 自动化运维管理套件 v${version}${UI_CLR_RESET}"
    echo -e "   ${UI_CLR_DIM}服务器 IP: ${ip} | 系统环境: ${os}${UI_CLR_RESET}"
    echo -e "${UI_CLR_CYAN}================================================================================${UI_CLR_RESET}"
}

# Status Badges
ui_badge_status() {
    local status="$1"
    case "$status" in
        running|active|ok|valid|green)
            echo -e "${UI_CLR_GREEN}🟢 [ 正常/有效 ]${UI_CLR_RESET}"
            ;;
        warning|yellow|expiring)
            echo -e "${UI_CLR_YELLOW}🟡 [ 即将到期 ]${UI_CLR_RESET}"
            ;;
        stopped|inactive|error|red|expired)
            echo -e "${UI_CLR_RED}🔴 [ 异常/停止 ]${UI_CLR_RESET}"
            ;;
        *)
            echo -e "${UI_CLR_DIM}⚪ [ ${status} ]${UI_CLR_RESET}"
            ;;
    esac
}

# Interactive Prompt with Default Value
ui_prompt() {
    local prompt_text="$1"
    local default_val="${2:-}"
    local user_input=""

    if [ -n "$default_val" ]; then
        echo -ne "${UI_CLR_BOLD}${prompt_text}${UI_CLR_RESET} ${UI_CLR_DIM}[默认: ${default_val}]${UI_CLR_RESET}: " >&2
    else
        echo -ne "${UI_CLR_BOLD}${prompt_text}${UI_CLR_RESET}: " >&2
    fi

    read -r user_input
    if [ -z "$user_input" ]; then
        echo "$default_val"
    else
        echo "$user_input"
    fi
}

# Interactive Confirmation (Returns 0 for YES, 1 for NO)
ui_confirm() {
    local prompt_text="$1"
    local default_choice="${2:-Y}" # Y or N
    local choice_hint="[Y/n]"
    [ "$default_choice" = "N" ] && choice_hint="[y/N]"

    echo -ne "${UI_CLR_YELLOW}? ${prompt_text} ${choice_hint}: ${UI_CLR_RESET}" >&2
    local answer=""
    read -r answer
    answer="$(echo "${answer:-$default_choice}" | tr '[:upper:]' '[:lower:]')"

    if [[ "$answer" == "y" || "$answer" == "yes" ]]; then
        return 0
    else
        return 1
    fi
}

# Interactive Menu Selection
ui_select() {
    local prompt_title="$1"
    shift
    local options=("$@")
    local num_options="${#options[@]}"

    echo -e "${UI_CLR_BOLD}${prompt_title}${UI_CLR_RESET}" >&2
    for ((i=0; i<num_options; i++)); do
        local idx=$((i + 1))
        echo -e "  ${UI_CLR_CYAN}${idx})${UI_CLR_RESET} ${options[i]}" >&2
    done

    while true; do
        echo -ne "${UI_CLR_YELLOW}请输入选择 [1-${num_options}]: ${UI_CLR_RESET}" >&2
        local choice=""
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$num_options" ]; then
            echo "$choice"
            return 0
        fi
        echo -e "${UI_CLR_RED}无效输入，请重新输入 1 到 ${num_options} 之间的数字。${UI_CLR_RESET}" >&2
    done
}

# Spinner / Progress indicator for long running background tasks
ui_spinner() {
    local pid="$1"
    local message="$2"
    local spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local delay=0.1
    local i=0

    # If non-interactive, just wait for process to finish safely
    if [ ! -t 1 ]; then
        local st=0
        wait "$pid" || st=$?
        return "$st"
    fi

    # Hide cursor
    tput civis 2>/dev/null || true

    while kill -0 "$pid" 2>/dev/null; do
        local char="${spin_chars[i % 10]}"
        echo -ne "\r${UI_CLR_CYAN}${char}${UI_CLR_RESET} ${message}..." >&2
        sleep "$delay"
        i=$((i + 1))
    done

    # Wait for process exit and capture code safely
    local exit_status=0
    wait "$pid" || exit_status=$?

    # Restore cursor & clear spinner line
    echo -ne "\r\033[K" >&2
    tput cnorm 2>/dev/null || true

    return "$exit_status"
}

# Auto-initialize on source
ui_init
