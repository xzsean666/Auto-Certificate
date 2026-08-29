[Unit]
Description=Certbot Automated Webroot Renewal Service
After=network-online.target nginx.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart={{CERTBOT_BIN}} renew --webroot -w {{ACME_WEBROOT_DIR}} --post-hook "{{POST_HOOK_CMD}}" --quiet
