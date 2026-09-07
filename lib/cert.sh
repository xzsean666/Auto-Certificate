#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - lib/cert.sh
# SSL/TLS Certificate Lifecycle Engine (Certbot, Webroot, Renewal & Dashboard)
# ==============================================================================

# Prevent multiple inclusions
if [ -n "${_NGX_LIB_CERT_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_NGX_LIB_CERT_LOADED=1

# Ensure dependencies are loaded
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
[ -f "$_SCRIPT_DIR/../config.env" ] && source "$_SCRIPT_DIR/../config.env"
# shellcheck source=lib/ui.sh
[ -f "$_SCRIPT_DIR/ui.sh" ] && source "$_SCRIPT_DIR/ui.sh"
# shellcheck source=lib/env.sh
[ -f "$_SCRIPT_DIR/env.sh" ] && source "$_SCRIPT_DIR/env.sh"
# shellcheck source=lib/nginx.sh
[ -f "$_SCRIPT_DIR/nginx.sh" ] && source "$_SCRIPT_DIR/nginx.sh"

LETSENCRYPT_LIVE_DIR="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}"

# 1. Check if Certbot is installed
cert_is_installed() {
    local bin="${CERTBOT_BIN:-certbot}"
    command -v "$bin" >/dev/null 2>&1
}

# 2. Automatically Install Certbot
cert_install() {
    if cert_is_installed; then
        ui_info "Certbot 已经安装。"
        return 0
    fi

    ui_info "正在通过系统包管理器 ($PKG_MANAGER) 安装 Certbot..."
    pkg_update || true

    case "$PKG_MANAGER" in
        apt)
            pkg_install certbot
            ;;
        dnf|yum)
            pkg_install epel-release 2>/dev/null || true
            pkg_install certbot
            ;;
        apk)
            pkg_install certbot
            ;;
        pacman)
            pkg_install certbot
            ;;
        *)
            ui_error "未知的包管理器，无法自动安装 Certbot。"
            return 1
            ;;
    esac

    if cert_is_installed; then
        ui_success "Certbot 安装成功。"
        return 0
    else
        ui_error "Certbot 安装失败，请检查软件源或网络。"
        return 1
    fi
}

# 3. Calculate Certificate Remaining Days
cert_get_remaining_days() {
    local cert_file="$1"

    if [ ! -f "$cert_file" ]; then
        echo "-1"
        return 1
    fi

    if ! command -v openssl >/dev/null 2>&1; then
        echo "unknown"
        return 0
    fi

    local end_date_str
    end_date_str="$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2 || true)"
    if [ -z "$end_date_str" ]; then
        echo "-1"
        return 1
    fi

    local end_ts curr_ts diff_sec diff_days
    # Convert date string to unix timestamp (supports GNU date and BSD date)
    end_ts="$(date -d "$end_date_str" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$end_date_str" +%s 2>/dev/null || echo "0")"
    curr_ts="$(date +%s)"

    if [ "$end_ts" -eq 0 ]; then
        echo "unknown"
        return 0
    fi

    diff_sec=$((end_ts - curr_ts))
    diff_days=$((diff_sec / 86400))

    echo "$diff_days"
}

# 4. Get Human-readable Expiration Date
cert_get_expire_date() {
    local cert_file="$1"
    if [ ! -f "$cert_file" ]; then
        echo "N/A"
        return 1
    fi

    local end_date_str
    end_date_str="$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2 || true)"
    if [ -n "$end_date_str" ]; then
        date -d "$end_date_str" "+%Y-%m-%d" 2>/dev/null || echo "$end_date_str"
    else
        echo "N/A"
    fi
}

# 5. Status Badge & Alert Level
cert_get_status_level() {
    local days="$1"
    local warn_days="${CERT_WARN_DAYS:-30}"
    local crit_days="${CERT_CRITICAL_DAYS:-15}"

    if [ "$days" = "unknown" ]; then
        echo "unknown"
    elif [ "$days" -le 0 ]; then
        echo "expired"
    elif [ "$days" -le "$crit_days" ]; then
        echo "critical"
    elif [ "$days" -le "$warn_days" ]; then
        echo "warning"
    else
        echo "safe"
    fi
}

cert_get_status_badge() {
    local days="$1"
    local level
    level="$(cert_get_status_level "$days")"

    case "$level" in
        safe)
            echo -e "${UI_CLR_GREEN}🟢 有效 (${days}天)${UI_CLR_RESET}"
            ;;
        warning)
            echo -e "${UI_CLR_YELLOW}🟡 即将到期 (${days}天)${UI_CLR_RESET}"
            ;;
        critical)
            echo -e "${UI_CLR_RED}🔴 紧急 (${days}天)${UI_CLR_RESET}"
            ;;
        expired)
            echo -e "${UI_CLR_RED}🔴 已过期 (${days}天)${UI_CLR_RESET}"
            ;;
        *)
            echo -e "${UI_CLR_DIM}⚪ 未知${UI_CLR_RESET}"
            ;;
    esac
}

