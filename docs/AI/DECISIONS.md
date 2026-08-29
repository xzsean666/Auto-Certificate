# Architecture Decision Records (ADR) - ngx-cert-manager

## ADR-001: 采用模块化 Bash 架构与单入口 (main.sh)
- **状态**: Accepted
- **背景**: 用户需要轻量、无复杂依赖的服务器运维工具。如果采用 Python / Node.js 等高层语言，在不同裸机服务器或极简 VPS 上安装依赖包常面临环境不一致、Python 版本过旧或缺失 pip/uv 的问题。
- **决策**: 采用纯 POSIX/Bash 模块化设计，主入口 `main.sh` 分发，所有核心逻辑按职责拆入 `lib/*.sh`。
- **影响**: 具备零依赖直接运行能力，跨各种 Linux 发行版极易移植，同时保持代码可测试性。

## ADR-002: 证书签发以 Webroot 模式为主，Standalone 为辅
- **状态**: Accepted
- **背景**: 很多传统脚本在签发证书时停掉 Nginx (`nginx -s stop` -> `certbot --standalone` -> `nginx -s start`)，导致已有线上站点短暂不可用。
- **决策**: 在 Nginx 中预置 `/etc/nginx/conf.d/000-default-acme.conf` 全局捕获 `/.well-known/acme-challenge/` 到 `/var/www/certbot`，所有证书签发与续期均基于 Webroot 进行。Standalone 模式仅作为 Nginx 未安装/未启动时的初次兜底。
- **影响**: 实现真正意义上的零停机、零中断全自动证书签发与平滑续期。

## ADR-003: IPv6 运行时动态探测与模板按需渲染
- **状态**: Accepted
- **背景**: 部分 VPS 厂商或 Docker 容器在内核中完全关闭了 IPv6，如果在 Nginx 配置文件中硬编码 `listen [::]:80;` 或 `listen [::]:443 ssl;`，会导致 Nginx 启动直接报致命错误 `[emerg] socket() [::]:80 failed (97: Address family not supported by protocol)` 导致全站宕机。
- **决策**: 在 `lib/env.sh` 中对系统 IPv6 绑定能力进行实时探测；渲染 Nginx 站点配置模板时，仅在系统明确支持 IPv6 时才输出 `[::]` 监听指令。
- **影响**: 彻底根除因宿主机 IPv6 支持差异引起的 Nginx 语法崩溃。

## ADR-004: 配置更新事务机制与原子回滚
- **状态**: Accepted
- **背景**: 用户手工修改 Nginx 或脚本写入错误反代配置后，直接 reload 会导致线上服务异常。
- **决策**: 实施「临时文件 `.tmp` -> 历史备份 `.backup/<timestamp>/` -> `nginx -t` 语法自检 -> 成功则原子替换并 reload，失败则立即从备份还原」流程。
- **影响**: 保证任何错误配置绝不污染现有运行环境，保障生产稳定性。

## ADR-005: 续期调度优先 Systemd Timer，降级 Crontab
- **状态**: Accepted
- **背景**: 现代 Linux 发行版推荐使用 Systemd Timer 替代旧式 Cron，且 Timer 支持 `RandomizedDelaySec` 防拥塞抖动，但在 Docker / Alpine / OpenRC 环境下 Systemd 不可用。
- **决策**: 优先检测并注入 `/etc/systemd/system/certbot-renew.timer`；若无 Systemd 环境，自动降级注入标准 `/etc/cron.d/certbot-renew` 或 Crontab。
- **影响**: 兼顾现代化 Linux 发行版的可靠调度与容器/Alpine 极简环境的兼容性。

## ADR-006: 远程 SSH 免安装代理执行与退出清理
- **状态**: Accepted
- **背景**: 管理多台服务器时，若每台都需要手动克隆仓库，运维成本高且留下碎片文件。
- **决策**: 本地执行 `main.sh --ssh root@host` 时，本地动态打包，通过 SSH 传输至远端 `/tmp/`，在远端分配伪终端执行交互，并在退出时通过 `trap` 自动清理临时文件。
- **影响**: 达到 Ansible 般的免 Agent / 即用即走体验，同时保留直观的 TUI 终端界面。
