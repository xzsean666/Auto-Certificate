# TASK-001: 项目骨架、默认配置与静态检查规范

## Objective
搭建项目的标准目录骨架，编写全局默认配置文件 `config.env`，并提供代码质量检查规范（Makefile/测试命令）。

## Scope
- 创建目录：`lib/`, `templates/`, `tests/`
- 创建 `config.env`，定义全局路径、默认超时、Let's Encrypt 选项等
- 提供 `Makefile` 包含 `make lint` (shellcheck) 与 `make test`

## Allowed Files
- `config.env`
- `Makefile`
- `.editorconfig`
- `.gitignore`

## Dependencies
- None

## Inputs and Outputs
- **Inputs**: 架构设计文档中的配置规范
- **Outputs**: 标准项目目录、配置文件与检查脚本

## Acceptance Criteria
- `config.env` 包含所有必要全局变量（ACME_WEBROOT, NGINX_CONF_DIR, LOG_FILE, CERTBOT_STAGING 等）
- `make lint` 能够正确执行 shellcheck 检查（若系统中存在）
- 项目目录清晰整洁

## Verification Commands
- `test -f config.env && source config.env`
- `make lint` (or dry-run lint)

## Risks and Assumptions
- 假设宿主机支持 Bash 4.0+

## Status
DONE