# 6. Check if valid cert already exists for a domain
cert_exists_and_valid() {
    local domain="$1"
    local live_dir="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$domain"
    local cert_file="$live_dir/fullchain.pem"

    if [ -f "$cert_file" ]; then
        local days
        days="$(cert_get_remaining_days "$cert_file")"
        if [ "$days" -gt "${CERT_WARN_DAYS:-30}" ]; then
            return 0
        fi
    fi
    return 1
}

# 7. Issue Certificate via Webroot Mode (Primary Strategy - Zero Downtime)
cert_issue_webroot() {
    local domain="$1"
    local email="$2"
    local staging="${3:-$CERTBOT_STAGING}"
    local force="${4:-0}"
    local bin="${CERTBOT_BIN:-certbot}"
    local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"

    if [ -z "$domain" ] || [ -z "$email" ]; then
        ui_error "域名与邮箱不能为空。"
        return 1
    fi

    # Ensure Certbot is installed
    if ! cert_is_installed; then
        cert_install || return 1
    fi

    # Ensure Webroot dir & ACME interception are active
    nginx_ensure_dirs

    # Check if existing certificate is already valid
    local cert_target="${LETSENCRYPT_LIVE_DIR}/$domain/fullchain.pem"
    local key_target="${LETSENCRYPT_LIVE_DIR}/$domain/privkey.pem"

    if [ "$force" != "1" ] && [ "$force" != "--force" ] && [ -f "$cert_target" ]; then
        local days
        days="$(cert_get_remaining_days "$cert_target")"
        if [ "$days" -gt 30 ]; then
            ui_info "域名 ${domain} 的证书已存在且剩余 ${days} 天，无需重复签发 (可使用 --force 强制覆盖)。"
            echo "SSL_CERT_PATH=$cert_target"
            echo "SSL_KEY_PATH=$key_target"
            return 0
        fi
    fi

    local cert_args=(
        "certonly"
        "--webroot"
        "-w" "$webroot"
        "-d" "$domain"
        "--email" "$email"
        "--agree-tos"
        "--no-eff-email"
        "--non-interactive"
    )

    if [ "$staging" = "1" ] || [ "$staging" = "true" ] || [ "$staging" = "--staging" ]; then
        ui_warn "启用 Let's Encrypt Staging 沙箱测试环境 (--test-cert)..."
        cert_args+=("--test-cert")
    fi

    if [ "$force" = "1" ] || [ "$force" = "--force" ]; then
        cert_args+=("--force-renewal")
    fi

    ui_info "正在为 ${domain} 申请 Let's Encrypt SSL 证书 (Webroot: ${webroot})..."
    local out=""
    local ret=0
    out="$("$bin" "${cert_args[@]}" 2>&1)" || ret=$?

    if [ "$ret" -eq 0 ] && [ -f "$cert_target" ]; then
        ui_success "Let's Encrypt 证书申请成功！"
        ui_info "证书文件: $cert_target"
        ui_info "密钥文件: $key_target"
        echo "SSL_CERT_PATH=$cert_target"
        echo "SSL_KEY_PATH=$key_target"
        return 0
    else
        ui_error "证书签发失败！Certbot 输出如下:"
        echo "$out" >&2
        ui_log "ERROR" "Certbot issuance failed for $domain: $out"
        return 1
    fi
}

# 8. Issue Certificate via Standalone Mode (Fallback Strategy)
cert_issue_standalone() {
    local domain="$1"
    local email="$2"
    local staging="${3:-$CERTBOT_STAGING}"
    local bin="${CERTBOT_BIN:-certbot}"

    if [ -z "$domain" ] || [ -z "$email" ]; then
        ui_error "域名与邮箱不能为空。"
        return 1
    fi

    if ! cert_is_installed; then
        cert_install || return 1
    fi

    local cert_target="${LETSENCRYPT_LIVE_DIR}/$domain/fullchain.pem"
    local key_target="${LETSENCRYPT_LIVE_DIR}/$domain/privkey.pem"

    local cert_args=(
        "certonly"
        "--standalone"
        "-d" "$domain"
        "--email" "$email"
        "--agree-tos"
        "--no-eff-email"
        "--non-interactive"
    )

    if [ "$staging" = "1" ] || [ "$staging" = "true" ] || [ "$staging" = "--staging" ]; then
        cert_args+=("--test-cert")
    fi

    ui_info "正在通过 Standalone 独立模式为 ${domain} 申请证书..."
    local out=""
    local ret=0
    out="$("$bin" "${cert_args[@]}" 2>&1)" || ret=$?

    if [ "$ret" -eq 0 ] && [ -f "$cert_target" ]; then
        ui_success "Standalone 证书申请成功！"
        echo "SSL_CERT_PATH=$cert_target"
        echo "SSL_KEY_PATH=$key_target"
        return 0
    else
        ui_error "Standalone 证书申请失败: $out"
        return 1
    fi
}

