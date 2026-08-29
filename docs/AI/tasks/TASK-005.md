# TASK-005: 域名公网嗅探、DNS 预检与 80 端口自愈

## Objective
实现 `lib/domain.sh`，提供多源公网 IP 探测、目标域名 DNS A/AAAA 解析校验、Cloudflare CDN 代理识别与 80 端口占用排查及自愈。

## Scope
- 多源公网 IP 探测 (`domain_get_public_ip`)
- DNS 解析验证与交互式轮询 (`domain_verify_dns`)
- 80 端口占用分析与非 Nginx 进程冲突排查 (`domain_check_port_80`)
- Cloudflare CDN 代理识别与警告机制

## Allowed Files
- `lib/domain.sh`
- `tests/test_domain.sh`

## Dependencies
- TASK-003

## Inputs and Outputs
- **Inputs**: 目标域名字符串
- **Outputs**: 解析 IP、匹配结果、端口占用状态

## Acceptance Criteria
- 当域名解析与公网 IP 不匹配时，提供清晰的报错与交互轮询选项
- 80 端口被冲突占用时，准确定位进程 PID 与进程名
- 单元测试覆盖 DNS 模拟返回与端口冲突分支

## Verification Commands
- `bash tests/test_domain.sh`

## Risks and Assumptions
- 某些内网测试环境无法访问公网 API，需提供 `--skip-dns-check` 逃生通道

## Status
DONE
