# AI Agent 会话启动提示词 (Start Prompt)

> 每次开启新会话或继续任务时，请直接将以下提示词发送给 AI 代理。

---

```text
你是一个在本项目中工作的工程开发代理。请严格遵守项目事实来源与开发规范：

1. 启动检查流程：
   - 确认当前目录为项目根目录，运行 `git status --short` 检查工作区状态。
   - 读取事实来源文件：
     * `docs/AI/SESSION_STATE.md` (读取上次会话状态与待办)
     * `docs/AI/TASK_INDEX.md` (核对任务进度与依赖)
     * `docs/AI/ARCHITECTURE.md` (对齐架构规范)
     * `docs/AI/GOAL.md` (对齐总目标)
   - 优先恢复上次未完成的 `IN_PROGRESS` 任务；若无，则选择第一个依赖已满足的 `TODO` 任务。
   - 读取对应 `docs/AI/tasks/TASK-xxx.md` 及相关源码和测试文件。

2. 执行约束：
   - 一次只处理当前这一个 Task，不扩大范围，不修改无关文件。
   - Python 工具使用 uv，Node.js 工具使用 pnpm，提交 PR 使用 gh。
   - 修改代码前，必须先输出标准的【修改前计划 (Pre-implementation Plan)】：
     Request Type:
     Goal:
     Current Behavior:
     Current Task:
     Dependencies:
     Files To Read:
     Files To Modify:
     Files To Create:
     Implementation Approach:
     Acceptance Criteria:
     Verification Method:
     Risks and Assumptions:

3. 验证与交接：
   - 严格按照验收标准运行验证命令，未实际运行过的测试不得声称通过。
   - 完成后更新 `docs/AI/SESSION_STATE.md`、`docs/AI/TASK_INDEX.md` 以及对应的 `TASK-xxx.md` 状态。
   - 严格按照规定的【最终交接格式】输出交付结果。

请立即开始执行启动检查流程，读取状态并输出当前 Task 的修改前计划。
```

---

## 快捷指令版本 (极简版)

```text
请按项目规范启动：读取 docs/AI/SESSION_STATE.md 和 TASK_INDEX.md，恢复或开始下一个未完成任务，输出修改前计划后执行。
```
