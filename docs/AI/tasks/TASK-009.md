# TASK-009: 远程 SSH 无痕代理执行引擎

## Objective
实现 `lib/remote.sh`，实现通过 `--ssh user@host` 参数将本地运维套件动态打包、透传至远端并在伪终端中执行交互，会话断开后无痕自动销毁。

## Scope
- 动态打包本地脚本库至 `/tmp/ngx-cert-manager-<hash>.tar.gz`
- 建立 SSH 会话传输并在远端解压
- 分配伪终端 `ssh -t` 运行主交互菜单或 CLI 子命令
- 注入 `trap` 信号保证远端与本地临时文件被百分之百清理

## Allowed Files
- `lib/remote.sh`
- `tests/test_remote.sh`

## Dependencies
- TASK-001

## Inputs and Outputs
- **Inputs**: SSH 目标格式 (`user@host` 或包含 `-p port`)，子命令参数
- **Outputs**: 远程终端会话透传及无痕清理

## Acceptance Criteria
- 支持免密公钥与交互式密码输入
- 进程异常退出时，远端临时目录被安全删除
- 包含打包与解压逻辑的单元测试

## Verification Commands
- `bash tests/test_remote.sh`

## Risks and Assumptions
- 远端主机需安装基本的 `tar`, `gzip` 工具

## Status
DONE
