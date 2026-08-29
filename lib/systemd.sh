#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - lib/systemd.sh
# Systemd Timer & Cron Automated Certificate Renewal Daemon Engine
# ==============================================================================

# Prevent multiple inclusions
if [ -n "${_NGX_LIB_SYSTEMD_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_NGX_LIB_SYSTEMD_LOADED=1

# Ensure dependencies are loaded
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
[ -f "$_SCRIPT_DIR/../config.env" ] && source "$_SCRIPT_DIR/../config.env"
# shellcheck source=lib/ui.sh
[ -f "$_SCRIPT_DIR/ui.sh" ] && source "$_SCRIPT_DIR/ui.sh"
# shellcheck source=lib/env.sh
[ -f "$_SCRIPT_DIR/env.sh" ] && source "$_SCRIPT_DIR/env.sh"
# shellcheck source=lib/cert.sh
[ -f "$_SCRIPT_DIR/cert.sh" ] && source "$_SCRIPT_DIR/cert.sh"

# 1. Check if Systemd is available
systemd_is_available() {
    if [ "${INIT_SYSTEM:-cron}" = "systemd" ] && command -v systemctl >/dev/null 2>&1 && [ -d "/run/systemd/system" ]; then
        return 0
    fi
    return 1
}

# 2. Setup Systemd Service & Timer
systemd_setup_timer() {
    local tpl_dir="${NGX_TEMPLATES_DIR:-$_SCRIPT_DIR/../templates}"
    local s_tpl="${tpl_dir}/certbot-renew.service.tpl"
    local t_tpl="${tpl_dir}/certbot-renew.timer.tpl"
    local system_dir="${SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"
    local s_name="${CERTBOT_RENEW_SERVICE_NAME:-certbot-renew.service}"
    local t_name="${CERTBOT_RENEW_TIMER_NAME:-certbot-renew.timer}"

    local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"
    local certbot_bin
    certbot_bin="$(command -v "${CERTBOT_BIN:-certbot}" 2>/dev/null || echo "/usr/bin/certbot")"
    local post_hook="nginx -t && systemctl reload nginx"

    if [ ! -f "$s_tpl" ] || [ ! -f "$t_tpl" ]; then
        ui_error "未找到 Systemd 服务或定时器模板文件。"
        return 1
    fi

    mkdir -p "$system_dir" 2>/dev/null || true

    ui_info "正在渲染并注入 Systemd 自动续期服务单元 (${s_name})..."
    sed \
        -e "s|{{CERTBOT_BIN}}|${certbot_bin}|g" \
        -e "s|{{ACME_WEBROOT_DIR}}|${webroot}|g" \
        -e "s|{{POST_HOOK_CMD}}|${post_hook}|g" \
        "$s_tpl" > "${system_dir}/${s_name}"

    ui_info "正在渲染并注入 Systemd 自动续期定时器 (${t_name}) [含 3600s 随机抖动]..."
    sed \
        -e "s|{{SYSTEMD_SYSTEM_DIR}}|${system_dir}|g" \
        -e "s|{{CERTBOT_RENEW_SERVICE_NAME}}|${s_name}|g" \
        "$t_tpl" > "${system_dir}/${t_name}"

    # Reload systemd and enable timer if in real system path as root
    if [ "$system_dir" = "/etc/systemd/system" ] && [ "${EUID:-$(id -u)}" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
        systemctl --no-ask-password daemon-reload 2>/dev/null || true
        systemctl --no-ask-password enable --now "$t_name" 2>/dev/null || true
    fi

    ui_success "Systemd 自动续期定时器已成功激活并运行！"
    return 0
}

# 3. Setup Cron Daemon (Fallback for Non-Systemd / Docker / Alpine)
cron_setup_renew() {
    local cron_dir="${CRON_D_DIR:-/etc/cron.d}"
    local cron_file="${cron_dir}/certbot-renew"
    local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"
    local certbot_bin
    certbot_bin="$(command -v "${CERTBOT_BIN:-certbot}" 2>/dev/null || echo "/usr/bin/certbot")"
    local post_hook="nginx -t && nginx -s reload"

    ui_info "正在为当前环境配置 Crontab 自动续期守护任务..."

    if [ -d "$cron_dir" ] && [ -w "$cron_dir" ]; then
        cat << EOF > "$cron_file"
# Automated certificate renewal managed by ngx-cert-manager
# Runs daily at 03:30 and 15:30
30 3,15 * * * root ${certbot_bin} renew --webroot -w ${webroot} --post-hook "${post_hook}" --quiet
EOF
        chmod 644 "$cron_file"
        ui_success "已成功注入系统 Cron 定时任务: $cron_file"
        return 0
    fi

    # Fallback to user crontab
    if command -v crontab >/dev/null 2>&1; then
        local current_cron
        current_cron="$(crontab -l 2>/dev/null || true)"
        if [[ "$current_cron" != *"certbot renew"* ]]; then
            (echo "$current_cron"; echo "30 3,15 * * * ${certbot_bin} renew --webroot -w ${webroot} --post-hook \"${post_hook}\" --quiet") | crontab -
            ui_success "已向当前用户 Crontab 追加自动续期任务。"
        else
            ui_info "Crontab 中已存在续期任务，无需重复注入。"
        fi
        return 0
    fi

    ui_warn "未找到 Cron 或 Systemd 环境，无法自动注入定时任务，请手动配置定时续期。"
    return 1
}

# 4. Bootstrap Automated Renewal Timer (Adaptive)
timer_bootstrap() {
    if systemd_is_available; then
        systemd_setup_timer
    else
        cron_setup_renew
    fi
}

# 5. Check Timer Status
systemd_status_timer() {
    local t_name="${CERTBOT_RENEW_TIMER_NAME:-certbot-renew.timer}"
    local system_dir="${SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"
    local cron_file="${CRON_D_DIR:-/etc/cron.d}/certbot-renew"

    ui_section "自动化续期守护状态"

    if systemd_is_available; then
        if [ -f "${system_dir}/${t_name}" ]; then
            echo -e "${UI_CLR_BOLD}Systemd Timer 状态:${UI_CLR_RESET}"
            systemctl --no-ask-password status "$t_name" --no-pager 2>/dev/null || true
            echo ""
            echo -e "${UI_CLR_BOLD}下一次触发时间计划:${UI_CLR_RESET}"
            systemctl --no-ask-password list-timers "$t_name" --no-pager 2>/dev/null || true
            return 0
        else
            ui_warn "Systemd 定时器未安装，可调用 timer_bootstrap 进行配置。"
            return 1
        fi
    else
        if [ -f "$cron_file" ]; then
            echo -e "${UI_CLR_BOLD}Crontab 任务配置 (${cron_file}):${UI_CLR_RESET}"
            cat "$cron_file"
            return 0
        elif crontab -l 2>/dev/null | grep -q "certbot renew"; then
            echo -e "${UI_CLR_BOLD}用户 Crontab 任务:${UI_CLR_RESET}"
            crontab -l 2>/dev/null | grep "certbot renew"
            return 0
        else
            ui_warn "未检测到已启用的 Cron 续期任务。"
            return 1
        fi
    fi
}

# 6. Trigger Immediate Renewal Test
systemd_trigger_now() {
    local s_name="${CERTBOT_RENEW_SERVICE_NAME:-certbot-renew.service}"

    ui_info "正在立即触发一次证书续期测试..."

    if [ "${EUID:-$(id -u)}" -eq 0 ] && systemd_is_available && [ -f "${SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}/${s_name}" ]; then
        if systemctl --no-ask-password start "$s_name" 2>/dev/null; then
            ui_success "已通过 Systemd 触发 Oneshot 续期服务 (${s_name})。"
            systemd_view_logs
            return 0
        fi
    fi

    # Fallback to direct cert_renew dry-run
    cert_renew "0" "1"
}

# 7. View Renewal Logs
systemd_view_logs() {
    local s_name="${CERTBOT_RENEW_SERVICE_NAME:-certbot-renew.service}"
    ui_section "证书自动续期审计日志"

    if systemd_is_available && command -v journalctl >/dev/null 2>&1; then
        journalctl --no-ask-password -u "$s_name" -n 30 --no-pager 2>/dev/null || true
    else
        if [ -f "$LOG_FILE" ]; then
            grep -E "\[(SUCCESS|WARN|ERROR|INFO)\]" "$LOG_FILE" | tail -n 30 || true
        else
            ui_info "暂无日志记录。"
        fi
    fi
}

# 8. Formatted Summary for TUI Dashboard
timer_status_summary() {
    local t_name="${CERTBOT_RENEW_TIMER_NAME:-certbot-renew.timer}"
    local system_dir="${SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"
    local cron_file="${CRON_D_DIR:-/etc/cron.d}/certbot-renew"

    if [ -f "${system_dir}/${t_name}" ]; then
        echo "[ 守护中 ] (Systemd Timer: ${t_name} 已激活)"
    elif [ -f "$cron_file" ] || (command -v crontab >/dev/null 2>&1 && crontab -l 2>/dev/null | grep -q "certbot renew"); then
        echo "[ 守护中 ] (Cron 自动续期守护中)"
    else
        echo "[ 未激活 ] (可一键启用守护)"
    fi
}
