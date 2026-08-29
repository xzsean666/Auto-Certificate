# TASK-010: 统一入口主路由、CLI 解析与 TUI 整合

## Objective
实现根目录主入口 `main.sh`，整合各模块，提供美观的 ANSI TUI 状态大盘交互式主菜单与全功能的 CLI 自动化命令行参数路由。

## Scope
- CLI 命令行参数解析（`site`, `cert`, `nginx`, `systemd`, `diagnose`, `remote` 等子命令）
- TUI 状态大盘（整合 Nginx 运行状态、证书到期大盘、Timer 状态）
- 向导式交互流程（一键新建站点：域名输入 -> DNS预检 -> 申请证书 -> 配置反代 -> 生效测试）
- 帮助信息与版本展示 (`--help`, `--version`)

## Allowed Files
- `main.sh`
- `tests/test_main_cli.sh`

## Dependencies
- TASK-001 ~ TASK-009

## Inputs and Outputs
- **Inputs**: 命令行参数或键盘交互指令
- **Outputs**: 对应模块调度与结果呈现

## Acceptance Criteria
- 无参数运行时进入交互 TUI 大盘
- 携带合法子命令时直接进入 CLI 非交互模式
- 帮助文档详实，参数解析健壮

## Verification Commands
- `bash main.sh --help`
- `bash tests/test_main_cli.sh`

## Risks and Assumptions
- 终端大小可能过小，需提供自适应换行或友好提示

## Status
DONE
