# 任务索引大盘 (TASK_INDEX.md)

## 状态说明
- `TODO`: 尚未开始
- `IN_PROGRESS`: 当前正在执行
- `REVIEW`: 代码已完成，等待验证或审查
- `DONE`: 验收标准全部满足，验证已通过，文档已更新
- `BLOCKED`: 受阻于外部条件

---

## 任务列表

| 任务编号 | 任务名称 | 责任模块 | 状态 | 依赖项 | 预计工时 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **[TASK-001](tasks/TASK-001.md)** | 项目骨架、默认配置与静态检查规范 | `config.env`, `Makefile` | DONE | 无 | 30m |
| **[TASK-002](tasks/TASK-002.md)** | 终端 UI 渲染引擎与分级日志系统 | `lib/ui.sh` | DONE | TASK-001 | 45m |
| **[TASK-003](tasks/TASK-003.md)** | 系统环境感知、多发行版适配与 IPv6 探测 | `lib/env.sh` | DONE | TASK-002 | 45m |
| **[TASK-004](tasks/TASK-004.md)** | Nginx 生命周期管理与全局 Webroot 穿透 | `lib/nginx.sh`, `templates/` | DONE | TASK-003 | 60m |
| **[TASK-005](tasks/TASK-005.md)** | 域名公网嗅探、DNS 预检与 80 端口自愈 | `lib/domain.sh` | DONE | TASK-003 | 60m |
| **[TASK-006](tasks/TASK-006.md)** | 证书签发、续期、吊销与状态大盘 | `lib/cert.sh` | DONE | TASK-004, TASK-005 | 60m |
| **[TASK-007](tasks/TASK-007.md)** | 现代反向代理配置引擎与原子安全回滚 | `lib/proxy.sh`, `templates/` | DONE | TASK-004, TASK-006 | 90m |
| **[TASK-008](tasks/TASK-008.md)** | Systemd Timer 与 Cron 自动化续期守护 | `lib/systemd.sh`, `templates/` | DONE | TASK-006 | 45m |
| **[TASK-009](tasks/TASK-009.md)** | 远程 SSH 无痕代理执行引擎 | `lib/remote.sh` | DONE | TASK-001 | 45m |
| **[TASK-010](tasks/TASK-010.md)** | 统一入口主路由、CLI 解析与 TUI 整合 | `main.sh` | DONE | TASK-001 ~ TASK-009 | 60m |
| **[TASK-011](tasks/TASK-011.md)** | 端到端集成测试、容错边界验证与使用文档 | `tests/`, `README.md` | DONE | TASK-010 | 60m |
