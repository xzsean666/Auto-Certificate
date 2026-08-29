# TASK-011: 端到端集成测试、容错边界验证与使用文档

## Objective
完善全套端到端集成测试套件，验证异常边界（如无 IPv6、语法错误回滚、端口冲突、无交互 CLI），并输出完整的项目使用说明文档 `README.md` 与 `CONTRIBUTING.md`。

## Scope
- 端到端综合测试脚本 `tests/run_all.sh`
- 覆盖异常与防御机制场景验证
- 编写生产就绪的 `README.md`（包含架构图、TUI 截图示意、CLI 使用范例、系统要求等）
- 编写 `CONTRIBUTING.md` 与开源规范

## Allowed Files
- `tests/run_all.sh`
- `README.md`
- `CONTRIBUTING.md`

## Dependencies
- TASK-010

## Inputs and Outputs
- **Inputs**: 整体项目代码
- **Outputs**: 测试报告与用户文档

## Acceptance Criteria
- 所有自动化测试用例通过
- README 包含快速入门、详细参数列表及高级技巧

## Verification Commands
- `bash tests/run_all.sh`

## Risks and Assumptions
- 部分测试需要 mock 环境支持

## Status
DONE
