# TASK-006: 证书签发、续期、吊销与状态大盘

## Objective
实现 `lib/cert.sh`，封装 Certbot 安装、Webroot 模式零停机签发、Standalone 兜底签发、证书有效期解析大盘、Let's Encrypt Staging 沙箱测试与证书吊销。

## Scope
- Certbot 自动安装适配
- Webroot 模式零中断签发 (`cert_issue_webroot`)
- Standalone 模式兜底签发 (`cert_issue_standalone`)
- 证书大盘看板与有效期计算 (`cert_list`, `cert_get_remaining_days`)
- Staging 演练模式与强制续期控制 (`cert_renew`)
- 证书吊销 (`cert_revoke`)

## Allowed Files
- `lib/cert.sh`
- `tests/test_cert.sh`

## Dependencies
- TASK-004
- TASK-005

## Inputs and Outputs
- **Inputs**: 域名、联系邮箱、签发模式、Staging 标记
- **Outputs**: 证书 PEM 路径、有效天数大盘、签发结果

## Acceptance Criteria
- 证书有效期计算精确到天，并给出 🟢/🟡/🔴 三级状态
- 支持 `--staging` 演练，避免正式环境 Rate Limit
- 签发前校验本地已有证书，有效天数 > 30 天时默认不重复签发

## Verification Commands
- `bash tests/test_cert.sh`

## Risks and Assumptions
- 依赖 Let's Encrypt CA 服务的可达性

## Status
DONE
