# Project Goal: ngx-cert-manager (Nginx & Let's Encrypt 一体化运维管理套件)

## 1. 项目定位与愿景
`ngx-cert-manager` 是一个专为 Linux 生产服务器设计的模块化 Shell 运维管理套件。
它提供**统一终端交互界面 (TUI)** 与**自动化命令行参数 (CLI)**，实现 Nginx 安装与维护、ACME/Let's Encrypt 证书自动化签发与守护续期、现代生产级反向代理配置生成、远程 SSH 免安装代理执行的完整闭环。

## 2. 核心价值与目标
1. **零学习成本与防错机制**：通过交互式引导与严格的前置预检（DNS解析校验、公网IP核对、IPv6能力探测、80端口冲突检测），避免 Let's Encrypt 触发频率限制或配置语法错误导致 Nginx 崩溃。
2. **生产级高可用配置**：默认输出 Mozilla SSL Modern/Intermediate 安全配置、HSTS、WebSocket 支持、Real-IP 真实客户端透传、HTTP/2 自适应。
3. **零停机平滑运维**：基于 Webroot 统一穿透路由签发证书，在不重启、不停机的前提下完成证书新增与自动续期。
4. **极简轻量与跨发行版**：纯 Bash 架构，原生适配主流 Linux 发行版（Debian/Ubuntu/RHEL/CentOS/Rocky/Alma/Alpine），支持 Systemd 与 Cron 自动适配。
5. **本地与远程无缝一体**：支持通过 `--ssh user@host` 本地直接控制远端服务器，脚本动态打包传输并在退出时无残留清理。

## 3. 技术栈与工具约定
- **脚本语言**：Bash (严格遵循 `set -eo pipefail` 与模块化分层)
- **ACME 引擎**：Certbot（默认 Webroot 模式，支持 Standalone 回退及未来扩展）
- **Web 服务器**：Nginx (自适应包管理器与已有安装版本)
- **调度守护**：Systemd Timer (主要) / Crontab (备用降级)
- **包管理器与环境规则**：严格遵循用户环境规则（Python 工具使用 `uv`，Node.js 使用 `pnpm`，PR 提交使用 `gh`）

## 4. 交付里程碑规划
- **Milestone 1**: AI 规范文档与完整生产架构设计规范建立
- **Milestone 2**: 核心基础库开发（UI交互、环境探测、配置管理、模板引擎）
- **Milestone 3**: Nginx 生命周期管理与全局 ACME 穿透规则注入
- **Milestone 4**: 域名公网嗅探、DNS 预检与 80 端口冲突自愈
- **Milestone 5**: 证书生命周期管理（Webroot/Standalone/续期/吊销/大盘看板）
- **Milestone 6**: 生产级反向代理配置引擎与原子安全回滚机制
- **Milestone 7**: Systemd / Cron 自动化续期守护与定时任务注入
- **Milestone 8**: 远程 SSH 免安装代理执行引擎与清理机制
- **Milestone 9**: 端到端集成测试、容错边界验证与用户文档完善
