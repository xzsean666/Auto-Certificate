# 生产场景使用示例集 (Examples Guide)

本目录提供了在常见生产环境中使用 `ngx-cert-manager` 的典型脚本与配置参考。所有脚本均可直接修改参数后在生产服务器上运行。

---

## 📂 示例索引与适用场景

| 示例文件 | 核心场景 | 关键参数 / 特性 |
| :--- | :--- | :--- |
| [**`01_standard_ssl_proxy.sh`**](file:///home/sean/git/Auto-Certificate/examples/01_standard_ssl_proxy.sh) | **标准生产 HTTPS 反向代理** | 自动申请证书 + HTTP 301 强跳 + HSTS + WebSocket |
| [**`02_cloudflare_http_only.sh`**](file:///home/sean/git/Auto-Certificate/examples/02_cloudflare_http_only.sh) | **Cloudflare CDN 代理 (纯 HTTP 80 反代)** | `--no-ssl` / `--http-only`，适配 Flexible SSL |
| [**`03_multiple_websites.sh`**](file:///home/sean/git/Auto-Certificate/examples/03_multiple_websites.sh) | **单机多网站/多域名独立托管** | 多租户解耦隔离，各站点独立证书与配置文件 |
| [**`04_unix_socket_upstream.sh`**](file:///home/sean/git/Auto-Certificate/examples/04_unix_socket_upstream.sh) | **Unix Domain Socket 高性能后端** | `unix:/run/app.sock:` 本地高性能进程通信 |
| [**`05_auto_renew_management.sh`**](file:///home/sean/git/Auto-Certificate/examples/05_auto_renew_management.sh) | **自动续期守护监控与演练** | Systemd Timer 状态、Dry-run 演练、审计日志 |

---

## 💡 核心问题解答

### 1. 可以配置多个网站吗？各网站会互相影响吗？
**完全可以，支持任意数量的网站同时托管！**
- `ngx-cert-manager` 为每个域名生成独立的 `/etc/nginx/conf.d/<domain>.conf` 文件。
- 每次新增、修改或删除某一个站点时，均通过 `.tmp` 预校验和 `nginx -t` 语法自检。
- 即使某个站点的配置写错，原子回滚机制会立刻还原，**绝对不会影响其他正在运行的线上业务**。

### 2. Cloudflare CDN 代理场景该怎么配置？
在 Cloudflare 开启小黄云（Proxied 橙色云朵）代理时，有两种常见模式：
- **模式 A：纯 HTTP 80 端口反代 (`--no-ssl`)**
  - **Cloudflare SSL 设置**：设置为 `Flexible` 模式。
  - **原理**：访客与 Cloudflare 节点之间走 HTTPS（由 Cloudflare 提供证书），Cloudflare 节点到你的源站服务器之间走 HTTP 80。
  - **配置命令**：
    ```bash
    sudo ngx-cert site add --domain cf.example.com --upstream 127.0.0.1:3000 --no-ssl
    ```
- **模式 B：端到端加密 HTTPS (`Full / Full Strict`)**
  - **Cloudflare SSL 设置**：设置为 `Full` 或 `Full (Strict)` 模式。
  - **原理**：源站也申请 Let's Encrypt 证书，全程端到端加密传输。
  - **配置命令**：直接使用标准命令即可：
    ```bash
    sudo ngx-cert site add --domain cf.example.com --upstream 127.0.0.1:3000 --email admin@example.com
    ```

### 3. 证书到期会自动更新吗？
**完全全自动更新，零人工介入！**
- **守护机制**：执行 `sudo ngx-cert timer setup`（或通过安装包安装）后，会自动激活 Systemd Timer 定时任务。
- **定时周期**：每天 **03:30** 与 **15:30** 各执行一次全盘扫描。
- **防拥塞抖动**：内置 `RandomizedDelaySec=3600`，随机打散在 1 小时窗口内，防止数万台机器在同一秒向 Let's Encrypt CA 发起请求。
- **智能续期条件**：仅当证书剩余天数 **<= 30 天** 时才会发起续期；若大于 30 天则自动跳过，避免浪费 API 额度。
- **平滑生效**：证书续期成功后，会自动触发 `nginx -s reload` 平滑加载新证书，**服务零中断、无需重启 Nginx**。

---

## 🛠️ 快速执行示例脚本

```bash
# 赋予执行权限
chmod +x examples/*.sh

# 运行示例 1: 配置标准 HTTPS 站点
./examples/01_standard_ssl_proxy.sh

# 运行示例 2: 配置 Cloudflare 纯 HTTP 站点
./examples/02_cloudflare_http_only.sh

# 运行示例 3: 批量配置 3 个不同业务站点
./examples/03_multiple_websites.sh

# 运行示例 5: 演练并查看自动续期状态
./examples/05_auto_renew_management.sh
```
