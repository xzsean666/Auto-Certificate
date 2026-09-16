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

# Helper: generate Bearer auth block into temporary file if token is specified
_proxy_create_bearer_auth_snippet() {
    local token="$1"
    [ -z "$token" ] && return 0

    # Normalize token: replace spaces, commas to pipe (|) regex alternation
    local clean_token
    clean_token="$(echo "$token" | tr -d ' ' | tr ',' '|')"

    local auth_tmp
    auth_tmp="$(mktemp /tmp/ngx_bearer_XXXXXX.conf 2>/dev/null || mktemp)"
    cat << EOF > "$auth_tmp"
        # Bearer Token 访问鉴权 (保护无鉴权后端)
        set \$auth_valid 0;
        if (\$http_authorization ~* "^Bearer\s+(${clean_token})\$") {
            set \$auth_valid 1;
        }
        # 放行 CORS OPTIONS 预检请求 (兼容前端跨域)
        if (\$request_method = OPTIONS) {
            set \$auth_valid 1;
        }
        if (\$auth_valid = 0) {
            add_header Content-Type application/json always;
            add_header WWW-Authenticate 'Bearer realm="Restricted Access"' always;
            return 401 '{"code":401,"error":"Unauthorized","message":"Invalid or missing Bearer token"}\n';
        }
EOF
    echo "$auth_tmp"
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
    local custom_port="${8:-}"
    local bearer_token="${9:-}"

    local https_port
    https_port="$(nginx_detect_https_port "$custom_port")"

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
    local ssl_listen_443="listen ${https_port} ssl;"
    local http2_directive=""
    if nginx_supports_http2_directive; then
        ssl_listen_443="listen ${https_port} ssl;"
        [ "${HAS_IPV6:-0}" -eq 1 ] && ipv6_443="listen [::]:${https_port} ssl;"
        http2_directive="http2 on;"
    else
        # Legacy HTTP/2 syntax
        ssl_listen_443="listen ${https_port} ssl http2;"
        [ "${HAS_IPV6:-0}" -eq 1 ] && ipv6_443="listen [::]:${https_port} ssl http2;"
        http2_directive=""
    fi

    # HSTS Header
    local hsts_line=""
    if [ "$hsts" = "1" ] || [ "$hsts" = "true" ] || [ "$hsts" = "--hsts" ]; then
        hsts_line='add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;'
    fi

    # Bearer Auth snippet file
    local auth_snippet_file=""
    if [ -n "$bearer_token" ]; then
        auth_snippet_file="$(_proxy_create_bearer_auth_snippet "$bearer_token")"
    fi

    # Read template and substitute variables safely
    local rendered
    if [ -n "$auth_snippet_file" ] && [ -f "$auth_snippet_file" ]; then
        rendered="$(sed \
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
            -e "s|{{PROXY_SEND_TIMEOUT}}|${DEFAULT_PROXY_SEND_TIMEOUT:-600s}|g" \
            -e "s|{{PROXY_READ_TIMEOUT}}|${DEFAULT_PROXY_READ_TIMEOUT:-600s}|g" \
            "$tpl_file" | sed -e "/{{BEARER_AUTH_DIRECTIVE}}/{r $auth_snippet_file" -e "d}")"
        rm -f "$auth_snippet_file"
    else
        rendered="$(sed \
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
            -e "s|{{PROXY_SEND_TIMEOUT}}|${DEFAULT_PROXY_SEND_TIMEOUT:-600s}|g" \
            -e "s|{{PROXY_READ_TIMEOUT}}|${DEFAULT_PROXY_READ_TIMEOUT:-600s}|g" \
            -e "/{{BEARER_AUTH_DIRECTIVE}}/d" \
            "$tpl_file")"
    fi
    printf "%s\n" "$rendered"
}

