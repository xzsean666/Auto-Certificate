# TASK-007: 现代反向代理配置引擎与原子安全回滚

## Objective
实现 `lib/proxy.sh` 与 `templates/proxy-ssl.conf.tpl`，提供现代安全反向代理站点的新增、查看、修改、禁用、删除功能，具备 WebSocket 支持、Real-IP 透传、Nginx 版本自适应 HTTP/2、快照备份与语法失败自动回滚机制。

## Scope
- 模板渲染引擎：支持替换 Domain, Upstream, IPv6 监听, SSL 路径, HTTP/2 指令, WS 支持, HSTS, Body Size
- 事务性写入与回滚：创建临时文件 -> `nginx -t` 测试 -> 成功替换并平滑重载 / 失败还原备份
- 站点管理功能：`proxy_add_site`, `proxy_list_sites`, `proxy_get_site`, `proxy_delete_site`

## Allowed Files
- `lib/proxy.sh`
- `templates/proxy-ssl.conf.tpl`
- `tests/test_proxy.sh`

## Dependencies
- TASK-004
- TASK-006

## Inputs and Outputs
- **Inputs**: 站点域名、Upstream 目标、WS 开关、SSL 证书路径等
- **Outputs**: `/etc/nginx/conf.d/<domain>.conf` 及平滑生效状态

## Acceptance Criteria
- 生成配置符合 Mozilla Modern/Intermediate 安全规范
- 若配置语法错误，必须自动回滚原配置并保留错误日志，线上已有站点零中断
- 覆盖 HTTP、HTTPS、Unix Socket、WebSocket 各类 upstream 场景

## Verification Commands
- `bash tests/test_proxy.sh`

## Risks and Assumptions
- 假设 Nginx 主配置正确包含了 `conf.d/*.conf`

## Status
DONE
