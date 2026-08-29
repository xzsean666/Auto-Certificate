# ==============================================================================
# Managed by ngx-cert-manager: {{DOMAIN}} (HTTP-Only / Cloudflare Proxy)
# Created at: {{CREATED_AT}}
# Upstream Target: {{UPSTREAM_TARGET}}
# ==============================================================================

server {
    listen 80;
    {{IPV6_LISTEN_80}}
    server_name {{DOMAIN}};

    # 保留 ACME Webroot 穿透验证 (便于随时无缝升级至 SSL)
    location ^~ /.well-known/acme-challenge/ {
        root {{ACME_WEBROOT_DIR}};
        default_type "text/plain";
        try_files $uri =404;
    }

    # 客户端上传限制与超时调节
    client_max_body_size {{CLIENT_MAX_BODY_SIZE}};
    client_body_buffer_size 128k;

    # 访问与错误日志
    access_log /var/log/nginx/{{DOMAIN}}_access.log combined;
    error_log /var/log/nginx/{{DOMAIN}}_error.log warn;

    # 核心反向代理路由
    location / {
        proxy_pass {{UPSTREAM_TARGET}};
        proxy_http_version 1.1;

        # 真实客户端 IP 头部透传 (含 Cloudflare 真实 IP)
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header CF-Connecting-IP $http_cf_connecting_ip;

        # WebSocket 协议升级支持
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        # 超时配置
        proxy_connect_timeout {{PROXY_CONNECT_TIMEOUT}};
        proxy_send_timeout {{PROXY_SEND_TIMEOUT}};
        proxy_read_timeout {{PROXY_READ_TIMEOUT}};

        # 缓冲优化
        proxy_buffering on;
        proxy_buffer_size 8k;
        proxy_buffers 8 64k;
    }
}
