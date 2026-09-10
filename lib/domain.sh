#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - lib/domain.sh
# Public IP Probing, DNS Pre-flight Inspection & Port 80 Self-Healing Engine
# ==============================================================================

# Prevent multiple inclusions
if [ -n "${_NGX_LIB_DOMAIN_LOADED:-}" ]; then
    return 0 2>/dev/null || exit 0
fi
_NGX_LIB_DOMAIN_LOADED=1

# Ensure dependencies are loaded
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.env
[ -f "$_SCRIPT_DIR/../config.env" ] && source "$_SCRIPT_DIR/../config.env"
# shellcheck source=lib/ui.sh
[ -f "$_SCRIPT_DIR/ui.sh" ] && source "$_SCRIPT_DIR/ui.sh"
# shellcheck source=lib/env.sh
[ -f "$_SCRIPT_DIR/env.sh" ] && source "$_SCRIPT_DIR/env.sh"

# Helper: validate IPv4 regex
domain_is_valid_ipv4() {
    local ip="$1"
    local regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    if [[ "$ip" =~ $regex ]]; then
        # Check each octet <= 255
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if [ "$octet" -gt 255 ]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# 1. Multi-source Public IPv4 Discovery
domain_get_public_ipv4() {
    local timeout="${DNS_TIMEOUT:-5}"
    local apis=("${PUBLIC_IPV4_APIS[@]:-https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com}")

    for api in "${apis[@]}"; do
        local ip=""
        ip="$(curl -s -4 --connect-timeout "$timeout" --max-time "$timeout" "$api" 2>/dev/null | tr -d '[:space:]' || true)"
        if domain_is_valid_ipv4 "$ip"; then
            echo "$ip"
            return 0
        fi
    done

    # Fallback to local default route IP if public fetch failed
    if command -v ip >/dev/null 2>&1; then
        local local_ip
        local_ip="$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)"
        if domain_is_valid_ipv4 "$local_ip"; then
            echo "$local_ip"
            return 0
        fi
    fi

    echo "127.0.0.1"
    return 1
}

# 2. Multi-source Public IPv6 Discovery
domain_get_public_ipv6() {
    local timeout="${DNS_TIMEOUT:-5}"
    local apis=("${PUBLIC_IPV6_APIS[@]:-https://api6.ipify.org https://icanhazip.com}")

    for api in "${apis[@]}"; do
        local ip=""
        ip="$(curl -s -6 --connect-timeout "$timeout" --max-time "$timeout" "$api" 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ "$ip" =~ : ]]; then
            echo "$ip"
            return 0
        fi
    done

    echo ""
    return 1
}

# 3. Resolve Domain DNS A Records
domain_resolve_ipv4() {
    local domain="$1"
    local timeout="${DNS_TIMEOUT:-5}"
    local ips=()

    if [ -z "$domain" ]; then
        return 1
    fi

    # Strategy 1: dig
    if command -v dig >/dev/null 2>&1; then
        local res
        res="$(dig +short +time="$timeout" +tries=2 A "$domain" 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || true)"
        if [ -n "$res" ]; then
            echo "$res"
            return 0
        fi
    fi

    # Strategy 2: host
    if command -v host >/dev/null 2>&1; then
        local res
        res="$(host -t A -W "$timeout" "$domain" 2>/dev/null | awk '/has address/ {print $NF}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || true)"
        if [ -n "$res" ]; then
            echo "$res"
            return 0
        fi
    fi

    # Strategy 3: nslookup
    if command -v nslookup >/dev/null 2>&1; then
        local res
        res="$(nslookup -timeout="$timeout" "$domain" 2>/dev/null | awk '/^Address: / { print $2 }' | tail -n +2 | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || true)"
        if [ -n "$res" ]; then
            echo "$res"
            return 0
        fi
    fi

    # Strategy 4: getent
    if command -v getent >/dev/null 2>&1; then
        local res
        res="$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | sort -u || true)"
        if [ -n "$res" ]; then
            echo "$res"
            return 0
        fi
    fi

    return 1
}

# 4. Check if an IP belongs to Cloudflare CDN CIDRs
domain_is_cloudflare_ip() {
    local ip="$1"
    if ! domain_is_valid_ipv4 "$ip"; then
        return 1
    fi

    # Check against known Cloudflare CIDR prefixes
    local cf_cidrs=("${CLOUDFLARE_IPV4_CIDRS[@]:-}")
    for cidr in "${cf_cidrs[@]}"; do
        local network="${cidr%/*}"
        local prefix="${cidr#*/}"
        # Basic prefix matching check
        local net_prefix
        case "$prefix" in
            20)
                # Matches first two octets approximately or prefix
                net_prefix="$(echo "$network" | cut -d. -f1-2)"
                ;;
            18|17|16|15|14|13)
                net_prefix="$(echo "$network" | cut -d. -f1-2)"
                ;;
            22|24)
                net_prefix="$(echo "$network" | cut -d. -f1-3)"
                ;;
            *)
                net_prefix="$(echo "$network" | cut -d. -f1-2)"
                ;;
        esac

        if [[ "$ip" == "$net_prefix"* ]]; then
            return 0
        fi
    done

    return 1
}

