# v2ray-deploy
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
curl -fsSLO https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/{v2ray-d
  eploy.sh,godaddy-dns.sh} && bash v2ray-deploy.sh full
```

### 仅安装 V2Ray + Nginx（DNS 需自行配置）：                                               

```bash
bash <(curl -fsSL                                                                      
  https://raw.githubusercontent.com/seedotlee-lgtm/v2ray-deploy/main/v2ray-deploy.sh)
  install
```

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

确认后自动执行 6 个步骤：

1. 安装 V2Ray
2. 配置 V2Ray (vmess + WebSocket)
3. 安装 Nginx 并部署伪装 Web 站点
4. 配置 Nginx 反向代理 (HTTP + WS 转发)
5. 配置防火墙 (放行 80、443 及 V2Ray 端口)
6. 通过 certbot 申请并安装 TLS 证书 (自动续期)

部署完成后输出完整的客户端连接参数。

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

## 典型部署流程

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
```