# 9. List All Certificates (Dashboard View)
cert_list() {
    local live_dir="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}"

    ui_section "受管 Let's Encrypt 证书大盘"

    if [ ! -d "$live_dir" ]; then
        ui_info "未检测到已申请的证书目录 ($live_dir)。"
        return 0
    fi

    local cert_count=0
    printf "%-30s | %-12s | %-12s | %-15s\n" "域名 / 证书名称" "状态" "剩余天数" "到期日期"
    echo "--------------------------------------------------------------------------------"

    # Iterate through certificate directories
    for d in "$live_dir"/*; do
        if [ -d "$d" ]; then
            local domain_name
            domain_name="$(basename "$d")"
            [ "$domain_name" = "README" ] && continue

            local cert_file="$d/fullchain.pem"
            [ ! -f "$cert_file" ] && cert_file="$d/cert.pem"

            if [ -f "$cert_file" ]; then
                cert_count=$((cert_count + 1))
                local days exp_date badge level
                days="$(cert_get_remaining_days "$cert_file")"
                exp_date="$(cert_get_expire_date "$cert_file")"
                level="$(cert_get_status_level "$days")"

                local status_txt="有效"
                [ "$level" = "warning" ] && status_txt="即将到期"
                [ "$level" = "critical" ] && status_txt="紧急"
                [ "$level" = "expired" ] && status_txt="已过期"

                printf "%-30s | %-12s | %-12s | %-15s\n" "$domain_name" "$status_txt" "${days} 天" "$exp_date"
            fi
        fi
    done

    if [ "$cert_count" -eq 0 ]; then
        echo "当前暂无受管证书。"
    else
        echo "--------------------------------------------------------------------------------"
        echo "共计 ${cert_count} 张受管 SSL 证书。"
    fi
}

# 10. Renew Certificates
cert_renew() {
    local force="${1:-0}"
    local dry_run="${2:-0}"
    local bin="${CERTBOT_BIN:-certbot}"
    local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"

    if ! cert_is_installed; then
        ui_error "Certbot 未安装，无法执行续期。"
        return 1
    fi

    local renew_args=(
        "renew"
        "--webroot"
        "-w" "$webroot"
        "--post-hook" "nginx -t && nginx -s reload"
        "--non-interactive"
    )

    if [ "$force" = "1" ] || [ "$force" = "--force" ]; then
        renew_args+=("--force-renewal")
    fi

    if [ "$dry_run" = "1" ] || [ "$dry_run" = "--dry-run" ]; then
        renew_args+=("--dry-run")
        ui_info "正在进行证书续期模拟演练 (--dry-run)..."
    else
        ui_info "正在执行证书自动化续期扫描..."
    fi

    local out=""
    local ret=0
    out="$("$bin" "${renew_args[@]}" 2>&1)" || ret=$?

    if [ "$ret" -eq 0 ]; then
        ui_success "证书续期操作完成！"
        echo "$out"
        return 0
    else
        ui_error "证书续期失败:"
        echo "$out" >&2
        return 1
    fi
}

# 11. Revoke Certificate
cert_revoke() {
    local domain="$1"
    local bin="${CERTBOT_BIN:-certbot}"
    local live_dir="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$domain"
    local cert_file="$live_dir/cert.pem"

    if [ -z "$domain" ]; then
        ui_error "必须指定要吊销的域名。"
        return 1
    fi

    if [ ! -f "$cert_file" ]; then
        cert_file="$live_dir/fullchain.pem"
    fi

    if [ ! -f "$cert_file" ]; then
        ui_error "未找到域名 ${domain} 的证书文件 ($live_dir)。"
        return 1
    fi

    ui_warn "正在吊销并删除 ${domain} 的证书..."
    local out=""
    local ret=0
    out="$("$bin" revoke --cert-path "$cert_file" --delete-after-revoke --non-interactive 2>&1)" || ret=$?

    if [ "$ret" -eq 0 ]; then
        ui_success "域名 ${domain} 的证书已成功吊销并清理！"
        return 0
    else
        ui_error "吊销证书失败: $out"
        return 1
    fi
}