# 5. DNS Pre-flight Verification with Polling / Retry
domain_verify_dns() {
    local domain="$1"
    local skip_check="${2:-0}"
    local non_interactive="${3:-0}"
    local is_dns_mode="${4:-0}"

    if [ "$is_dns_mode" = "1" ] || [ "$is_dns_mode" = "true" ] || [ "$is_dns_mode" = "--dns-cf" ] || [ "$is_dns_mode" = "dns_cf" ]; then
        ui_info "已启用 Cloudflare DNS-01 验证模式: 跳过公网 IP 匹配与 80 端口占用检查 (支持内网/无公网IP/FRP穿透/非80端口环境)。"
        return 0
    fi

    if [ "$skip_check" = "1" ] || [ "$skip_check" = "true" ] || [ "$skip_check" = "--skip-dns-check" ]; then
        ui_warn "已通过参数显式跳过 DNS 解析前置预检。"
        return 0
    fi

    ui_info "正在预检目标域名 DNS 解析与公网 IP 对齐状态: ${domain}..."
    local server_ip
    server_ip="$(domain_get_public_ipv4)"
    ui_info "检测到当前服务器公网 IP: ${server_ip}"

    local max_retries="${DNS_MAX_RETRIES:-12}"
    local retry_interval="${DNS_RETRY_INTERVAL:-5}"
    local attempt=1

    while [ "$attempt" -le "$max_retries" ]; do
        local resolved_ips=""
        resolved_ips="$(domain_resolve_ipv4 "$domain" || true)"

        if [ -n "$resolved_ips" ]; then
            local matched=0
            while read -r r_ip; do
                [ -z "$r_ip" ] && continue
                if [ "$r_ip" = "$server_ip" ]; then
                    matched=1
                    break
                fi
                if domain_is_cloudflare_ip "$r_ip"; then
                    ui_warn "域名 ${domain} 解析到了 Cloudflare CDN 节点 ($r_ip) [小黄云开启]。"
                    ui_info "提示: Let's Encrypt HTTP-01 验证仍可通过，但请确保 Cloudflare SSL 模式设置为 'Full' 或 'Full (strict)'。"
                    return 0
                fi
            done <<< "$resolved_ips"

            if [ "$matched" -eq 1 ]; then
                ui_success "DNS 预检成功: ${domain} 正确解析至本机公网 IP ($server_ip)。"
                return 0
            fi
        fi

        ui_warn "第 ${attempt}/${max_retries} 次检测: 域名 ${domain} 解析结果 [${resolved_ips:-无解析记录}] 与本机 IP [${server_ip}] 不匹配。"

        if [ "$non_interactive" = "1" ] || [ ! -t 0 ]; then
            if [ "$attempt" -lt "$max_retries" ]; then
                ui_info "将在 ${retry_interval} 秒后重试..."
                sleep "$retry_interval"
                attempt=$((attempt + 1))
                continue
            else
                ui_error "DNS 预检超时失败: 域名 ${domain} 未指向本机 IP (${server_ip})。"
                ui_info "若确定要跳过，请添加参数 '--skip-dns-check'。"
                return 3
            fi
        fi

        # Interactive Mode Choice
        echo ""
        local choice
        choice="$(ui_select "DNS 尚未生效或未指向本机，请选择后续操作:" \
            "等待并重新检测 (5秒后重试)" \
            "强行跳过预检 (若解析错误可能导致 Let's Encrypt 限流)" \
            "取消本次操作")"

        case "$choice" in
            1)
                ui_info "正在等待 DNS 生效..."
                sleep "$retry_interval"
                attempt=$((attempt + 1))
                ;;
            2)
                ui_warn "用户选择强行跳过 DNS 预检。"
                return 0
                ;;
            3|*)
                ui_error "用户取消操作。"
                return 3
                ;;
        esac
    done

    ui_error "DNS 预检失败。"
    return 3
}

