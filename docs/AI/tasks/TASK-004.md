# TASK-004: Nginx 生命周期管理与全局 Webroot 穿透

## Objective
实现 `lib/nginx.sh` 与 `templates/acme-global.conf.tpl`，提供 Nginx 安装与检测、运行状态监控、零停机平滑重载、配置语法自检以及全局 ACME 穿透规则注入。

## Scope
- Nginx 安装状态检测与一键安装适配（Debian/Ubuntu/RHEL/CentOS/Rocky/Alma/Alpine）
- 注入全局 ACME Webroot 规则（`/etc/nginx/conf.d/000-default-acme.conf`）
- 注入全局 WebSocket Map（`/etc/nginx/conf.d/000-websocket-map.conf`）
- Nginx 启动、停止、重启、平滑重载 (`nginx_reload`) 与语法检查 (`nginx_test`)

## Allowed Files
- `lib/nginx.sh`
- `templates/acme-global.conf.tpl`
- `templates/websocket-map.conf.tpl`
- `tests/test_nginx.sh`

## Dependencies
- TASK-003

## Inputs and Outputs
- **Inputs**: Nginx 配置文件与服务控制命令
- **Outputs**: 穿透配置、WebSocket Map 与服务控制接口

## Acceptance Criteria
- 自动创建 `/var/www/certbot` 并赋予适当权限
- 语法检测失败时绝对不触发 reload
- 支持无 IPv6 时的自适应模板渲染

## Verification Commands
- `bash tests/test_nginx.sh`

## Risks and Assumptions
- 已有系统可能存在旧版 Nginx 配置冲突，需先探测 `nginx.conf` include 状态

## Status
DONE
