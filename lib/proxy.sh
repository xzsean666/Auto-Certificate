#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - lib/proxy.sh
# Production Reverse Proxy Engine, Template Rendering & Atomic Rollback
# ==============================================================================

# Prevent multiple inclusions
if [ -n "${_NGX_LIB_PROXY_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_NGX_LIB_PROXY_LOADED=1

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
# shellcheck source=lib/domain.sh
[ -f "$_SCRIPT_DIR/domain.sh" ] && source "$_SCRIPT_DIR/domain.sh"
# shellcheck source=lib/cert.sh
[ -f "$_SCRIPT_DIR/cert.sh" ] && source "$_SCRIPT_DIR/cert.sh"

# 1. Normalize upstream format (e.g. 127.0.0.1:3000 -> http://127.0.0.1:3000)
proxy_normalize_upstream() {
    local upstream="$1"
    if [[ "$upstream" =~ ^https?:// ]] || [[ "$upstream" =~ ^unix: ]]; then
        echo "$upstream"
    else
        echo "http://${upstream}"
    fi
}

# 2. Render Nginx Reverse Proxy Configuration (SSL Mode)
proxy_render_config() {
    local domain="$1"
    local upstream="$2"
    local cert_path="$3"
    local key_path="$4"
    local hsts="${5:-$DEFAULT_ENABLE_HSTS}"
    local body_size="${6:-$DEFAULT_CLIENT_MAX_BODY_SIZE}"
    local ws="${7:-$DEFAULT_ENABLE_WEBSOCKET}"

    local tpl_dir="${NGX_TEMPLATES_DIR:-$_SCRIPT_DIR/../templates}"
    local tpl_file="${tpl_dir}/proxy-ssl.conf.tpl"
    if [ ! -f "$tpl_file" ]; then
        ui_error "未找到反向代理模板: $tpl_file"
        return 1
    fi

    local norm_upstream
    norm_upstream="$(proxy_normalize_upstream "$upstream")"
    local now_str
    now_str="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
    local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"

    # IPv6 directives
    local ipv6_80=""
    local ipv6_443=""
    if [ "${HAS_IPV6:-0}" -eq 1 ]; then
        ipv6_80="listen [::]:80;"
    fi

    # HTTP/2 syntax adaptivity
    local ssl_listen_443="listen 443 ssl;"
    local http2_directive=""
    if nginx_supports_http2_directive; then
        ssl_listen_443="listen 443 ssl;"
        [ "${HAS_IPV6:-0}" -eq 1 ] && ipv6_443="listen [::]:443 ssl;"
        http2_directive="http2 on;"
    else
        # Legacy HTTP/2 syntax
        ssl_listen_443="listen 443 ssl http2;"
        [ "${HAS_IPV6:-0}" -eq 1 ] && ipv6_443="listen [::]:443 ssl http2;"
        http2_directive=""
    fi

    # HSTS Header
    local hsts_line=""
    if [ "$hsts" = "1" ] || [ "$hsts" = "true" ] || [ "$hsts" = "--hsts" ]; then
        hsts_line='add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;'
    fi

    # Read template and substitute variables safely
    sed \
        -e "s|{{DOMAIN}}|${domain}|g" \
        -e "s|{{CREATED_AT}}|${now_str}|g" \
        -e "s|{{UPSTREAM_TARGET}}|${norm_upstream}|g" \
        -e "s|{{ACME_WEBROOT_DIR}}|${webroot}|g" \
        -e "s|{{IPV6_LISTEN_80}}|${ipv6_80}|g" \
        -e "s|{{SSL_LISTEN_443}}|${ssl_listen_443}|g" \
        -e "s|{{IPV6_LISTEN_443}}|${ipv6_443}|g" \
        -e "s|{{HTTP2_DIRECTIVE}}|${http2_directive}|g" \
        -e "s|{{SSL_CERT_PATH}}|${cert_path}|g" \
        -e "s|{{SSL_KEY_PATH}}|${key_path}|g" \
        -e "s|{{HSTS_HEADER}}|${hsts_line}|g" \
        -e "s|{{CLIENT_MAX_BODY_SIZE}}|${body_size}|g" \
        -e "s|{{PROXY_CONNECT_TIMEOUT}}|${DEFAULT_PROXY_CONNECT_TIMEOUT:-60s}|g" \
        -e "s|{{PROXY_SEND_TIMEOUT}}|${DEFAULT_PROXY_SEND_TIMEOUT:-60s}|g" \
        -e "s|{{PROXY_READ_TIMEOUT}}|${DEFAULT_PROXY_READ_TIMEOUT:-60s}|g" \
        "$tpl_file"
}

# 3. Render Nginx Reverse Proxy Configuration (HTTP-Only / Cloudflare Proxy Mode)
proxy_render_http_config() {
    local domain="$1"
    local upstream="$2"
    local body_size="${3:-$DEFAULT_CLIENT_MAX_BODY_SIZE}"
    local ws="${4:-$DEFAULT_ENABLE_WEBSOCKET}"

    local tpl_dir="${NGX_TEMPLATES_DIR:-$_SCRIPT_DIR/../templates}"
    local tpl_file="${tpl_dir}/proxy-http.conf.tpl"
    if [ ! -f "$tpl_file" ]; then
        ui_error "未找到 HTTP 反向代理模板: $tpl_file"
        return 1
    fi

    local norm_upstream
    norm_upstream="$(proxy_normalize_upstream "$upstream")"
    local now_str
    now_str="$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
    local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"

    local ipv6_80=""
    if [ "${HAS_IPV6:-0}" -eq 1 ]; then
        ipv6_80="listen [::]:80;"
    fi

    sed \
        -e "s|{{DOMAIN}}|${domain}|g" \
        -e "s|{{CREATED_AT}}|${now_str}|g" \
        -e "s|{{UPSTREAM_TARGET}}|${norm_upstream}|g" \
        -e "s|{{ACME_WEBROOT_DIR}}|${webroot}|g" \
        -e "s|{{IPV6_LISTEN_80}}|${ipv6_80}|g" \
        -e "s|{{CLIENT_MAX_BODY_SIZE}}|${body_size}|g" \
        -e "s|{{PROXY_CONNECT_TIMEOUT}}|${DEFAULT_PROXY_CONNECT_TIMEOUT:-60s}|g" \
        -e "s|{{PROXY_SEND_TIMEOUT}}|${DEFAULT_PROXY_SEND_TIMEOUT:-60s}|g" \
        -e "s|{{PROXY_READ_TIMEOUT}}|${DEFAULT_PROXY_READ_TIMEOUT:-60s}|g" \
        "$tpl_file"
}

# 4. Transactional Write & Atomic Rollback Engine
proxy_apply_site_config() {
    local domain="$1"
    local config_content="$2"

    local conf_dir="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"
    local backup_dir="${NGINX_BACKUP_DIR:-/etc/nginx/conf.d/.backup}"
    local target_file="${conf_dir}/${domain}.conf"
    local temp_file="${conf_dir}/${domain}.conf.tmp"

    nginx_ensure_dirs

    # Step 1: Create snapshot backup of existing configuration
    local backup_file=""
    if [ -f "$target_file" ]; then
        local ts
        ts="$(date +%s)"
        backup_file="${backup_dir}/${domain}_${ts}.bak"
        ui_debug "正在备份已有站点配置至: $backup_file"
        cp "$target_file" "$backup_file" 2>/dev/null || true
    fi

    # Step 2: Write rendered content to temporary pre-write file
    echo "$config_content" > "$temp_file"

    # Step 3: Run Syntax Test
    ui_info "正在对新生成的站点配置进行语法预检验..."
    if ! nginx_test; then
        ui_error "Nginx 语法自检未通过，正在触发自动回滚..."
        rm -f "$temp_file"

        # Restore from backup if needed
        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            cp "$backup_file" "$target_file" 2>/dev/null || true
            ui_warn "已从历史快照 ($backup_file) 恢复原有配置。"
        fi

        ui_error "站点 ${domain} 配置应用失败，线上已有服务未受任何影响。"
        return 1
    fi

    # Step 4: Atomic rename & smooth reload
    mv "$temp_file" "$target_file"
    ui_success "配置文件原子写入成功: $target_file"

    if nginx_reload; then
        ui_success "站点 ${domain} 反向代理配置已成功生效！"
        return 0
    else
        ui_error "Nginx 平滑重载失败，正在执行紧急回滚..."
        if [ -n "$backup_file" ] && [ -f "$backup_file" ]; then
            mv "$backup_file" "$target_file"
            nginx_reload || true
        else
            rm -f "$target_file"
            nginx_reload || true
        fi
        return 1
    fi
}

# 5. Orchestrate Full Site Creation Workflow
proxy_add_site() {
    local domain="$1"
    local upstream="$2"
    local email="${3:-}"
    local hsts="${4:-1}"
    local body_size="${5:-50m}"
    local ws="${6:-1}"
    local skip_dns="${7:-0}"
    local staging="${8:-0}"
    local non_interactive="${9:-0}"
    local ssl_enabled="${10:-1}"
    local dns_mode="${11:-auto}"
    local cf_token="${12:-}"

    if [ -z "$domain" ] || [ -z "$upstream" ]; then
        ui_error "必须指定域名 (--domain) 与上游地址 (--upstream)。"
        return 1
    fi

    # Determine whether to use Cloudflare DNS-01 mode
    local use_dns_cf=0
    if [ "$dns_mode" = "dns_cf" ] || [ "$dns_mode" = "1" ] || [ "$dns_mode" = "cloudflare" ]; then
        use_dns_cf=1
    elif [ "$dns_mode" = "webroot" ] || [ "$dns_mode" = "0" ]; then
        use_dns_cf=0
    elif [ "$dns_mode" = "auto" ] || [ -z "$dns_mode" ]; then
        # Auto-detect: if cf_token provided, CF_DNS_API_TOKEN set, or DEFAULT_CERT_MODE is dns_cf
        if [ -n "${cf_token:-}" ] || [ -n "${CF_DNS_API_TOKEN:-}" ] || [ "${DEFAULT_CERT_MODE:-webroot}" = "dns_cf" ]; then
            use_dns_cf=1
        else
            use_dns_cf=0
        fi
    fi

    ui_section "开始配置反向代理站点: ${domain}"

    # Bootstrap Nginx global environment if needed
    nginx_bootstrap

    # Branch A: HTTP-Only Mode (No SSL / Cloudflare Flexible Mode)
    if [ "$ssl_enabled" = "0" ] || [ "$ssl_enabled" = "false" ] || [ "$ssl_enabled" = "--no-ssl" ] || [ "$ssl_enabled" = "--http-only" ]; then
        ui_info "配置模式: 纯 HTTP 80 端口反向代理 (适用于 Cloudflare 边缘 SSL / 内网转发)..."
        local rendered_http
        rendered_http="$(proxy_render_http_config "$domain" "$upstream" "$body_size" "$ws")"

        if proxy_apply_site_config "$domain" "$rendered_http"; then
            ui_section "🎉 站点 ${domain} (HTTP 模式) 配置完成"
            ui_info "访问入口: http://${domain}"
            ui_info "上游目标: $(proxy_normalize_upstream "$upstream")"
            ui_info "Nginx 配置文件: ${NGINX_CONF_DIR:-/etc/nginx/conf.d}/${domain}.conf"
            return 0
        else
            return 1
        fi
    fi

    # Branch B: Standard HTTPS + SSL Certificate Mode
    # Step 1: DNS Pre-flight Inspection
    if ! domain_verify_dns "$domain" "$skip_dns" "$non_interactive" "$use_dns_cf"; then
        ui_error "DNS 预检失败，终止操作。"
        return 3
    fi

    # Step 2: Acquire SSL Certificate
    local clean_domain="${domain#\*.}"
    local cert_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$domain/fullchain.pem"
    local key_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$domain/privkey.pem"
    if [ ! -f "$cert_path" ] && [ -f "${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/fullchain.pem" ]; then
        cert_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/fullchain.pem"
        key_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/privkey.pem"
    fi

    if ! cert_exists_and_valid "$domain"; then
        if [ -z "$email" ]; then
            if [ "$non_interactive" = "1" ]; then
                email="admin@${clean_domain}"
            else
                email="$(ui_prompt "请输入 Let's Encrypt 登记联系邮箱" "admin@${clean_domain}")"
            fi
        fi

        if [ "$use_dns_cf" -eq 1 ]; then
            ui_info "配置模式: Cloudflare DNS-01 验证模式 (无公网80端口依赖)..."
            if ! cert_issue_dns_cloudflare "$domain" "$email" "$cf_token" "$staging"; then
                ui_error "证书签发失败，终止配置反向代理。"
                return 1
            fi
            if [ ! -f "$cert_path" ] && [ -f "${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/fullchain.pem" ]; then
                cert_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/fullchain.pem"
                key_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/privkey.pem"
            fi
        else
            # Pre-provision temporary dedicated HTTP-01 challenge route for domain
            local conf_dir="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"
            local site_conf="${conf_dir}/${domain}.conf"
            local temp_conf_created=0
            if [ ! -f "$site_conf" ]; then
                ui_info "正在为 ${domain} 预置 HTTP-01 验证穿透通道..."
                local webroot="${ACME_WEBROOT_DIR:-/var/www/certbot}"
                cat <<EOF > "$site_conf"
server {
    listen 80;
    server_name ${domain};

    location ^~ /.well-known/acme-challenge/ {
        root ${webroot};
        default_type "text/plain";
        try_files \$uri =404;
    }

    location / {
        return 404;
    }
}
EOF
                if nginx_reload; then
                    temp_conf_created=1
                else
                    rm -f "$site_conf"
                    nginx_reload || true
                fi
            fi

            if ! cert_issue_webroot "$domain" "$email" "$staging"; then
                if [ "$temp_conf_created" -eq 1 ]; then
                    rm -f "$site_conf"
                    nginx_reload || true
                fi
                ui_error "证书签发失败，终止配置反向代理。"
                return 1
            fi
        fi
    else
        ui_info "检测到 ${domain} 证书已存在且有效，直接复用。"
    fi

    # Step 3: Render and apply configuration
    local rendered
    rendered="$(proxy_render_config "$domain" "$upstream" "$cert_path" "$key_path" "$hsts" "$body_size" "$ws")"

    if proxy_apply_site_config "$domain" "$rendered"; then
        ui_section "🎉 站点 ${domain} 配置完成"
        ui_info "访问入口: https://${domain}"
        ui_info "上游目标: $(proxy_normalize_upstream "$upstream")"
        ui_info "SSL 证书: ${cert_path}"
        ui_info "Nginx 配置文件: ${NGINX_CONF_DIR:-/etc/nginx/conf.d}/${domain}.conf"
        return 0
    else
        return 1
    fi
}

# 5. List All Active Proxy Sites
proxy_list_sites() {
    nginx_detect_paths
    local conf_dir="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"

    ui_section "当前受管反向代理站点列表"

    if [ ! -d "$conf_dir" ]; then
        ui_info "未检测到 Nginx 配置目录 ($conf_dir)。"
        return 0
    fi

    local site_count=0
    printf "%-28s | %-26s | %-12s | %-8s\n" "域名 / 虚拟主机" "上游目标 (Upstream)" "SSL 状态" "HSTS"
    echo "--------------------------------------------------------------------------------"

    for f in "$conf_dir"/*.conf; do
        if [ -f "$f" ]; then
            local fname
            fname="$(basename "$f")"
            # Skip global helper configs
            [[ "$fname" =~ ^000-.*$ ]] && continue
            [[ "$fname" =~ \.tmp$ ]] && continue
            [[ "$fname" =~ \.bak$ ]] && continue

            local domain="${fname%.conf}"
            local upstream="N/A"
            local ssl_status="未配置"
            local hsts_status="关闭"

            # Parse upstream from proxy_pass
            local pass_line
            pass_line="$(grep -E '^[[:space:]]*proxy_pass[[:space:]]+' "$f" | head -n 1 || true)"
            if [[ "$pass_line" =~ proxy_pass[[:space:]]+([^;]+)\; ]]; then
                upstream="${BASH_REMATCH[1]}"
            fi

            # Check SSL cert file
            local cert_file="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$domain/fullchain.pem"
            if [ -f "$cert_file" ]; then
                local days
                days="$(cert_get_remaining_days "$cert_file")"
                local level
                level="$(cert_get_status_level "$days")"
                [ "$level" = "safe" ] && ssl_status="🟢 有效(${days}d)"
                [ "$level" = "warning" ] && ssl_status="🟡 预警(${days}d)"
                [ "$level" = "critical" ] && ssl_status="🔴 紧急(${days}d)"
                [ "$level" = "expired" ] && ssl_status="🔴 过期"
            fi

            # Check HSTS
            if grep -q "Strict-Transport-Security" "$f"; then
                hsts_status="开启"
            fi

            site_count=$((site_count + 1))
            printf "%-28s | %-26s | %-12s | %-8s\n" "$domain" "$upstream" "$ssl_status" "$hsts_status"
        fi
    done

    if [ "$site_count" -eq 0 ]; then
        echo "当前暂无配置的反向代理站点。"
    else
        echo "--------------------------------------------------------------------------------"
        echo "共计 ${site_count} 个受管反向代理站点。"
    fi
}

# 6. Get Site Config Details
proxy_get_site() {
    nginx_detect_paths
    local domain="$1"
    local conf_file="${NGINX_CONF_DIR:-/etc/nginx/conf.d}/${domain}.conf"

    if [ -z "$domain" ]; then
        ui_error "必须指定要查询的域名。"
        return 1
    fi

    if [ -f "$conf_file" ]; then
        ui_section "站点配置文件: $conf_file"
        cat "$conf_file"
        return 0
    else
        ui_error "未找到站点 ${domain} 的配置文件 ($conf_file)。"
        return 1
    fi
}

# 7. Delete Site Configuration
proxy_delete_site() {
    nginx_detect_paths
    local domain="$1"
    local delete_cert="${2:-0}"
    local conf_file="${NGINX_CONF_DIR:-/etc/nginx/conf.d}/${domain}.conf"
    local backup_dir="${NGINX_BACKUP_DIR:-/etc/nginx/conf.d/.backup}"

    if [ -z "$domain" ]; then
        ui_error "必须指定要删除的域名。"
        return 1
    fi

    if [ ! -f "$conf_file" ]; then
        ui_warn "未找到站点 ${domain} 的配置文件 ($conf_file)。"
    else
        ui_info "正在归档并删除站点配置: $conf_file"
        mkdir -p "$backup_dir" 2>/dev/null || true
        cp "$conf_file" "${backup_dir}/${domain}_deleted_$(date +%s).bak" 2>/dev/null || true
        rm -f "$conf_file"
        nginx_reload || true
        ui_success "站点 ${domain} 反向代理配置已移除。"
    fi

    if [ "$delete_cert" = "1" ] || [ "$delete_cert" = "--delete-cert" ]; then
        cert_revoke "$domain" || true
    fi

    return 0
}
