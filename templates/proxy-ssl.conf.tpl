# ==============================================================================
# Managed by ngx-cert-manager: {{DOMAIN}}
# Created at: {{CREATED_AT}}
# Upstream Target: {{UPSTREAM_TARGET}}
# ==============================================================================

# HTTP -> HTTPS 强制 301 重定向 (保留全局 ACME 验证回落)
server {
    listen 80;
    {{IPV6_LISTEN_80}}
    server_name {{DOMAIN}};

    location ^~ /.well-known/acme-challenge/ {
        root {{ACME_WEBROOT_DIR}};
        default_type "text/plain";
        try_files $uri =404;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS 核心业务反向代理
server {
    {{SSL_LISTEN_443}}
    {{IPV6_LISTEN_443}}
    {{HTTP2_DIRECTIVE}}
    server_name {{DOMAIN}};

    # SSL 证书与密钥文件
    ssl_certificate {{SSL_CERT_PATH}};
    ssl_certificate_key {{SSL_KEY_PATH}};

    # 现代安全协议与高强度密码套件 (Mozilla Intermediate)
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # SSL 会话优化与复用
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # 安全头部响应 (Security Headers)
    {{HSTS_HEADER}}
    add_header X-Content-Type-Options nosniff always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    # 客户端上传限制与超时调节
    client_max_body_size {{CLIENT_MAX_BODY_SIZE}};
    client_body_buffer_size 128k;

    # 访问与错误日志
    access_log /var/log/nginx/{{DOMAIN}}_access.log combined;
    error_log /var/log/nginx/{{DOMAIN}}_error.log warn;

    # 反向代理主要路由
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