# 3. Render Nginx Reverse Proxy Configuration (HTTP-Only / Cloudflare Proxy Mode)
proxy_render_http_config() {
    local domain="$1"
    local upstream="$2"
    local body_size="${3:-$DEFAULT_CLIENT_MAX_BODY_SIZE}"
    local ws="${4:-$DEFAULT_ENABLE_WEBSOCKET}"
    local bearer_token="${5:-}"

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

    local auth_snippet_file=""
    if [ -n "$bearer_token" ]; then
        auth_snippet_file="$(_proxy_create_bearer_auth_snippet "$bearer_token")"
    fi

    local rendered
    if [ -n "$auth_snippet_file" ] && [ -f "$auth_snippet_file" ]; then
        rendered="$(sed \
            -e "s|{{DOMAIN}}|${domain}|g" \
            -e "s|{{CREATED_AT}}|${now_str}|g" \
            -e "s|{{UPSTREAM_TARGET}}|${norm_upstream}|g" \
            -e "s|{{ACME_WEBROOT_DIR}}|${webroot}|g" \
            -e "s|{{IPV6_LISTEN_80}}|${ipv6_80}|g" \
            -e "s|{{CLIENT_MAX_BODY_SIZE}}|${body_size}|g" \
            -e "s|{{PROXY_CONNECT_TIMEOUT}}|${DEFAULT_PROXY_CONNECT_TIMEOUT:-60s}|g" \
            -e "s|{{PROXY_SEND_TIMEOUT}}|${DEFAULT_PROXY_SEND_TIMEOUT:-600s}|g" \
            -e "s|{{PROXY_READ_TIMEOUT}}|${DEFAULT_PROXY_READ_TIMEOUT:-600s}|g" \
            "$tpl_file" | sed -e "/{{BEARER_AUTH_DIRECTIVE}}/{r $auth_snippet_file" -e "d}")"
        rm -f "$auth_snippet_file"
    else
        rendered="$(sed \
            -e "s|{{DOMAIN}}|${domain}|g" \
            -e "s|{{CREATED_AT}}|${now_str}|g" \
            -e "s|{{UPSTREAM_TARGET}}|${norm_upstream}|g" \
            -e "s|{{ACME_WEBROOT_DIR}}|${webroot}|g" \
            -e "s|{{IPV6_LISTEN_80}}|${ipv6_80}|g" \
            -e "s|{{CLIENT_MAX_BODY_SIZE}}|${body_size}|g" \
            -e "s|{{PROXY_CONNECT_TIMEOUT}}|${DEFAULT_PROXY_CONNECT_TIMEOUT:-60s}|g" \
            -e "s|{{PROXY_SEND_TIMEOUT}}|${DEFAULT_PROXY_SEND_TIMEOUT:-600s}|g" \
            -e "s|{{PROXY_READ_TIMEOUT}}|${DEFAULT_PROXY_READ_TIMEOUT:-600s}|g" \
            -e "/{{BEARER_AUTH_DIRECTIVE}}/d" \
            "$tpl_file")"
    fi
    printf "%s\n" "$rendered"
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
    local custom_https_port="${13:-}"
    local bearer_token="${14:-}"

    if [ -z "$domain" ] || [ -z "$upstream" ]; then
        ui_error "必须指定域名 (--domain) 与上游地址 (--upstream)。"
        return 1
    fi

    # Handle Bearer Token resolution (auto-generate vs custom token)
    local token_file_saved=""
    if [ "$bearer_token" = "auto" ] || [ "$bearer_token" = "gen" ] || [ "$bearer_token" = "1" ] || [ "$bearer_token" = "true" ]; then
        local tokens_dir="${NGX_TOKENS_DIR:-${NGX_APP_ROOT:-$_SCRIPT_DIR/..}/.tokens}"
        mkdir -p "$tokens_dir" 2>/dev/null || {
            tokens_dir="${HOME:-/tmp}/.ngx-cert-manager/tokens"
            mkdir -p "$tokens_dir" 2>/dev/null || true
        }
        chmod 700 "$tokens_dir" 2>/dev/null || true

        local random_part=""
        if command -v openssl >/dev/null 2>&1; then
            random_part="$(openssl rand -hex 24 2>/dev/null || true)"
        fi
        if [ -z "$random_part" ]; then
            random_part="$(tr -dc 'a-f0-9' < /dev/urandom 2>/dev/null | head -c 48 || date +%s%N | md5sum | head -c 48)"
        fi
        bearer_token="sk-${random_part}"
        local token_file="${tokens_dir}/${domain}.token"
        echo "$bearer_token" > "$token_file"
        chmod 600 "$token_file" 2>/dev/null || true
        token_file_saved="$token_file"

        ui_success "已为 ${domain} 自动生成高强度 Bearer Token 并保存至: ${token_file}"
        ui_info "自动生成的 Token 密钥: ${bearer_token}"
    elif [ -n "$bearer_token" ]; then
        # User specified token, also save to .tokens directory for record & convenience
        local tokens_dir="${NGX_TOKENS_DIR:-${NGX_APP_ROOT:-$_SCRIPT_DIR/..}/.tokens}"
        if mkdir -p "$tokens_dir" 2>/dev/null; then
            chmod 700 "$tokens_dir" 2>/dev/null || true
            local token_file="${tokens_dir}/${domain}.token"
            echo "$bearer_token" > "$token_file"
            chmod 600 "$token_file" 2>/dev/null || true
            token_file_saved="$token_file"
        fi
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
        rendered_http="$(proxy_render_http_config "$domain" "$upstream" "$body_size" "$ws" "$bearer_token")"

        if proxy_apply_site_config "$domain" "$rendered_http"; then
            ui_section "🎉 站点 ${domain} (HTTP 模式) 配置完成"
            ui_info "访问入口: http://${domain}"
            ui_info "上游目标: $(proxy_normalize_upstream "$upstream")"
            if [ -n "$bearer_token" ]; then
                ui_info "鉴权保护: 已启用 Bearer Token 访问控制 (HTTP 401 拦截未授权请求)"
                [ -n "$token_file_saved" ] && ui_info "凭证存储: Token 密钥已保存在 ${token_file_saved} (已加入 .gitignore，权限: 600)"
            fi
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
    local parent_domain="${domain#*.}"
    local cert_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$domain/fullchain.pem"
    local key_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$domain/privkey.pem"
    if [ ! -f "$cert_path" ] && [ -f "${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/fullchain.pem" ]; then
        cert_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/fullchain.pem"
        key_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$clean_domain/privkey.pem"
    elif [ ! -f "$cert_path" ] && [ "$parent_domain" != "$domain" ] && [ -f "${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$parent_domain/fullchain.pem" ]; then
        local p_cert="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$parent_domain/fullchain.pem"
        if openssl x509 -text -noout -in "$p_cert" 2>/dev/null | grep -qi "\*\.${parent_domain}"; then
            cert_path="$p_cert"
            key_path="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$parent_domain/privkey.pem"
            ui_info "检测到上级泛域名 (*.${parent_domain}) 证书有效，自动复用。"
        fi
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
    local effective_https_port
    effective_https_port="$(nginx_detect_https_port "$custom_https_port")"
    if [ "$effective_https_port" != "443" ]; then
        ui_info "HTTPS 监听端口: ${effective_https_port} (已适配 Nginx 443 智能分流架构，公网访问仍为标准 443)"
    fi

    local rendered
    rendered="$(proxy_render_config "$domain" "$upstream" "$cert_path" "$key_path" "$hsts" "$body_size" "$ws" "$effective_https_port" "$bearer_token")"

    if proxy_apply_site_config "$domain" "$rendered"; then
        ui_section "🎉 站点 ${domain} 配置完成"
        ui_info "访问入口: https://${domain}"
        ui_info "上游目标: $(proxy_normalize_upstream "$upstream")"
        if [ -n "$bearer_token" ]; then
            ui_info "鉴权保护: 已启用 Bearer Token 访问控制 (HTTP 401 拦截未授权请求)"
            [ -n "$token_file_saved" ] && ui_info "凭证存储: Token 密钥已保存在 ${token_file_saved} (已加入 .gitignore，权限: 600)"
        fi
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
            local cert_line
            cert_line="$(grep -E '^[[:space:]]*ssl_certificate[[:space:]]+' "$f" | head -n 1 || true)"
            local cert_file=""
            if [[ "$cert_line" =~ ssl_certificate[[:space:]]+([^;]+)\; ]]; then
                cert_file="${BASH_REMATCH[1]}"
            else
                cert_file="${LETSENCRYPT_LIVE_DIR:-/etc/letsencrypt/live}/$domain/fullchain.pem"
            fi

            if [ -n "$cert_file" ] && [ -f "$cert_file" ]; then
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

        local tokens_dir="${NGX_TOKENS_DIR:-${NGX_APP_ROOT:-$_SCRIPT_DIR/..}/.tokens}"
        local token_file="${tokens_dir}/${domain}.token"
        if [ -f "$token_file" ]; then
            echo ""
            ui_info "【关联 Bearer Token 凭据】: $token_file"
            echo "  Token: $(cat "$token_file")"
        fi
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

        # Cleanup associated token file if present
        local tokens_dir="${NGX_TOKENS_DIR:-${NGX_APP_ROOT:-$_SCRIPT_DIR/..}/.tokens}"
        local token_file="${tokens_dir}/${domain}.token"
        if [ -f "$token_file" ]; then
            rm -f "$token_file" 2>/dev/null || true
            ui_info "已清理关联的 Bearer Token 文件: $token_file"
        fi

        nginx_reload || true
        ui_success "站点 ${domain} 反向代理配置已移除。"
    fi

    if [ "$delete_cert" = "1" ] || [ "$delete_cert" = "--delete-cert" ]; then
        cert_revoke "$domain" || true
    fi

    return 0
}
