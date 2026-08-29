# ==============================================================================
# Global WebSocket Connection Upgrade Mapping
# Managed by ngx-cert-manager
# ==============================================================================

map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
