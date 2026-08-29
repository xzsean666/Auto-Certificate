#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - lib/nginx.sh
# Nginx Lifecycle Management, Global Webroot Penetration & Configuration Engine
# ==============================================================================

# Prevent multiple inclusions
if [ -n "${_NGX_LIB_NGINX_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_NGX_LIB_NGINX_LOADED=1

# Ensure dependencies are loaded
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
[ -f "$_SCRIPT_DIR/../config.env" ] && source "$_SCRIPT_DIR/../config.env"
# shellcheck source=lib/ui.sh
[ -f "$_SCRIPT_DIR/ui.sh" ] && source "$_SCRIPT_DIR/ui.sh"
# shellcheck source=lib/env.sh
[ -f "$_SCRIPT_DIR/env.sh" ] && source "$_SCRIPT_DIR/env.sh"

# 1. Check if Nginx is installed
nginx_is_installed() {
    local bin="${NGINX_BIN:-nginx}"
    command -v "$bin" >/dev/null 2>&1
}

# 2. Extract Nginx Version
nginx_get_version() {
    local bin="${NGINX_BIN:-nginx}"
    if ! nginx_is_installed; then
        echo "not_installed"
        return 1
    fi

    local raw_ver
    raw_ver="$("$bin" -v 2>&1 || true)"
    # Extract pattern nginx/1.24.0
    if [[ "$raw_ver" =~ nginx/([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    echo "unknown"
    return 0
}

# Version comparison: returns 0 if ver1 >= ver2, 1 if ver1 < ver2
nginx_version_ge() {
    local ver1="$1"
    local ver2="$2"

    if [ "$ver1" = "$ver2" ]; then
        return 0
    fi

    local lower
    lower="$(printf '%s\n%s' "$ver1" "$ver2" | sort -V | head -n 1)"
    if [ "$lower" = "$ver2" ]; then
        return 0
    else
        return 1
    fi
}

# Check if current Nginx supports modern `http2 on;` directive (Nginx >= 1.25.1)
nginx_supports_http2_directive() {
    local ver
    ver="$(nginx_get_version)"
    if [ "$ver" = "not_installed" ] || [ "$ver" = "unknown" ]; then
        return 1
    fi

    if nginx_version_ge "$ver" "1.25.1"; then
        return 0
    else
        return 1
    fi
}

# 3. Check if Nginx is actively running
nginx_is_running() {
    if [ "${EUID:-$(id -u)}" -eq 0 ] && command -v systemctl >/dev/null 2>&1 && [ -d "/run/systemd/system" ]; then
        if systemctl --no-ask-password is-active --quiet nginx 2>/dev/null; then
            return 0
        fi
    fi

    if pgrep -x nginx >/dev/null 2>&1 || pidof nginx >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# 4. Install Nginx across distros
nginx_install() {
    if nginx_is_installed; then
        ui_info "Nginx 已安装，版本为: $(nginx_get_version)"
        return 0
    fi

    ui_info "正在通过系统包管理器 ($PKG_MANAGER) 安装 Nginx..."
    pkg_update || true
    if pkg_install nginx; then
        ui_success "Nginx 安装成功: $(nginx_get_version)"
        return 0
    else
        ui_error "Nginx 自动安装失败，请检查网络或软件源配置。"
        return 1
    fi
}

# 5. Syntax Test
nginx_test() {
    local bin="${NGINX_BIN:-nginx}"
    local custom_conf="${1:-}"

    if ! nginx_is_installed; then
        ui_error "Nginx 未安装，无法执行语法测试。"
        return 2
    fi

    local test_cmd=("$bin" "-t")
    if [ -n "$custom_conf" ]; then
        test_cmd=("$bin" "-t" "-c" "$custom_conf")
    fi

    local output=""
    local ret=0
    output="$("${test_cmd[@]}" 2>&1)" || ret=$?

    if [ "$ret" -eq 0 ]; then
        ui_debug "Nginx 配置文件语法检查通过。"
        return 0
    else
        ui_error "Nginx 配置文件语法校验失败:"
        echo "$output" >&2
        ui_log "ERROR" "Nginx test failed: $output"
        return 1
    fi
}

# 6. Smooth Reload (with strict pre-test verification)
nginx_reload() {
    local bin="${NGINX_BIN:-nginx}"

    ui_info "正在校验 Nginx 配置文件语法..."
    if ! nginx_test; then
        ui_error "Nginx 语法自检未通过，已阻断重载操作，线上服务保持稳定。"
        return 1
    fi

    ui_info "语法校验通过，正在平滑重载 Nginx..."
    if [ "${EUID:-$(id -u)}" -eq 0 ] && command -v systemctl >/dev/null 2>&1 && [ -d "/run/systemd/system" ] && systemctl --no-ask-password is-active --quiet nginx 2>/dev/null; then
        if systemctl --no-ask-password reload nginx 2>/dev/null; then
            ui_success "Nginx 已成功平滑重载 (systemctl reload)。"
            return 0
        fi
    fi

    # Fallback to direct signal
    if "$bin" -s reload 2>/dev/null; then
        ui_success "Nginx 已成功平滑重载 (nginx -s reload)。"
        return 0
    else
        ui_warn "平滑重载信号发送失败，尝试启动 Nginx 服务..."
        nginx_start
    fi
}

# 7. Start / Stop / Restart Service
nginx_start() {
    local bin="${NGINX_BIN:-nginx}"
    if nginx_is_running; then
        ui_info "Nginx 已经在运行中。"
        return 0
    fi

    if ! nginx_test; then
        ui_error "Nginx 语法错误，拒绝启动服务。"
        return 1
    fi

    ui_info "正在启动 Nginx 服务..."
    if [ "${EUID:-$(id -u)}" -eq 0 ] && command -v systemctl >/dev/null 2>&1 && [ -d "/run/systemd/system" ]; then
        systemctl --no-ask-password start nginx 2>/dev/null || systemctl --no-ask-password restart nginx 2>/dev/null || true
        systemctl --no-ask-password enable nginx 2>/dev/null || true
    else
        "$bin" 2>/dev/null || true
    fi

    if nginx_is_running; then
        ui_success "Nginx 服务已启动。"
        return 0
    else
        ui_error "Nginx 启动失败，请排查 80 端口占用或系统日志。"
        return 1
    fi
}

nginx_stop() {
    local bin="${NGINX_BIN:-nginx}"
    if ! nginx_is_running; then
        ui_info "Nginx 已经处于停止状态。"
        return 0
    fi

    ui_info "正在停止 Nginx 服务..."
    if [ "${EUID:-$(id -u)}" -eq 0 ] && command -v systemctl >/dev/null 2>&1 && [ -d "/run/systemd/system" ]; then
        systemctl --no-ask-password stop nginx 2>/dev/null || true
    else
        "$bin" -s stop 2>/dev/null || pkill -x nginx 2>/dev/null || true
    fi

    if ! nginx_is_running; then
        ui_success "Nginx 服务已停止。"
        return 0
    else
        ui_error "Nginx 停止失败。"
        return 1
    fi
}

nginx_restart() {
    nginx_stop || true
    sleep 0.5
    nginx_start
}

# 8. Ensure essential directories exist
nginx_ensure_dirs() {
    local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"
    local conf_dir="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"
    local backup_dir="${NGINX_BACKUP_DIR:-/etc/nginx/conf.d/.backup}"

    if [ ! -d "$webroot" ]; then
        ui_info "创建 ACME Webroot 穿透验证目录: $webroot"
        mkdir -p "$webroot" 2>/dev/null || true
        chmod 755 "$webroot" 2>/dev/null || true
    fi

    if [ ! -d "$conf_dir" ]; then
        mkdir -p "$conf_dir" 2>/dev/null || true
    fi

    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir" 2>/dev/null || true
        chmod 700 "$backup_dir" 2>/dev/null || true
    fi
}

# 9. Ensure nginx.conf includes conf.d/*.conf
nginx_ensure_include_conf_d() {
    local main_conf="${NGINX_MAIN_CONF:-/etc/nginx/nginx.conf}"
    local conf_dir="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"

    if [ ! -f "$main_conf" ]; then
        ui_warn "未找到主配置文件: $main_conf，跳过 include 检查。"
        return 0
    fi

    # Check if include conf.d/*.conf already exists in main conf
    if grep -E "include[[:space:]]+.*conf\.d/\*\.conf;" "$main_conf" >/dev/null 2>&1; then
        ui_debug "Nginx 主配置已包含 conf.d/*.conf 引入规则。"
        return 0
    fi

    ui_info "正在向 $main_conf 的 http 块中注入 include ${conf_dir}/*.conf 规则..."
    # Inject before the closing bracket of http block or at end
    if grep -q "http {" "$main_conf"; then
        # Backup first
        cp "$main_conf" "${main_conf}.bak_ngx_cert" 2>/dev/null || true
        # Insert include line after http {
        sed -i "/http {/a \    include ${conf_dir}/*.conf;" "$main_conf"
        if nginx_test; then
            ui_success "成功为 $main_conf 注入 include 规则。"
            rm -f "${main_conf}.bak_ngx_cert"
            return 0
        else
            ui_error "注入 include 规则后语法校验失败，正在自动回滚..."
            mv "${main_conf}.bak_ngx_cert" "$main_conf"
            return 1
        fi
    fi

    return 0
}

# 10. Setup Global ACME Webroot Interception Rule
nginx_setup_global_acme() {
    local tpl_dir="${NGX_TEMPLATES_DIR:-$_SCRIPT_DIR/../templates}"
    local tpl_file="${tpl_dir}/acme-global.conf.tpl"
    local target_file="${NGINX_CONF_DIR:-/etc/nginx/conf.d}/000-default-acme.conf"
    local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"

    nginx_ensure_dirs

    if [ ! -f "$tpl_file" ]; then
        ui_error "未找到模板文件: $tpl_file"
        return 1
    fi

    local ipv6_listen=""
    if [ "${HAS_IPV6:-0}" -eq 1 ]; then
        ipv6_listen="listen [::]:80 default_server;"
    fi

    ui_info "正在注入全局 ACME Webroot 穿透规则 (000-default-acme.conf)..."
    sed -e "s|{{ACME_WEBROOT_DIR}}|${webroot}|g" \
        -e "s|{{IPV6_LISTEN_80}}|${ipv6_listen}|g" \
        "$tpl_file" > "$target_file"

    ui_success "全局 ACME 穿透规则已生成至: $target_file"
    return 0
}

# 11. Setup Global WebSocket Upgrade Map
nginx_setup_websocket_map() {
    local tpl_dir="${NGX_TEMPLATES_DIR:-$_SCRIPT_DIR/../templates}"
    local tpl_file="${tpl_dir}/websocket-map.conf.tpl"
    local target_file="${NGINX_CONF_DIR:-/etc/nginx/conf.d}/000-websocket-map.conf"

    nginx_ensure_dirs

    if [ ! -f "$tpl_file" ]; then
        ui_error "未找到模板文件: $tpl_file"
        return 1
    fi

    ui_info "正在注入全局 WebSocket Map 映射规则 (000-websocket-map.conf)..."
    cp "$tpl_file" "$target_file"
    ui_success "WebSocket 映射规则已就绪: $target_file"
    return 0
}

# 12. Full Bootstrap for Nginx Environment
nginx_bootstrap() {
    env_ensure_base_deps || true
    if ! nginx_is_installed; then
        ui_info "未检测到 Nginx，正在自动安装..."
        nginx_install || true
    fi
    nginx_ensure_dirs
    nginx_ensure_include_conf_d || true
    nginx_setup_global_acme
    nginx_setup_websocket_map
    if nginx_is_installed; then
        nginx_reload || true
    fi
}

# 13. Formatted Status Summary for TUI
nginx_status_summary() {
    local installed="未安装"
    local version="N/A"
    local running="已停止"

    if nginx_is_installed; then
        installed="已安装"
        version="$(nginx_get_version)"
        if nginx_is_running; then
            running="运行中"
        fi
    fi

    echo "Nginx 状态: ${installed} (${version}) | 进程: ${running}"
}
