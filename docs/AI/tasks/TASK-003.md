# TASK-003: 系统环境感知、多发行版适配与 IPv6 探测

## Objective
实现 `lib/env.sh`，负责底层系统识别（Debian/Ubuntu/RHEL/CentOS/Rocky/Alma/Alpine/Arch）、Root 权限检查、包管理器抽象与内核 IPv6 双栈支持动态探测。

## Scope
- 检测 `/etc/os-release` 确定操作系统类型与包管理器
- 提供通用包管理接口：`pkg_update`, `pkg_install`, `pkg_is_installed`
- 动态探测 IPv6 绑定能力 (`env_check_ipv6`) 并设置 `HAS_IPV6=true/false`
- 探测 Init 系统 (`systemd` vs `cron/openrc`) 并设置 `INIT_SYSTEM`

## Allowed Files
- `lib/env.sh`
- `tests/test_env.sh`

## Dependencies
- TASK-002

## Inputs and Outputs
- **Inputs**: 系统环境文件 (`/etc/os-release`, `/proc/net/if_inet6`, `/run/systemd/system`)
- **Outputs**: 环境全局变量与统一包管理工具函数

## Acceptance Criteria
- 在无 IPv6 的宿主或容器上能准确返回 `HAS_IPV6=false`
- 能够准确识别常见 Linux 发行版及包管理器
- 具备完整的测试用例

## Verification Commands
- `bash tests/test_env.sh`

## Risks and Assumptions
- 某些容器环境精简了 `/etc/os-release`，需提供容错兜底

## Status
DONE
