[Unit]
Description=Daily 12-hour Timer for Certbot Renewal
ConditionPathExists={{SYSTEMD_SYSTEM_DIR}}/{{CERTBOT_RENEW_SERVICE_NAME}}

[Timer]
OnCalendar=*-*-* 03,15:30:00
RandomizedDelaySec=3600
Persistent=true

[Install]
WantedBy=timers.target
