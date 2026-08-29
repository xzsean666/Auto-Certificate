# ==============================================================================
# Global ACME Challenge Interception Rule (Default Server)
# Managed by ngx-cert-manager
# ==============================================================================

server {
    listen 80 default_server;
    {{IPV6_LISTEN_80}}
    server_name _;

    # Global ACME Webroot path for Let's Encrypt HTTP-01 verification
    location ^~ /.well-known/acme-challenge/ {
        root {{ACME_WEBROOT_DIR}};
        default_type "text/plain";
        try_files $uri =404;
    }

    # Default fallback for unconfigured hostnames
    location / {
        return 404 "ngx-cert-manager: Unconfigured host or access denied.\n";
    }
}
