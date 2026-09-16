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
| [**`06_bearer_auth_proxy.sh`**](file:///home/sean/git/Auto-Certificate/examples/06_bearer_auth_proxy.sh) | **无鉴权后端添加 Nginx Bearer 鉴权** | `--auth-bearer <token>`，保护 Ollama / 本地微服务 |
| [**`07_llm_ai_optimized_proxy.sh`**](file:///home/sean/git/Auto-Certificate/examples/07_llm_ai_optimized_proxy.sh) | **大模型 (LLM/AI) 专项反代与流式优化** | `--optimize-llm`，600s超时 + 关闭缓冲 + SSE 流式秒推 |
| [**`08_rotate_bearer_token.sh`**](file:///home/sean/git/Auto-Certificate/examples/08_rotate_bearer_token.sh) | **根据域名更新/轮转/移除 Bearer Token** | `token update` / `site update-bearer`，零停机平滑热生效 |

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

### 4. 如何为无鉴权的后端服务添加 Bearer Token 访问鉴权？
当反代本地无鉴权服务（例如本地运行的 Ollama LLM、Prometheus、Node/Python 内部接口等）时，直接暴露到公网或内网是非常危险的。
`ngx-cert-manager` 原生支持在 Nginx 层添加 Bearer Token 校验：
- **CLI 命令行**：
  - **自动生成 Token 并写入 `.tokens/`**（已在 `.gitignore` 中）：直接指定 `--auth-bearer` 或 `--gen-bearer`：
    ```bash
    sudo ngx-cert site add \
        --domain ai.example.com \
        --upstream 127.0.0.1:11434 \
        --auth-bearer \
        --email admin@example.com
    # 系统会自动生成 sk-xxxx 并安全保存在 .tokens/ai.example.com.token (chmod 600)
    ```
  - **自定义指定 Token**：
    ```bash
    sudo ngx-cert site add \
        --domain ai.example.com \
        --upstream 127.0.0.1:11434 \
        --auth-bearer "sk-my-super-secret-token" \
        --email admin@example.com
    ```
- **TUI 交互向导**：向导第 9 步会自动询问 `是否需要由 Nginx 增加 Bearer Token 鉴权保护?`，直接按 Enter 留空即可自动生成高强度 Token 并存入 `.tokens/` 目录。
- **自动忽略防泄露**：生成的 `.tokens/` 目录和 `*.token` 文件已被加入 `.gitignore`，且权限强制设置为 `600`，彻底避免 Git 提交泄露。
- **多 Token 支持**：支持传入逗号分隔的多组 Token（如 `"token1, token2"`）。
- **CORS 预检支持**：自动放行浏览器 `OPTIONS` 跨域预检请求，避免跨域 Web 前端调用因鉴权报错。
- **未授权拦截**：未携带或携带错误凭证的请求直接由 Nginx 响应 `401 Unauthorized`，完全阻断流量打到后端服务。

### 5. 反向代理大语言模型 (LLM/AI) 为什么需要专项优化 (`--optimize-llm`)？
普通反向代理配置主要面向传统静态网站或普通 Web API，而大语言模型具有两大显著特征：
1. **深度推理耗时长（容易 504）**：
   - 带有思考链的模型（如 `qwen3.5`、`deepseek-r1`）在非流式调用或复杂推理时往往需要生成上千个 tokens，耗时可达数分钟。若使用普通默认的 `60s` 超时，必定触发 `504 Gateway Time-out`。
   - `--optimize-llm` 自动配置 `proxy_read_timeout 600s;` 和 `proxy_send_timeout 600s;`（10 分钟长连接保证）。
2. **流式传输打字机效果（容易被 Nginx 缓冲阻断）**：
   - 客户端依赖 Server-Sent Events (SSE) 逐字打字推送。如果开启了 Nginx 代理缓冲（`proxy_buffering on`），Nginx 会将输出积攒到 8KB 满之后才一次性冲刷给客户端，导致前端流式卡顿变成大段吐字。
   - `--optimize-llm` 会彻底关闭缓冲（`proxy_buffering off;`、`proxy_request_buffering off;`、`tcp_nodelay on;`），实现真正的逐 Token 毫秒级打字机推送。

### 6. 后续如何根据域名更新、轮转或移除已有的 Bearer Token？
**完全支持基于域名进行一键更新与平滑热生效！**
- **更新/自动轮转新 Token**：
  ```bash
  # 自动生成全新高强度 Token 并替换 (零中断热重载):
  sudo ngx-cert site update-bearer --domain server-10001.002788.xyz
  # 或:
  sudo ngx-cert token update --domain server-10001.002788.xyz
  ```
- **手动指定新 Token**：
  ```bash
  sudo ngx-cert site update-bearer --domain server-10001.002788.xyz --token "sk-new-super-token"
  ```
- **查看与检索 Token 凭据**：
  ```bash
  # 查看单个域名生效的 Token:
  sudo ngx-cert token get --domain server-10001.002788.xyz

  # 列表大盘查看所有站点的 Token:
  sudo ngx-cert token list
  ```
- **彻底移除 Bearer 鉴权保护 (恢复透明直通代理)**：
  ```bash
  sudo ngx-cert site update-bearer --domain server-10001.002788.xyz --remove
  # 或:
  sudo ngx-cert token delete --domain server-10001.002788.xyz
  ```
- **TUI 交互模式**：
  启动 `./ngx-cert-manager`，进入 `[2] 反向代理站点管理 (Reverse Proxy)` -> `[2] 更新/轮转站点 Bearer Token`，输入域名后选择自动生成或输入新 Token 即可。

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
