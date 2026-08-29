# TASK-008: Systemd Timer 与 Cron 自动化续期守护

## Objective
实现 `lib/systemd.sh` 及相关服务与定时器模板，提供 Systemd Timer (带随机抖动) 自动注入与状态查看，并在非 Systemd 环境下自动降级适配 Crontab。

## Scope
- 模板实现：`templates/certbot-renew.service.tpl`, `templates/certbot-renew.timer.tpl`
- 自动注册并启用 Systemd Timer：`systemd_setup_timer`
- 查看续期定时任务运行状态与日志：`systemd_status_timer`, `systemd_view_logs`
- 触发单次测试运行：`systemd_trigger_now`
- Cron 自动降级与清理：`cron_setup_renew`

## Allowed Files
- `lib/systemd.sh`
- `templates/certbot-renew.service.tpl`
- `templates/certbot-renew.timer.tpl`
- `tests/test_systemd.sh`

## Dependencies
- TASK-006

## Inputs and Outputs
- **Inputs**: Webroot 路径与 Nginx 重载命令
- **Outputs**: 系统守护任务单元及生效状态

## Acceptance Criteria
- Systemd Timer 启用 `RandomizedDelaySec=3600`，避免请求风暴
- 支持测试触发与日志格式化输出
- 自动适配 Systemd 与非 Systemd 环境

## Verification Commands
- `bash tests/test_systemd.sh`

## Risks and Assumptions
- 权限不足时无法操作 `/etc/systemd/system/`，需确保 root 权限

## Status
DONE
