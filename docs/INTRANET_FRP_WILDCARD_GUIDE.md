# 内网穿透与泛域名 SSL 反向代理完整运维指南

本文档专门针对 **“无公网 IP 内网服务器 + FRP 端口映射 + Cloudflare DNS-01 泛域名证书 + Nginx SNI 单端口多域名复用”** 的完整架构设计与日常运维手册。

通过本套方案，你可以实现：**公网只开一个 FRP 端口（例如 `26703`），即可安全托管内网任意多个不同服务/不同机器，且全部自动支持 HTTPS、HTTP/2、WebSocket 与自动续期。**

---

## 目录
- [一、核心架构与技术原理](#一核心架构与技术原理)
- [二、前置准备与基础环境](#二前置准备与基础环境)
- [三、后续持续添加新域名 SOP（标准作业流程）](#三后续持续添加新域名-sop标准作业流程)
- [四、常用运维命令全集（复制即用）](#四常用运维命令全集复制即用)
  - [1. 站点反向代理管理 (site)](#1-站点反向代理管理-site)
  - [2. SSL 泛域名证书管理 (cert)](#2-ssl-泛域名证书管理-cert)
  - [3. 自动续期守护 (timer)](#3-自动续期守护-timer)
  - [4. Nginx 服务运维 (nginx)](#4-nginx-服务运维-nginx)
- [五、局域网多主机多设备反代实战](#五局域网多主机多设备反代实战)
- [六、高级进阶与多级域名说明](#六高级进阶与多级域名说明)
- [七、常见问题排查 (FAQ & Troubleshooting)](#七常见问题排查-faq--troubleshooting)

---

## 一、核心架构与技术原理

### 1. 链路拓扑图

```text
       [ 互联网客户端 / 手机 / 外部浏览器 ]
                         │
                         ▼  访问: https://<服务名>.sean-server.002788.xyz:26703/
       [ Cloudflare DNS (DNS-only 模式) ]
                         │  A 记录解析到公网 VPS: 47.108.81.129
                         ▼
       [ 阿里云公网 VPS (FRP Server) ]
                         │  监听端口: 26703 (协议: TCP 透传，不解密 TLS)
                         ▼  通过 FRP 隧道安全穿透到家庭/公司内网
       [ 内网主机 (192.168.31.110) - FRP Client 容器 ]
                         │  监听本地 443 端口
                         ▼
       [ 内网主机 (192.168.31.110) - Nginx 核心网关 ]
                         │
                         ├─ 1. 加载泛域名证书 (*.sean-server.002788.xyz) 完成 TLS 握手
                         ├─ 2. 通过 SNI (Server Name Indication) 识别访问的具体子域名
                         │
         ┌───────────────┼───────────────┬────────────────────────┐
         │ (域名匹配)     │ (域名匹配)     │ (域名匹配)              │ (域名匹配)
         ▼               ▼               ▼                        ▼
  [ 10201 业务服务 ]  [ 10202 业务服务 ]  [ 本机其他容器 ]         [ 局域网其他机器 (如 NAS) ]
  127.0.0.1:10201    127.0.0.1:10202    127.0.0.1:10000         192.168.31.200:5000
```

### 2. 为什么公网一个端口能代理多个不同服务？
* **常规误区**：很多人以为一个端口只能反代一个网站。
* **技术关键**：FRP 客户端配置为 **`type = "tcp"`**，公网 `26703` 端口只负责透明转发底层 TCP 数据包。
* **SNI 域名分发**：现代 HTTPS 握手首个数据包（Client Hello）中带有 **SNI（域名标识）**。内网 Nginx 拿到报文后，使用 `*.sean-server.002788.xyz` 泛域名证书解密，并精准匹配对应的 `server { server_name 10201.xxx; }` 配置块，进而将流量分发给对应的内网端口。

---

## 二、前置准备与基础环境

### 1. Cloudflare DNS 解析与 API Token
* **DNS 记录**：
  * 主机记录：`*.sean-server.002788.xyz`
  * 记录类型：`A`
  * 记录值：`47.108.81.129`（公网 VPS IP）
  * 代理状态：`仅限 DNS`（DNS only，关闭小黄云）
* **API Token**：
  * 在 Cloudflare 控制台申请具备 `Zone.DNS (编辑)` 权限的 Token。
  * 填入本地代码库中的 `config.env` 文件：
    ```bash
    CF_DNS_API_TOKEN="cfut_n4bmn..."
    ```

### 2. 目标主机上的 FRP 客户端配置
内网主机（`192.168.31.110`）的配置文件（如 `/ssd0/apps/frpc-88frp/frpc.toml`）：
```toml
[[proxies]]
name = "zAeQHChOYy4J"
type = "tcp"
localIP = "127.0.0.1"
localPort = 443
remotePort = 26703
transport.useEncryption = true
transport.useCompression = true
```

---

## 三、后续持续添加新域名 SOP（标准作业流程）

后续内网有任何新服务上线，只需按照以下三步操作：

### 步骤 1：确认内网服务正常运行
在目标主机上，确保你的业务服务（Python、NodeJS、Docker、Go 等）正在监听某个本地端口或局域网 IP，例如 `127.0.0.1:8080`：
```bash
# 测试本地端口是否可访问：
curl -sI http://127.0.0.1:8080
```

### 步骤 2：在本地电脑执行一条命令完成反代与证书配置
在你的日常工作电脑上的 `Auto-Certificate` 目录下运行：
```bash
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
    --domain app.sean-server.002788.xyz \
    --upstream 127.0.0.1:8080 \
    --dns-cf
```
> **自动优化特性**：系统检测到已存在 `*.sean-server.002788.xyz` 泛域名证书时，**无需重复走 ACME 验证，0 秒直接复用**，自动生成 Nginx 配置并平滑重载（Zero Downtime）。

### 步骤 3：验证公网访问
在浏览器或终端直接访问：
```bash
https://app.sean-server.002788.xyz:26703/
```

---

## 四、常用运维命令全集（复制即用）

所有命令推荐直接在**本地终端**执行，工具会自动通过 SSH 远程免安装调用目标机运维引擎。

### 1. 站点反向代理管理 (site)

#### 1.1 添加反向代理站点
```bash
# 添加本机某个端口（如 10203）
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
    --domain 10203.sean-server.002788.xyz \
    --upstream 127.0.0.1:10203 \
    --dns-cf

# 自定义客户端最大上传限制为 200MB（默认 50MB）
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
    --domain pan.sean-server.002788.xyz \
    --upstream 127.0.0.1:5244 \
    --body-size 200m \
    --dns-cf
```

#### 1.2 查看当前所有受管站点大盘
```bash
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site list
```
输出示例：
```text
域名 / 虚拟主机                | 上游目标 (Upstream)    | SSL 状态   | HSTS    
--------------------------------------------------------------------------------
10201.sean-server.002788.xyz | http://127.0.0.1:10201 | 🟢 有效(89d) | 开启  
10202.sean-server.002788.xyz | http://127.0.0.1:10202 | 🟢 有效(89d) | 开启  
```

#### 1.3 查看某个站点的 Nginx 配置文件内容
```bash
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site get \
    --domain 10201.sean-server.002788.xyz
```

#### 1.4 下线并删除反代站点
```bash
# 安全删除站点配置（保留泛域名证书给其他子域名继续使用）
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site delete \
    --domain 10201.sean-server.002788.xyz
```

---

### 2. SSL 泛域名证书管理 (cert)

#### 2.1 重新申请或强制重新签发泛域名证书
```bash
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean cert issue \
    --domain "*.sean-server.002788.xyz" \
    --email admin@002788.xyz \
    --dns-cf \
    --force
```

#### 2.2 查看所有受管证书剩余有效天数
```bash
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean cert list
```
输出示例：
```text
域名 / 证书名称          | 状态       | 剩余天数 | 到期日期   
--------------------------------------------------------------------------------
sean-server.002788.xyz   | 有效       | 89 天   | 2026-12-09     
```

#### 2.3 模拟演练证书自动续期 (Dry Run)
```bash
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean cert renew --dry-run
```

---

### 3. 自动续期守护 (timer)

系统已为内网主机自动注册并启用了 Systemd 定时器，每天自动扫描证书到期情况，剩余不足 30 天时自动通过 Cloudflare DNS-01 完成无感续期。

```bash
# 激活/重新注册续期定时器：
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean timer setup

# 查看续期定时器运行状态：
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean timer status

# 查看证书续期审计日志：
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean timer logs
```

---

### 4. Nginx 服务运维 (nginx)

```bash
# 检查 Nginx 配置文件语法是否有错误：
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean nginx test

# 平滑重载 Nginx（修改配置后安全生效）：
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean nginx reload

# 查看 Nginx 服务状态与版本：
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean nginx status
```

---

## 五、局域网多主机多设备反代实战

除了内网服务器本机（`127.0.0.1`）的服务，**这台服务器还可以充当整个家庭/公司局域网的统一反代网关**！

你可以将同一个网段下的其他设备也分配子域名暴露到外网：

```bash
# 示例 1: 代理内网群晖/NAS (IP: 192.168.31.200, 端口: 5000)
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
    --domain nas.sean-server.002788.xyz \
    --upstream 192.168.31.200:5000 \
    --dns-cf

# 示例 2: 代理内网路由器管理后台 (IP: 192.168.31.1, 端口: 80)
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
    --domain router.sean-server.002788.xyz \
    --upstream 192.168.31.1:80 \
    --dns-cf

# 示例 3: 代理内网 Home Assistant 智能家居 (IP: 192.168.31.150, 端口: 8123)
./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
    --domain hass.sean-server.002788.xyz \
    --upstream 192.168.31.150:8123 \
    --dns-cf
```

访问方式完全一致：
* `https://nas.sean-server.002788.xyz:26703`
* `https://router.sean-server.002788.xyz:26703`
* `https://hass.sean-server.002788.xyz:26703`

全部自动共享 `*.sean-server.002788.xyz` 泛域名证书！

---

## 六、高级进阶与多级域名说明

### 1. 泛域名证书的覆盖范围
Let's Encrypt 签发的 `*.sean-server.002788.xyz` 泛域名证书仅匹配 **单层前缀**：
* ✅ 匹配：`10201.sean-server.002788.xyz`
* ✅ 匹配：`app.sean-server.002788.xyz`
* ❌ 不匹配：`test.dev.sean-server.002788.xyz`（双层前缀）

### 2. 如果未来想使用更深层的三级域名？
例如想要 `dev.api.sean-server.002788.xyz`：
1. **方案 A（推荐，单独签发单域名证书）**：
   直接执行命令指定该三级域名，工具会自动为其独立签发证书：
   ```bash
   ./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
       --domain dev.api.sean-server.002788.xyz \
       --upstream 127.0.0.1:3000 \
       --dns-cf
   ```
2. **方案 B（申请二级泛域名证书）**：
   签发 `*.api.sean-server.002788.xyz` 泛域名证书：
   ```bash
   ./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean cert issue \
       --domain "*.api.sean-server.002788.xyz" \
       --email admin@002788.xyz \
       --dns-cf
   ```

---

## 七、常见问题排查 (FAQ & Troubleshooting)

### Q1：为什么访问两个不同域名，看到的内容一模一样？
* **原因**：Nginx 的默认回落机制（Default Server）。当访问的域名**没有在 Nginx 中配置对应的 site 虚拟主机**时，Nginx 会自动落到监听 443 端口的第一个站点。
* **解决**：使用 `site add --domain <域名>` 为该域名添加专属配置即可。

### Q2：访问提示 `502 Bad Gateway`？
* **原因**：Nginx 已经成功接收请求，但配置的内网后端上游（Upstream）服务没有运行或端口写错。
* **排查**：在 `192.168.31.110` 上运行 `curl http://<上游IP>:<端口>`，确认后端程序是否正在监听并能够响应。

### Q3：访问提示 `Connection Refused` 或 `Unexpected EOF`？
* **原因**：FRP 客户端断开连接，或者 Nginx 443 端口未启动。
* **排查**：
  1. 检查内网机器上的 FRP 容器状态：`docker ps | grep frp`
  2. 检查 Nginx 443 监听：`ss -tulpn | grep 443`

### Q4：访问时必须在网址后面加 `:26703` 端口吗？
* **原因**：因为你的公网云服务器（阿里云）未开放或没有将标准的 `443` 端口映射给内网，而是分配了高位端口 `26703`。
* **解决**：只要客户端浏览器中输入 `https://<子域名>.sean-server.002788.xyz:26703/` 即可正常访问。如果未来公网云服务器开放了标准 `443` 端口，将 FRP `remotePort` 改为 `443` 后，即可免输入端口号直接通过 `https://<子域名>...` 访问。