# 6. Check Port 80 Conflict & Process Details
# Returns 0 if 80 is free or owned by Nginx, 1 if 80 is occupied by a foreign process
domain_check_port_80() {
    local occupied=0
    local pid=""
    local proc_name=""

    # Strategy 1: ss -tulpn
    if command -v ss >/dev/null 2>&1; then
        local line
        line="$(ss -tulpn 2>/dev/null | grep -E ':80[[:space:]]+' | head -n 1 || true)"
        if [ -n "$line" ]; then
            occupied=1
            # Extract pid and name e.g. users:(("apache2",pid=1234,fd=4))
            if [[ "$line" =~ users:\(\(\"([^\"]+)\",pid=([0-9]+) ]]; then
                proc_name="${BASH_REMATCH[1]}"
                pid="${BASH_REMATCH[2]}"
            elif [[ "$line" =~ pid=([0-9]+) ]]; then
                pid="${BASH_REMATCH[1]}"
                proc_name="$(ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")"
            fi
        fi
    fi

    # Strategy 2: lsof -i :80
    if [ "$occupied" -eq 0 ] && command -v lsof >/dev/null 2>&1; then
        local line
        line="$(lsof -i :80 -sTCP:LISTEN -n -P 2>/dev/null | tail -n +2 | head -n 1 || true)"
        if [ -n "$line" ]; then
            occupied=1
            proc_name="$(echo "$line" | awk '{print $1}')"
            pid="$(echo "$line" | awk '{print $2}')"
        fi
    fi

    # Strategy 3: netstat -tlpn
    if [ "$occupied" -eq 0 ] && command -v netstat >/dev/null 2>&1; then
        local line
        line="$(netstat -tlpn 2>/dev/null | grep -E ':80[[:space:]]+' | head -n 1 || true)"
        if [ -n "$line" ]; then
            occupied=1
            local prog
            prog="$(echo "$line" | awk '{print $NF}')" # e.g. 1234/apache2
            pid="${prog%/*}"
            proc_name="${prog#*/}"
        fi
    fi

    if [ "$occupied" -eq 0 ]; then
        ui_debug "80 端口当前空闲可用。"
        return 0
    fi

    # Check if the process is nginx
    if [[ "$proc_name" == *"nginx"* ]]; then
        ui_debug "80 端口当前由 Nginx 正常监听。"
        return 0
    fi

    echo "OCCUPIED_PID=${pid}"
    echo "OCCUPIED_NAME=${proc_name}"
    ui_warn "检测到 80 端口被非 Nginx 进程占用: [PID: ${pid:-未知}, 程序名: ${proc_name:-未知}]"
    return 1
}

# 7. Self-Healing Port 80 Conflict
domain_heal_port_80() {
    local pid="$1"
    local proc_name="$2"

    if [ -z "$pid" ] && [ -z "$proc_name" ]; then
        ui_info "未指定冲突进程，无需处理。"
        return 0
    fi

    ui_info "正在尝试解决 80 端口占用冲突 (进程: ${proc_name}, PID: ${pid})..."

    # If it's a known service, try stopping via systemctl
    if [ -n "$proc_name" ] && [ "${EUID:-$(id -u)}" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
        if systemctl --no-ask-password is-active --quiet "$proc_name" 2>/dev/null; then
            if ui_confirm "检测到系统服务 '${proc_name}' 正在占用 80 端口，是否尝试通过 systemctl 停止它?" "Y"; then
                ui_info "尝试停止冲突服务: systemctl stop ${proc_name}..."
                systemctl --no-ask-password stop "$proc_name" 2>/dev/null || true
            fi
        fi
    fi

    # If still running and PID is valid, send SIGTERM
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        ui_info "发送 SIGTERM 终止进程 PID ${pid}..."
        kill -15 "$pid" 2>/dev/null || true
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            ui_warn "进程仍在运行，发送 SIGKILL 强制释放..."
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi

    sleep 0.5
    # Verify port is now free
    if domain_check_port_80 >/dev/null 2>&1; then
        ui_success "80 端口冲突已成功自愈并释放！"
        return 0
    else
        ui_error "未能成功释放 80 端口，请手动排查占用进程。"
        return 1
    fi
}
