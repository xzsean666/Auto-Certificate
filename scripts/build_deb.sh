#!/usr/bin/env bash
# ==============================================================================
# ngx-cert-manager - scripts/build_deb.sh
# Debian / Ubuntu .deb Package Builder for APT Distribution
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$PROJECT_ROOT/config.env"

PKG_NAME="ngx-cert-manager"
PKG_VERSION="${NGX_CERT_MANAGER_VERSION:-1.0.0}"
PKG_ARCH="all"
PKG_FULL_NAME="${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}"

DIST_DIR="$PROJECT_ROOT/dist"
BUILD_ROOT="$DIST_DIR/$PKG_FULL_NAME"

echo "[*] 开始构建 Debian/Ubuntu 安装包: ${PKG_FULL_NAME}.deb"

# Clean build directory
rm -rf "$BUILD_ROOT" "$DIST_DIR/${PKG_FULL_NAME}.deb"
mkdir -p "$BUILD_ROOT/DEBIAN"
mkdir -p "$BUILD_ROOT/usr/bin"
mkdir -p "$BUILD_ROOT/usr/share/ngx-cert-manager/lib"
mkdir -p "$BUILD_ROOT/usr/share/ngx-cert-manager/templates"
mkdir -p "$BUILD_ROOT/etc/ngx-cert-manager"

# 1. Create DEBIAN/control
cat << EOF > "$BUILD_ROOT/DEBIAN/control"
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Section: net
Priority: optional
Architecture: ${PKG_ARCH}
Depends: bash (>= 4.0), curl, openssl, nginx | nginx-full | nginx-light | nginx-core
Recommends: certbot, python3-certbot-nginx
Maintainer: ngx-cert-manager Contributors <admin@example.com>
Description: Nginx & Let's Encrypt automated operations and reverse proxy management suite
 ngx-cert-manager provides zero-downtime Let's Encrypt certificate issuance,
 automated renewal daemon, dynamic IPv6 crash-prevention, DNS pre-flight checks,
 production reverse proxy generation with atomic rollback, and remote SSH execution.
EOF

# 2. Create DEBIAN/conffiles
cat << EOF > "$BUILD_ROOT/DEBIAN/conffiles"
/etc/ngx-cert-manager/config.env
EOF

# 3. Create DEBIAN/postinst & prerm
cat << 'EOF' > "$BUILD_ROOT/DEBIAN/postinst"
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    chmod 755 /usr/bin/ngx-cert-manager 2>/dev/null || true
    ln -sf ngx-cert-manager /usr/bin/ngx-cert 2>/dev/null || true
    echo "========================================================"
    echo "  ngx-cert-manager 安装成功！"
    echo "  直接在终端运行 'ngx-cert-manager' 进入管理大盘"
    echo "  或使用短别名 'ngx-cert site list'"
    echo "========================================================"
fi
exit 0
EOF
chmod 755 "$BUILD_ROOT/DEBIAN/postinst"

cat << 'EOF' > "$BUILD_ROOT/DEBIAN/prerm"
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    rm -f /usr/bin/ngx-cert 2>/dev/null || true
fi
exit 0
EOF
chmod 755 "$BUILD_ROOT/DEBIAN/prerm"

# 4. Copy Application Files
cp "$PROJECT_ROOT/ngx-cert-manager" "$BUILD_ROOT/usr/bin/ngx-cert-manager"
chmod 755 "$BUILD_ROOT/usr/bin/ngx-cert-manager"

# Create symlink in package
(cd "$BUILD_ROOT/usr/bin" && ln -sf ngx-cert-manager ngx-cert)

cp -r "$PROJECT_ROOT/lib/"* "$BUILD_ROOT/usr/share/ngx-cert-manager/lib/"
cp -r "$PROJECT_ROOT/templates/"* "$BUILD_ROOT/usr/share/ngx-cert-manager/templates/"
cp "$PROJECT_ROOT/config.env" "$BUILD_ROOT/usr/share/ngx-cert-manager/config.env"
cp "$PROJECT_ROOT/config.env" "$BUILD_ROOT/etc/ngx-cert-manager/config.env"

# 5. Build .deb package with dpkg-deb or fallback to tar
if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb --build "$BUILD_ROOT" "$DIST_DIR/${PKG_FULL_NAME}.deb"
    echo "[✔] Debian 安装包构建成功: $DIST_DIR/${PKG_FULL_NAME}.deb"
    echo ""
    echo "安装命令:"
    echo "  sudo dpkg -i dist/${PKG_FULL_NAME}.deb"
    echo "  sudo apt-get install -f  # 自动补全依赖"
else
    echo "[!] 系统中未找到 dpkg-deb，已生成标准目录结构: $BUILD_ROOT"
fi
