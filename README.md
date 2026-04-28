# VPS 工具箱

一键部署 V2Ray (WebSocket + TLS + Web) 及 GoDaddy DNS 管理的 Shell 脚本集合。

---

## 必要条件

### 1. VPS 服务器

需要一台境外 VPS 服务器（Debian / Ubuntu 系统，root 权限）。

推荐使用 [Vultr](https://www.vultr.com/?ref=7163300)，新用户通过推荐链接注册可获得赠款。

### 2. 域名 & GoDaddy DNS（可选，用于域名解析管理）

如需使用一键 DNS 解析功能，需通过 GoDaddy 管理域名：

1. 注册 [GoDaddy](https://www.godaddy.com) 账号
2. 购买一个域名
3. 获取 Open API 的 Key 和 Secret —— [前往 GoDaddy Developer](https://developer.godaddy.com/keys)

> 如果你已有域名且手动配置了 DNS A 记录指向 VPS IP，可跳过此步，直接使用 `v2ray-deploy.sh`。

---

## 一键安装

### 完全版安装（含 GoDaddy DNS 设置）：                                                    

```bash
curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/v2ray-deploy.sh \
&& curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/godaddy-dns.sh \
&& curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/generate_client_config.py \
&& curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/requirements.txt \
&& bash v2ray-deploy.sh full 
```

### 仅安装 V2Ray + Nginx（DNS 需自行配置）： 
**需要提前将域名解析到你的服务器，否则证书会生成失败**

```bash
curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/v2ray-deploy.sh \
&& curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/generate_client_config.py \
&& curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/requirements.txt \
&& bash v2ray-deploy.sh install
```

> 如果在最后显示证书生成失败大概率是 DNS 设置还未能生效，整体重跑一下就好了

## v2ray-deploy.sh

在 Debian/Ubuntu VPS 上一键部署 V2Ray + Nginx + WebSocket + TLS，并支持独立更换域名。

### 前置条件

- Debian / Ubuntu 系统
- root 权限
- 一个已购买的域名，DNS A 记录已指向服务器 IP

### 命令

```bash
# 首次完整部署
bash v2ray-deploy.sh install

# 完全版部署 (含自动设置 GoDaddy A + AAAA 记录)
bash v2ray-deploy.sh full

# 为已部署好的 IPv4 域名补充 IPv6 支持
bash v2ray-deploy.sh add-ipv6

# 新增一个仅 IPv6 解析的域名 (复用现有 V2Ray 服务)
bash v2ray-deploy.sh add-ipv6-only

# 仅更换域名 (保留 UUID、端口、路径不变，重新申请证书)
bash v2ray-deploy.sh change-domain

# 查看当前配置和客户端连接参数
bash v2ray-deploy.sh info
```

### install 流程

脚本会交互询问以下信息（均可直接回车使用自动生成的值）：

| 参数 | 说明 | 默认值 |
|------|------|--------|
| 域名 | 必填，如 `dev.example.com` | - |
| UUID | V2Ray 用户 ID | 自动生成随机 UUID |
| 端口 | V2Ray 内部监听端口 | 自动生成 10000-60000 随机高位端口 |
| WebSocket 路径 | Nginx 转发路径 | `/login` |
| 邮箱 | Let's Encrypt 证书通知邮箱 | - |

确认后自动执行 7 个步骤：

1. 安装 V2Ray
2. 配置 V2Ray (vmess + WebSocket)
3. 安装 Nginx 并部署伪装 Web 站点
4. 配置 Nginx 反向代理 (HTTP + WS 转发，**默认双栈监听 IPv4 + IPv6**)
5. 配置防火墙 (放行 80、443 及 V2Ray 端口，自动启用 UFW IPv6 支持)
6. 通过 certbot 申请并安装 TLS 证书 (自动续期)
7. 生成客户端配置文件 (Clash Verge + Shadowrocket + VMess 链接)

部署完成后输出完整的客户端连接参数，并在 `client-configs/` 目录生成可直接导入的配置文件。

> Nginx 配置默认包含 `listen 80; listen [::]:80;`，certbot 会自动追加对应的 `listen 443 ssl; listen [::]:443 ssl;`，无需手动调整。

### add-ipv6 流程

适用于服务器**已经部署好 IPv4 版本**（V2Ray + Nginx + 证书已就绪），后期补充 IPv6 支持的场景。

```bash
bash v2ray-deploy.sh add-ipv6
```

执行步骤：

1. 自动检测服务器公网 IPv6 地址（无 IPv6 时直接报错退出）
2. 自动从 nginx 配置读取已部署域名（可手动覆盖）
3. **修改 Nginx 配置**：原配置文件备份为 `*.bak.YYYYMMDDHHMMSS`，使用 `sed` 在每条 `listen PORT;` 行后追加对应的 `listen [::]:PORT;`，包括 certbot 已写入的 `listen 443 ssl;` 行
4. `nginx -t` 验证配置后重载（无需重启）
5. **设置 DNS AAAA 记录**：可选自动 (GoDaddy API) 或手动；自动模式会在 Google/Cloudflare DNS 上轮询验证 AAAA 生效

> **证书无需重新申请**。Let's Encrypt 证书绑定的是域名而非 IP，现有证书直接在 IPv4/IPv6 上复用。

> 仅 nginx 双栈监听仍依赖系统/容器具有可路由的公网 IPv6 地址；若 VPS 未分配 IPv6，请先在面板中开启。

### add-ipv6-only 流程

适用于"在已部署的 V2Ray 服务上，新增一个仅 IPv6 解析的独立域名"，例如 `dev.example.com` 已是 IPv4 双栈域名，再加一个 `dev6.example.com` 只走 IPv6。

```bash
bash v2ray-deploy.sh add-ipv6-only
```

执行步骤：

1. 检测服务器公网 IPv6 地址（无则报错）
2. **复用现有 V2Ray 配置**（端口 / UUID / WebSocket 路径），不修改 `/usr/local/etc/v2ray/config.json`
3. 交互输入新域名 + 证书邮箱
4. **AAAA 记录由用户确认**：
   - 选 `y`：调用 GoDaddy API 自动写 AAAA，并轮询 Google/Cloudflare DNS 等待生效
   - 选 `n`：**跳过 DNS 步骤直接进入证书申请**（适合已在其它 DNS 控制台手动配好的情况）
5. 创建独立的 nginx server block，**只写 `listen [::]:80;`**（不写 `listen 80;`，确保仅 IPv6 响应）
6. certbot 申请证书（自动追加 `listen [::]:443 ssl;`）
7. 生成对应的客户端配置文件到 `client-configs/`

> **V2Ray 服务无需重启**。inbound 始终监听 `127.0.0.1:${V2RAY_PORT}`，仅与 nginx 通过本机回环通信，与外部协议栈无关。客户端只需把地址换成新域名，UUID/路径保持不变。

> **限制**：此域名仅 IPv6 可达，IPv4-only 网络（部分移动/办公网）完全无法访问。

### change-domain 流程

用于域名到期更换场景，只需输入新域名和邮箱：

1. 自动读取现有 V2Ray 配置 (UUID / 端口 / 路径保持不变)
2. 重写 Nginx 配置
3. 重新申请 TLS 证书
4. 输出更新后的完整配置

### 客户端配置说明

`info` 命令会输出以下客户端参数，直接填入 V2Ray 客户端即可：

| 参数 | 值 |
|------|-----|
| 地址 (address) | 你的域名 |
| 端口 (port) | 443 |
| 用户ID (id) | 你的 UUID |
| 额外ID (alterId) | 0 |
| 加密方式 (security) | auto |
| 传输协议 (network) | ws |
| 路径 (path) | 你的 WebSocket 路径 |
| 传输安全 (tls) | tls |

---

## godaddy-dns.sh

通过 GoDaddy API 管理域名 DNS 记录，支持查询、新增、修改、删除。

### 前置条件

- GoDaddy 账号，域名托管在 GoDaddy
- API Key + Secret（在 https://developer.godaddy.com/keys 获取）

### 命令

```bash
# 配置 API 凭证 (持久化保存到 ~/.godaddy-dns.conf)
bash godaddy-dns.sh config

# 列出 DNS 记录
bash godaddy-dns.sh list -d example.com
bash godaddy-dns.sh list -d example.com -t A        # 只看 A 记录

# 新增或修改记录 (交互模式，自动判断新增/修改)
bash godaddy-dns.sh set

# 新增或修改记录 (非交互模式)
bash godaddy-dns.sh set -d example.com -n dev -t A -v 1.2.3.4
bash godaddy-dns.sh set -d example.com -n dev -t AAAA -v 2001:db8::1
bash godaddy-dns.sh set -d example.com -n www -t CNAME -v other.com

# 删除记录
bash godaddy-dns.sh delete -d example.com -n old -t A
```

### 参数说明

| 参数 | 缩写 | 说明 | 默认值 |
|------|------|------|--------|
| `--domain` | `-d` | 主域名 | 配置文件中的默认域名 |
| `--name` | `-n` | 记录名称 (`@` = 主域名, `www`, `dev`, `*` 等) | 交互输入 |
| `--type` | `-t` | 记录类型 (A / AAAA / CNAME / TXT / MX / NS / SRV) | A |
| `--value` | `-v` | 记录值 (IP 地址、域名等) | 交互输入 |
| `--ttl` | | TTL 秒数 | 600 |

### 功能特性

- **自动判断新增/修改**：`set` 命令会先查询记录是否存在，存在则修改，不存在则新增
- **A 记录自动检测 IP**：设置 A 记录时自动探测当前服务器公网 IP，回车即可使用
- **凭证持久化**：API Key 保存在 `~/.godaddy-dns.conf`（权限 600），配置一次后续无需重复输入
- **操作后自动验证**：修改完成后回查确认记录已生效

---

## 快速开始 (一键部署)

SSH 到 VPS，执行以下命令即可完成全部部署（含 GoDaddy DNS 自动设置）：

```bash
curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/v2ray-deploy.sh \
  && curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/godaddy-dns.sh \
  && curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/generate_client_config.py \
  && curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/requirements.txt \
  && bash v2ray-deploy.sh full
```

如果 DNS 已手动配置好，可用 `install` 代替 `full`：

```bash
curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/v2ray-deploy.sh \
  && curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/generate_client_config.py \
  && curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/requirements.txt \
  && bash v2ray-deploy.sh install
```

部署完成后会自动生成 Clash Verge 和 Shadowrocket 客户端配置文件。

---

## 典型部署流程 (分步)

```bash
# 1. 配置 GoDaddy API
bash godaddy-dns.sh config

# 2. 将域名 A 记录指向 VPS
bash godaddy-dns.sh set -d example.com -n dev -t A -v <你的VPS IP>

# 3. SSH 到 VPS，部署 V2Ray
bash v2ray-deploy.sh install

# 4. 域名到期后更换
bash godaddy-dns.sh set -d newdomain.com -n dev -t A -v <你的VPS IP>
bash v2ray-deploy.sh change-domain

# 5. (可选) 后期为已有 IPv4 域名补充 IPv6
bash v2ray-deploy.sh add-ipv6
```

---

## IPv6 支持说明

脚本默认在 nginx 中开启 IPv4 + IPv6 双栈监听 (`listen 80;` + `listen [::]:80;`)，并在 `full` 模式下自动设置 DNS A 与 AAAA 记录。

| 场景 | 命令 |
|------|------|
| 全新部署且 VPS 已分配 IPv6 | `bash v2ray-deploy.sh full` (自动写 A + AAAA) |
| 全新部署，DNS 自管 | `bash v2ray-deploy.sh install` + 自行添加 A/AAAA 记录 |
| **已有 IPv4 域名补充 IPv6** | `bash v2ray-deploy.sh add-ipv6` |
| **新增独立的 IPv6-only 域名** | `bash v2ray-deploy.sh add-ipv6-only` |

**验证 IPv6 是否生效**：

```bash
# 服务端检查 nginx 是否监听 IPv6
ss -tlnp | grep -E ':80|:443'        # 应看到 :::80 和 :::443

# 域名是否解析到 AAAA
dig AAAA your-domain.com @8.8.8.8
dig AAAA your-domain.com @1.1.1.1

# 客户端通过 IPv6 实测访问
curl -6 -v https://your-domain.com
```

> **注意**：仅当 VPS 自身分配了可路由的公网 IPv6 地址时，脚本才能完成 IPv6 配置。Vultr / DigitalOcean 等主流厂商默认提供 IPv6，需在控制面板中确认已启用。
