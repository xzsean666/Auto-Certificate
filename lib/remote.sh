#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - lib/remote.sh
# Zero-trace Remote SSH Execution & Ephemeral Deployment Engine
# ==============================================================================

# Prevent multiple inclusions
if [ -n "${_NGX_LIB_REMOTE_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_NGX_LIB_REMOTE_LOADED=1

# Ensure dependencies are loaded
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
[ -f "$_SCRIPT_DIR/../config.env" ] && source "$_SCRIPT_DIR/../config.env"
# shellcheck source=lib/ui.sh
[ -f "$_SCRIPT_DIR/ui.sh" ] && source "$_SCRIPT_DIR/ui.sh"

# 1. Create a Lightweight Ephemeral Tarball of the Toolkit
remote_pack_bundle() {
    local project_root="${1:-$(cd "$_SCRIPT_DIR/.." && pwd)}"
    local output_tar="${2:-/tmp/ngx-cert-manager-bundle-$$.tar.gz}"

    ui_info "正在打包本地运维组件库..."

    # Create tarball containing ngx-cert-manager, main.sh, config.env, lib/, templates/
    tar -czf "$output_tar" \
        -C "$project_root" \
        --exclude='.git' \
        --exclude='.backup' \
        --exclude='tests' \
        --exclude='dist' \
        --exclude='*.log' \
        --exclude='*.tmp' \
        --exclude='*.bak' \
        ngx-cert-manager main.sh config.env lib templates 2>/dev/null || {
            # Fallback if some files not yet present during testing
            tar -czf "$output_tar" \
                -C "$project_root" \
                --exclude='.git' \
                --exclude='.backup' \
                --exclude='tests' \
                --exclude='dist' \
                config.env lib templates 2>/dev/null || true
        }

    if [ -f "$output_tar" ] && [ -s "$output_tar" ]; then
        echo "$output_tar"
        return 0
    else
        ui_error "打包运维组件库失败。"
        return 1
    fi
}

# 2. Parse SSH target and optional custom port
# Supports user@host, user@host:port, -p port user@host
remote_parse_ssh_target() {
    local raw_target="$1"
    local port="${2:-}"

    local user_host="$raw_target"
    local extracted_port="$port"

    # Check if target contains :port syntax
    if [[ "$raw_target" =~ ^(.*):([0-9]+)$ ]]; then
        user_host="${BASH_REMATCH[1]}"
        extracted_port="${BASH_REMATCH[2]}"
    fi

    echo "USER_HOST=$user_host"
    echo "PORT=$extracted_port"
}

# 3. Build Remote Execution Command
remote_build_remote_command() {
    local remote_dir="$1"
    shift
    local subcommands=("$@")

    # Command string with trap cleanup
    local cmd="mkdir -p '${remote_dir}' && tar -xzf - -C '${remote_dir}' && "
    cmd+="trap 'rm -rf \"${remote_dir}\"' EXIT INT TERM; "
    cmd+="cd '${remote_dir}' && chmod +x ngx-cert-manager main.sh 2>/dev/null || true; "
    cmd+="if [ -x ./ngx-cert-manager ]; then ./ngx-cert-manager; else ./main.sh; fi"

    if [ "${#subcommands[@]}" -gt 0 ]; then
        for arg in "${subcommands[@]}"; do
            cmd+=" '$arg'"
        done
    fi

    echo "$cmd"
}

# 4. Execute Remote Agent with Full TTY Allocation & Self-Cleaning
remote_execute() {
    local ssh_target="$1"
    shift
    local subcommands=("$@")

    if [ -z "$ssh_target" ]; then
        ui_error "必须指定 SSH 目标主机 (例如: root@192.168.1.100)。"
        return 1
    fi

    if ! command -v ssh >/dev/null 2>&1; then
        ui_error "本地未安装 ssh 客户端，无法发起远程连接。"
        return 1
    fi

    # Project root
    local project_root
    project_root="$(cd "$_SCRIPT_DIR/.." && pwd)"

    local bundle_tar="/tmp/ngx-cert-manager-$$.tar.gz"
    trap 'rm -f "$bundle_tar" 2>/dev/null || true' EXIT INT TERM

    if ! remote_pack_bundle "$project_root" "$bundle_tar" >/dev/null; then
        return 1
    fi

    local rand_suffix
    rand_suffix="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8 || echo "$$")"
    local remote_tmp_dir="/tmp/.ngx-cert-manager-${rand_suffix}"

    local ssh_opts=(-o "StrictHostKeyChecking=accept-new" -o "ConnectTimeout=10")
    
    # Parse target and port
    eval "$(remote_parse_ssh_target "$ssh_target")"
    if [ -n "$PORT" ]; then
        ssh_opts+=(-p "$PORT")
    fi

    local remote_cmd
    remote_cmd="$(remote_build_remote_command "$remote_tmp_dir" "${subcommands[@]}")"

    ui_section "建立无痕 SSH 远程运维通道: ${USER_HOST}"
    ui_info "传输临时运维套件并启动远端控制台..."

    # Pipe bundle into ssh and allocate pseudo-terminal
    # shellcheck disable=SC2029
    ssh -t "${ssh_opts[@]}" "$USER_HOST" "$remote_cmd" < "$bundle_tar"
    local ret=$?

    rm -f "$bundle_tar" 2>/dev/null || true

    if [ "$ret" -eq 0 ]; then
        ui_success "远程运维会话已正常结束，远端临时资源已彻底清理。"
        return 0
    else
        ui_warn "远程运维会话退出 (状态码: $ret)。"
        return "$ret"
    fi
}
