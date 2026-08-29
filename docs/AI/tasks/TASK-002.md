# TASK-002: 终端 UI 渲染引擎与分级日志系统

## Objective
实现 `lib/ui.sh`，提供一致的 ANSI 终端彩色输出、标题横幅、加载动画、格式化表格、交互确认框及审计日志功能。

## Scope
- 实现 `ui_banner`, `ui_section`, `ui_info`, `ui_success`, `ui_warn`, `ui_error`
- 实现交互提示函数：`ui_prompt`, `ui_confirm`, `ui_select`
- 实现日志记录函数 `ui_log`，写入 `/var/log/ngx-cert-manager.log`

## Allowed Files
- `lib/ui.sh`
- `tests/test_ui.sh`

## Dependencies
- TASK-001

## Inputs and Outputs
- **Inputs**: 终端控制符与用户输入
- **Outputs**: 结构化终端输出与日志流

## Acceptance Criteria
- 支持彩色终端与非交互终端自动去除 ANSI 颜色
- 日志函数自动附带 ISO 8601 时间戳
- 具备完整的单元测试覆盖

## Verification Commands
- `bash tests/test_ui.sh`

## Risks and Assumptions
- 终端必须兼容 ANSI 基础色彩规范

## Status
DONE
