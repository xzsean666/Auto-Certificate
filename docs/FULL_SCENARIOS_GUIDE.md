# ngx-cert-manager 全场景实战与配置全集指南

本文档涵盖 `ngx-cert-manager` 在不同网络拓扑、服务器环境与 CDN 策略下的**所有核心部署场景**。包含技术原理解析、架构图、选型决策树以及可直接复制运行的单行命令。

---

## 目录

- [一、全场景架构选型决策树 (Decision Tree)](#一全场景架构选型决策树-decision-tree)
- [二、场景一：独立公网主机 (公网 VPS / 云服务器直连)](#二场景一独立公网主机-公网-vps--云服务器直连)
  - [1.1 标准公网 80/443 开放环境 (Webroot 零中断经典方案)](#11-标准公网-80443-开放环境-webroot-零中断经典方案)
  - [1.2 国内云服务器未备案 / 80 端口被封禁 (DNS-01 绕过方案)](#12-国内云服务器未备案--80-端口被封禁-dns-01-绕过方案)
- [三、场景二：使用 Cloudflare 开启小黄云 (Proxied 边缘 CDN 代理)](#三场景二使用-cloudflare-开启小黄云-proxied-边缘-cdn-代理)
  - [2.1 Flexible 灵活模式 (源站纯 HTTP 80，免证书零开销)](#21-flexible-灵活模式-源站纯-http-80免证书零开销)
  - [2.2 Full (Strict) 严格模式 (端到端全程 HTTPS 加密)](#22-full-strict-严格模式-端到端全程-https-加密)
- [四、场景三：不使用小黄云 (DNS Only 纯解析直连)](#四场景三不使用小黄云-dns-only-纯解析直连)
- [五、场景四：内网服务器 + FRP 穿透 + 泛域名单端口复用](#五场景四内网服务器--frp-穿透--泛域名单端口复用)
- [六、进阶特性与组合配置](#六进阶特性与组合配置)
  - [6.1 Unix Domain Socket (UDS) 本地高性能反代](#61-unix-domain-socket-uds-本地高性能反代)
  - [6.2 WebSocket 长连接与大文件上传限制](#62-websocket-长连接与大文件上传限制)
  - [6.3 沙箱演练模式 (--staging) 避免触发限流](#63-沙箱演练模式---staging-避免触发限流)
- [七、全命令速查清单 (Cheatsheet)](#七全命令速查清单-cheatsheet)

---

## 一、全场景架构选型决策树 (Decision Tree)

使用以下决策树，快速找到适合你网络环境的部署命令：

```mermaid
flowchart TD
    Start[开始部署新网站/服务] --> Q1{你的服务器有独立公网 IP 吗?}
  
    Q1 -->|没有 / 处于局域网或家庭内网| Intranet[需要使用 FRP / 穿透工具]
    Intranet --> IntranetCmd["使用场景四: FRP + 泛域名 + DNS-01<br>./ngx-cert-manager site add --domain xxx --upstream 127.0.0.1:port --dns-cf"]
  
    Q1 -->|有独立公网 IP (VPS/云服务器)| Q2{域名解析开启了 Cloudflare 小黄云吗?}
  
    Q2 -->|开启了 (Proxied 模式)| Q3{源站到 Cloudflare 之间需要加密吗?}
    Q3 -->|不需要 (Flexible 灵活模式)| CFCmd1["使用场景 2.1: 纯 HTTP 回源 (极简)<br>./ngx-cert-manager site add --domain xxx --upstream 127.0.0.1:port --no-ssl"]
    Q3 -->|需要 (Full/Strict 端到端加密)| CFCmd2["使用场景 2.2: DNS-01 签发源站证书<br>./ngx-cert-manager site add --domain xxx --upstream 127.0.0.1:port --dns-cf"]
  
    Q2 -->|没开启 (DNS Only 灰色云朵)| Q4{公网 80 端口畅通吗? (国内是否备案)}
    Q4 -->|畅通 (海外VPS / 国内已备案)| PublicWebroot["使用场景 1.1: Webroot 零停机签发 (推荐)<br>./ngx-cert-manager site add --domain xxx --upstream 127.0.0.1:port --email admin@xx.com"]
    Q4 -->|被阻断 (国内未备案/家庭宽带)| PublicDNS["使用场景 1.2: DNS-01 API 验证签发<br>./ngx-cert-manager site add --domain xxx --upstream 127.0.0.1:port --dns-cf"]
```

---

## 二、场景一：独立公网主机 (公网 VPS / 云服务器直连)

### 1.1 标准公网 80/443 开放环境 (Webroot 零中断经典方案)

* **适用环境**：阿里云/腾讯云已备案主机、AWS、GCP、DigitalOcean、Linode、搬瓦工、甲骨文云等海外或合规云主机。80 和 443 端口对外畅通。
* **架构链路**：
  ```text
  客户端 (HTTPS:443) ──> 公网服务器 Nginx (443) ──> 后端服务 (127.0.0.1:3000)
  客户端 (HTTP:80)   ──> 自动 301 强跳至 HTTPS (443)
  Let's Encrypt 验证  ──> 80 端口 /.well-known/acme-challenge/ 穿透验证 (业务零中断)
  ```
* **核心命令**：
  ```bash
  # 本机执行：
  sudo ./ngx-cert-manager site add \
      --domain api.example.com \
      --upstream 127.0.0.1:3000 \
      --email admin@example.com

  # 从本地电脑通过 SSH 远程部署到公网 VPS（远端免安装）：
  ./ngx-cert-manager --ssh root@YOUR_VPS_IP --ssh-key ~/ssh/my_key site add \
      --domain api.example.com \
      --upstream 127.0.0.1:3000 \
      --email admin@example.com
  ```
* **执行效果**：
  1. 自动执行公网 IP 预检与 DNS 一致性核对（防止 DNS 没生效触发限流）；
  2. 自动检测并释放被 Apache/Caddy 异常占用的 80 端口；
  3. 通过 Webroot 无感签发 Let's Encrypt SSL 证书；
  4. 生成符合 Mozilla Intermediate 安全标准的 Nginx 配置；
  5. 开启 HTTP 301 强制跳转 HTTPS、HTTP/2、HSTS 安全头以及 WebSocket 升级；
  6. 自动配置后台 Systemd 定时续期守护。

---

### 1.2 国内云服务器未备案 / 80 端口被封禁 (DNS-01 绕过方案)

* **适用环境**：国内部分云服务器因未取得工信部 ICP 备案，80 端口被运营商强制拦截阻断（但 443 或其他端口可用）；或者家庭宽带公网 IP 封禁 80 端口。
* **痛点解析**：传统的 HTTP-01 验证必须通过公网 80 端口访问验证文件，80 端口不通会导致证书无法签发！
* **解决方案**：使用 `--dns-cf` 参数启用 Cloudflare DNS-01 验证。Certbot 直接通过 Cloudflare API 在 DNS 记录中自动添加 TXT 记录完成验证，**全程不需要 80 端口，甚至不需要公网流量到达服务器即可完成证书签发**！
* **核心命令**：
  ```bash
  sudo ./ngx-cert-manager site add \
      --domain server.example.com \
      --upstream 127.0.0.1:8080 \
      --dns-cf
  ```

---

## 三、场景二：使用 Cloudflare 开启小黄云 (Proxied 边缘 CDN 代理)

开启小黄云（Proxied）后，全球访客访问的是 Cloudflare 位于全球各地的边缘机房节点，源站真实 IP 得到严密隐藏，并自带 DDoS 防护与 CDN 加速。

```text
客户端 ──[HTTPS:443]──> Cloudflare 边缘节点 (自带免费证书) ──[回源]──> 你的源站服务器
```

针对 Cloudflare 到源站的这趟“回源链路”，ngx-cert-manager 提供两种最佳实践：

### 2.1 Flexible 灵活模式 (源站纯 HTTP 80，免证书零开销)

* **适用场景**：
  * Cloudflare 控制台 SSL/TLS 模式设置为 **`Flexible`**。
  * 访客到 Cloudflare 走 HTTPS（浏览器显示安全绿锁），Cloudflare 到源站回源走纯 HTTP 80 端口。
  * **源站完全不需要申请、配置或更新任何 SSL 证书**，极大节省源站 CPU 资源与维护成本。
* **核心命令**（追加 `--no-ssl` 或 `--http-only`）：
  ```bash
  # 本机执行：
  sudo ./ngx-cert-manager site add \
      --domain cf.example.com \
      --upstream 127.0.0.1:3000 \
      --no-ssl

  # 远程执行：
  ./ngx-cert-manager --ssh root@YOUR_VPS_IP --ssh-key ~/ssh/my_key site add \
      --domain cf.example.com \
      --upstream 127.0.0.1:3000 \
      --no-ssl
  ```
* **特点**：
  * 跳过所有证书申请逻辑，0 秒极速部署；
  * Nginx 仅监听 80 端口，自动配置真实客户端 IP 透传（含 `CF-Connecting-IP` 和 `X-Forwarded-For`）；
  * 完美支持 WebSocket 长连接协议升级。

---

### 2.2 Full (Strict) 严格模式 (端到端全程 HTTPS 加密)

* **适用场景**：
  * Cloudflare 控制台 SSL/TLS 模式设置为 **`Full`** 或 **`Full (Strict)`**。
  * 金融、外贸、个人隐私等对数据安全性要求极高的系统，杜绝 Cloudflare 与源站之间明文传输。
* **技术难点**：开启小黄云后，Let's Encrypt 官方验证机访问域名解析出来的是 Cloudflare CDN 节点 IP，而不是源站 IP，导致传统的 HTTP-01 验证无法直达源站。
* **解决方案**：使用 `--dns-cf` 参数走 DNS-01 验证，直接获取被权威机构认可的可信证书。
* **核心命令**：
  ```bash
  sudo ./ngx-cert-manager site add \
      --domain secure.example.com \
      --upstream 127.0.0.1:3000 \
      --dns-cf
  ```

---

## 四、场景三：不使用小黄云 (DNS Only 纯解析直连)

* **适用场景**：

  * Cloudflare 控制台中的域名解析状态为**灰色云朵（DNS only）**。
  * 需要客户端与源站直接握手，不经过 CDN 节点中转（例如需要最低网络延迟、SSH/游戏反代、或者源站已有专用 BGP 优化线路）。
* **配置方式**：

  * 流量直达源站，源站 Nginx 必须持有合法证书并监听 443 端口。

  ```bash
  # 标准开放 80 端口环境：
  sudo ./ngx-cert-manager site add \
      --domain direct.example.com \
      --upstream 127.0.0.1:3000 \
      --email admin@example.com

  # 若源站 80 端口不通或需要泛域名：
  sudo ./ngx-cert-manager site add \
      --domain direct.example.com \
      --upstream 127.0.0.1:3000 \
      --dns-cf
  ```

---

## 五、场景四：内网服务器 + FRP 穿透 + 泛域名单端口复用

* **适用场景**：
  * 家庭宽带、实验室、内网开发机无独立公网 IP；
  * 通过 FRP 客户端将公网云服务器的某个高位端口（如 `26703`）映射给内网 `192.168.31.110` 的 `443` 端口；
  * **目标**：公网只开这一个端口（`26703`），承载内网任意多个不同子域名的服务。
* **架构配置关键**：
  1. FRP 必须使用 **`type = "tcp"`**（透传原生 TLS 报文）；
  2. 申请一张 `*.sean-server.002788.xyz` 泛域名证书；
  3. 内网 Nginx 依据 TLS SNI 域名识别，自动精准分发到不同的内网端口或不同的局域网 IP。
* **核心命令**：
  ```bash
  # 1. 签发泛域名证书 (一次签发，所有二级子域名终身受用)
  ./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean cert issue \
      --domain "*.sean-server.002788.xyz" \
      --email admin@002788.xyz \
      --dns-cf

  # 2. 映射服务 A (如 10201 端口)
  ./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
      --domain 10201.sean-server.002788.xyz \
      --upstream 127.0.0.1:10201 \
      --dns-cf

  # 3. 映射服务 B (如 10202 端口)
  ./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
      --domain 10202.sean-server.002788.xyz \
      --upstream 127.0.0.1:10202 \
      --dns-cf

  # 4. 映射局域网另一台机器 (如 NAS 192.168.31.200:5000)
  ./ngx-cert-manager --ssh root@192.168.31.110 --ssh-key ~/ssh/sean site add \
      --domain nas.sean-server.002788.xyz \
      --upstream 192.168.31.200:5000 \
      --dns-cf
  ```
* **访问方式**：
  * `https://10201.sean-server.002788.xyz:26703/`
  * `https://10202.sean-server.002788.xyz:26703/`
  * `https://nas.sean-server.002788.xyz:26703/`

> 详细配置与原理请参阅专用手册：[内网穿透与泛域名 SSL 反向代理完整运维指南](INTRANET_FRP_WILDCARD_GUIDE.md)。

---

## 六、进阶特性与组合配置

### 6.1 Unix Domain Socket (UDS) 本地高性能反代

当 Python（FastAPI / Django / Gunicorn / Uvicorn）、Node.js 或 PHP-FPM 与 Nginx 在同一台物理机或容器中运行时，可以通过 Linux 内存套接字通信，**吞吐量提升 20%~30%，彻底消除本地端口冲突与 TIME_WAIT 端口枯竭**：

```bash
# 反代至本地 Unix Socket 文件
sudo ./ngx-cert-manager site add \
    --domain fastapi.example.com \
    --upstream unix:/run/uvicorn.sock: \
    --email admin@example.com
```

### 6.2 WebSocket 长连接与大文件上传限制

* **大文件上传限制**：默认客户端请求体上限为 `50m`。若部署网盘或视频服务，可通过 `--body-size` 调整：
  ```bash
  sudo ./ngx-cert-manager site add \
      --domain pan.example.com \
      --upstream 127.0.0.1:5244 \
      --body-size 500m \
      --email admin@example.com
  ```
* **WebSocket 支持**：默认已**全自动启用**（支持实时推送、ChatGPT 打字机效果、在线聊天、SSH Web 控制台）。若不需要，可显式追加 `--no-ws` 禁用。

### 6.3 沙箱演练模式 (--staging) 避免触发限流

Let's Encrypt 正式生产环境对每个主域名有严格的每周 50 次限流。在开发调试或首次测试新域名解析时，强烈建议追加 `--staging`：

```bash
sudo ./ngx-cert-manager site add \
    --domain test.example.com \
    --upstream 127.0.0.1:3000 \
    --staging
```

演练成功后再去掉 `--staging` 即可签发正式浏览器信任证书。

---

## 七、全命令速查清单 (Cheatsheet)

| 运维目标                         | 对应执行命令 (单行复制即用)                                                                                     |
| :------------------------------- | :-------------------------------------------------------------------------------------------------------------- |
| **标准 VPS 公网加 SSL**    | `sudo ./ngx-cert-manager site add --domain a.com --upstream 127.0.0.1:3000 --email admin@a.com`               |
| **Cloudflare 小黄云 HTTP** | `sudo ./ngx-cert-manager site add --domain cf.com --upstream 127.0.0.1:3000 --no-ssl`                         |
| **内网 / 80被封 / 泛域名** | `sudo ./ngx-cert-manager site add --domain sub.a.com --upstream 127.0.0.1:3000 --dns-cf`                      |
| **SSH 远程部署 (免安装)**  | `./ngx-cert-manager --ssh root@IP --ssh-key ~/key site add --domain a.com --upstream 127.0.0.1:3000 --dns-cf` |
| **仅申请泛域名证书**       | `sudo ./ngx-cert-manager cert issue --domain "*.a.com" --email admin@a.com --dns-cf`                          |
| **查看所有站点大盘**       | `sudo ./ngx-cert-manager site list`                                                                           |
| **查看证书到期天数**       | `sudo ./ngx-cert-manager cert list`                                                                           |
| **查看具体站点配置**       | `sudo ./ngx-cert-manager site get --domain a.com`                                                             |
| **安全删除下线站点**       | `sudo ./ngx-cert-manager site delete --domain a.com`                                                          |
| **测试 Nginx 语法**        | `sudo ./ngx-cert-manager nginx test`                                                                          |
| **平滑重载 Nginx**         | `sudo ./ngx-cert-manager nginx reload`                                                                        |
| **激活自动续期定时器**     | `sudo ./ngx-cert-manager timer setup`                                                                         |
| **查看续期守护状态**       | `sudo ./ngx-cert-manager timer status`                                                                        |
| **全系统网络环境体检**     | `sudo ./ngx-cert-manager diagnose`                                                                            |
