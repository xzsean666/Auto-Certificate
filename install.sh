#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - install.sh
# System Installation & Uninstallation Script
# ==============================================================================

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${DESTDIR:-}${PREFIX}/bin"
SHARE_DIR="${DESTDIR:-}${PREFIX}/share/ngx-cert-manager"
CONF_DIR="${DESTDIR:-}/etc/ngx-cert-manager"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
C_GREEN="\033[0;32m"
C_RED="\033[0;31m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;34m"
C_BOLD="\033[1m"
C_RESET="\033[0m"

log_info() { echo -e "${C_BLUE}ℹ [INFO]${C_RESET} $*"; }
log_success() { echo -e "${C_GREEN}✔ [OK]${C_RESET}   $*"; }
log_warn() { echo -e "${C_YELLOW}⚠ [WARN]${C_RESET} $*"; }
log_error() { echo -e "${C_RED}✖ [ERROR]${C_RESET} $*" >&2; }

# Check root if installing to system directory
check_privileges() {
    if [ -z "${DESTDIR:-}" ] && [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_error "系统级安装需要管理员权限，请使用 'sudo ./install.sh' 运行。"
        exit 1
    fi
}

do_install() {
    check_privileges
    log_info "开始安装 ngx-cert-manager 到系统目录 (${PREFIX})..."

    # 1. Create directories
    mkdir -p "$BIN_DIR" "$SHARE_DIR" "$CONF_DIR"

    # 2. Copy libraries & templates
    log_info "正在复制核心库与模板文件至: $SHARE_DIR"
    cp -r "$SCRIPT_DIR/lib" "$SHARE_DIR/"
    cp -r "$SCRIPT_DIR/templates" "$SHARE_DIR/"
    cp "$SCRIPT_DIR/config.env" "$SHARE_DIR/"

    # 3. Copy global configuration
    if [ ! -f "$CONF_DIR/config.env" ]; then
        log_info "初始化全局配置文件: $CONF_DIR/config.env"
        cp "$SCRIPT_DIR/config.env" "$CONF_DIR/config.env"
    else
        log_info "保留已有全局配置文件: $CONF_DIR/config.env"
    fi

    # 4. Install binary and symlink
    log_info "正在安装可执行文件至: $BIN_DIR/ngx-cert-manager"
    install -m 755 "$SCRIPT_DIR/ngx-cert-manager" "$BIN_DIR/ngx-cert-manager"
    ln -sf "ngx-cert-manager" "$BIN_DIR/ngx-cert"

    log_success "🎉 ngx-cert-manager 安装完成！"
    echo ""
    echo -e "${C_BOLD}现在可以在终端任意位置直接使用：${C_RESET}"
    echo "  - ngx-cert-manager (交互式大盘)"
    echo "  - ngx-cert site list (CLI 别名)"
    echo "  - ngx-cert-manager --help (查看帮助)"
}

do_uninstall() {
    check_privileges
    log_info "正在从系统中卸载 ngx-cert-manager..."

    rm -f "$BIN_DIR/ngx-cert-manager" "$BIN_DIR/ngx-cert"
    rm -rf "$SHARE_DIR"

    log_success "已清理二进制与共享资源。"
    if [ -d "$CONF_DIR" ]; then
        echo -ne "${C_YELLOW}? 是否同时删除全局配置文件目录 ($CONF_DIR)? [y/N]: ${C_RESET}"
        read -r ans || true
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            rm -rf "$CONF_DIR"
            log_success "已清理配置文件目录: $CONF_DIR"
        else
            log_info "已保留配置文件目录: $CONF_DIR"
        fi
    fi

    log_success "ngx-cert-manager 卸载完成。"
}

# Entrypoint
ACTION="${1:-install}"
case "$ACTION" in
    install|--install)
        do_install
        ;;
    uninstall|--uninstall|remove)
        do_uninstall
        ;;
    *)
        echo "使用方法: sudo ./install.sh [install|uninstall]"
        exit 1
        ;;
esac
