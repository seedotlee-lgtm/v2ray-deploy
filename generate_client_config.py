#!/usr/bin/env python3
"""
代理配置文件一键生成器
从 server.json 读取服务端配置，同时生成:
  - Clash Verge (.yaml)
  - Shadowrocket (.conf)
  - VMess 分享链接

用法:
  python3 generate_client_config.py -c server.json
  python3 generate_client_config.py -c server.json -d /output/dir
"""

import json
import base64
import argparse
import textwrap
import os
import sys


def load_servers(config_path):
    """从 JSON 配置文件加载服务端信息"""
    if not os.path.isfile(config_path):
        print(f"错误: 配置文件不存在: {config_path}", file=sys.stderr)
        sys.exit(1)

    with open(config_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 支持单节点 (对象) 或多节点 (数组)
    nodes = data if isinstance(data, list) else [data]

    servers = []
    for i, node in enumerate(nodes):
        servers.append({
            "name":       node.get("name", f"VMess-{i}"),
            "server":     node["server"],
            "port":       int(node.get("port", 443)),
            "uuid":       node["uuid"],
            "alterId":    int(node.get("alterId", 0)),
            "cipher":     node.get("cipher", "auto"),
            "network":    node.get("network", "ws"),
            "ws_path":    node.get("ws_path", "/login"),
            "ws_host":    node.get("ws_host", node["server"]),
            "tls":        node.get("tls", True),
            "servername": node.get("servername", node["server"]),
        })
    return servers


# ============================================================
# Clash Verge 配置生成
# ============================================================

def generate_proxy_block(s):
    """生成单个 VMess 代理节点的 YAML 块"""
    tls = "true" if s["tls"] else "false"
    return f"""\
- name: {s["name"]}
    type: vmess
    server: {s["server"]}
    port: {s["port"]}
    uuid: {s["uuid"]}
    alterId: {s["alterId"]}
    cipher: {s["cipher"]}
    network: {s["network"]}
    tls: {tls}
    udp: true
    skip-cert-verify: false
    servername: {s["servername"]}
    ws-opts:
      path: {s["ws_path"]}
      headers:
        Host: {s["ws_host"]}"""


def generate_clash_config(servers):
    proxy_names = [s["name"] for s in servers]

    proxies_yaml = "\n  ".join(generate_proxy_block(s) for s in servers)

    def proxy_list(names, indent=6):
        pad = " " * indent
        return "\n".join(f"{pad}- {n}" for n in names)

    all_nodes = proxy_list(proxy_names)
    select_with_auto = proxy_list(["♻️ 自动选优"] + proxy_names + ["DIRECT"])
    select_with_proxy = proxy_list(["🚀 节点选择"] + proxy_names + ["DIRECT"])
    select_direct_first = proxy_list(["DIRECT", "🚀 节点选择"] + proxy_names)
    select_fallback = proxy_list(["🚀 节点选择", "DIRECT"])

    return textwrap.dedent(f"""\
# =============================================
# Clash Verge (mihomo) 配置文件
# 自动生成 - 请勿手动编辑
# =============================================

# 基础设置
mixed-port: 7890
socks-port: 7891
port: 7892
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
unified-delay: true
geodata-mode: true
tcp-concurrent: true
find-process-mode: strict
global-client-fingerprint: chrome

# DNS 设置
dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - "*.lan"
    - "*.local"
    - "*.localhost"
    - localhost.ptlogin2.qq.com
    - "+.stun.*.*"
    - "+.stun.*.*.*"
    - dns.msftncsi.com
    - www.msftncsi.com
    - www.msftconnecttest.com
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  fallback:
    - https://dns.cloudflare.com/dns-query
    - https://dns.google/dns-query
    - https://1.0.0.1/dns-query
  fallback-filter:
    geoip: true
    geoip-code: CN
    ipcidr:
      - 240.0.0.0/4

# 代理节点
proxies:
  {proxies_yaml}

# 代理组
proxy-groups:
  - name: 🚀 节点选择
    type: select
    proxies:
{select_with_auto}

  - name: ♻️ 自动选优
    type: url-test
    proxies:
{all_nodes}
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50

  - name: 📹 YouTube
    type: select
    proxies:
{select_with_proxy}

  - name: 🤖 AI 服务
    type: select
    proxies:
{select_with_proxy}

  - name: 📲 Telegram
    type: select
    proxies:
{select_with_proxy}

  - name: 🍎 Apple
    type: select
    proxies:
{select_direct_first}

  - name: 🧩 Microsoft
    type: select
    proxies:
{select_direct_first}

  - name: 🎮 Steam
    type: select
    proxies:
{select_direct_first}

  - name: 🐟 漏网之鱼
    type: select
    proxies:
{select_fallback}

# 规则提供者
rule-providers:
  reject:
    type: http
    behavior: domain
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt
    path: ./ruleset/reject.yaml
    interval: 86400
  direct:
    type: http
    behavior: domain
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/direct.txt
    path: ./ruleset/direct.yaml
    interval: 86400
  proxy:
    type: http
    behavior: domain
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/proxy.txt
    path: ./ruleset/proxy.yaml
    interval: 86400
  private:
    type: http
    behavior: domain
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/private.txt
    path: ./ruleset/private.yaml
    interval: 86400
  cncidr:
    type: http
    behavior: ipcidr
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/cncidr.txt
    path: ./ruleset/cncidr.yaml
    interval: 86400
  lancidr:
    type: http
    behavior: ipcidr
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/lancidr.txt
    path: ./ruleset/lancidr.yaml
    interval: 86400
  telegramcidr:
    type: http
    behavior: ipcidr
    url: https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/telegramcidr.txt
    path: ./ruleset/telegramcidr.yaml
    interval: 86400

# 分流规则
rules:
  # 本地/私有网络
  - RULE-SET,private,DIRECT
  - RULE-SET,lancidr,DIRECT,no-resolve

  # 广告拦截
  - RULE-SET,reject,REJECT

  # AI 服务
  - DOMAIN-SUFFIX,openai.com,🤖 AI 服务
  - DOMAIN-SUFFIX,ai.com,🤖 AI 服务
  - DOMAIN-SUFFIX,claude.ai,🤖 AI 服务
  - DOMAIN-SUFFIX,anthropic.com,🤖 AI 服务
  - DOMAIN-SUFFIX,bard.google.com,🤖 AI 服务
  - DOMAIN-SUFFIX,gemini.google.com,🤖 AI 服务
  - DOMAIN-SUFFIX,copilot.microsoft.com,🤖 AI 服务
  - DOMAIN-KEYWORD,openai,🤖 AI 服务

  # YouTube
  - DOMAIN-SUFFIX,youtube.com,📹 YouTube
  - DOMAIN-SUFFIX,googlevideo.com,📹 YouTube
  - DOMAIN-SUFFIX,ytimg.com,📹 YouTube
  - DOMAIN-SUFFIX,youtu.be,📹 YouTube

  # Telegram
  - RULE-SET,telegramcidr,📲 Telegram,no-resolve

  # Apple
  - DOMAIN-SUFFIX,apple.com,🍎 Apple
  - DOMAIN-SUFFIX,icloud.com,🍎 Apple
  - DOMAIN-SUFFIX,icloud-content.com,🍎 Apple
  - DOMAIN-SUFFIX,mzstatic.com,🍎 Apple
  - DOMAIN-SUFFIX,cdn-apple.com,🍎 Apple

  # Microsoft
  - DOMAIN-SUFFIX,microsoft.com,🧩 Microsoft
  - DOMAIN-SUFFIX,windows.net,🧩 Microsoft
  - DOMAIN-SUFFIX,msftconnecttest.com,🧩 Microsoft
  - DOMAIN-SUFFIX,azure.com,🧩 Microsoft
  - DOMAIN-SUFFIX,live.com,🧩 Microsoft
  - DOMAIN-SUFFIX,office.com,🧩 Microsoft
  - DOMAIN-SUFFIX,office365.com,🧩 Microsoft

  # Steam
  - DOMAIN-SUFFIX,steampowered.com,🎮 Steam
  - DOMAIN-SUFFIX,steamcommunity.com,🎮 Steam
  - DOMAIN-SUFFIX,steamstatic.com,🎮 Steam
  - DOMAIN-SUFFIX,steam-chat.com,🎮 Steam

  # 国内直连
  - RULE-SET,direct,DIRECT
  - RULE-SET,cncidr,DIRECT,no-resolve

  # 需要代理的域名
  - RULE-SET,proxy,🚀 节点选择

  # GeoIP 中国直连
  - GEOIP,CN,DIRECT,no-resolve

  # 兜底规则
  - MATCH,🐟 漏网之鱼
""")


# ============================================================
# Shadowrocket 配置生成
# ============================================================

def generate_vmess_uri(s):
    """生成 vmess:// 分享链接 (v2rayN 标准格式)"""
    obj = {
        "v": "2",
        "ps": s["name"],
        "add": s["server"],
        "port": str(s["port"]),
        "id": s["uuid"],
        "aid": str(s["alterId"]),
        "scy": s["cipher"],
        "net": s["network"],
        "type": "none",
        "host": s["ws_host"],
        "path": s["ws_path"],
        "tls": "tls" if s["tls"] else "",
        "sni": s["servername"],
    }
    b64 = base64.b64encode(json.dumps(obj, ensure_ascii=False).encode()).decode()
    return f"vmess://{b64}"


def generate_shadowrocket_proxy(s):
    """生成 Shadowrocket [Proxy] 段的节点行"""
    tls_part = "over-tls=true" if s["tls"] else "over-tls=false"
    return (
        f'{s["name"]} = vmess, {s["server"]}, {s["port"]}, '
        f'password={s["uuid"]}, '
        f'obfs=websocket, obfs-path={s["ws_path"]}, '
        f'obfs-header="Host: {s["ws_host"]}", '
        f'tls-name={s["servername"]}, '
        f'{tls_part}, '
        f'alterId={s["alterId"]}'
    )


def generate_shadowrocket_config(servers):
    """生成完整的 Shadowrocket .conf 配置"""
    proxy_names = [s["name"] for s in servers]
    proxy_lines = "\n".join(generate_shadowrocket_proxy(s) for s in servers)
    proxy_names_csv = ", ".join(proxy_names)

    return textwrap.dedent(f"""\
# =============================================
# Shadowrocket 配置文件
# 自动生成 - 请勿手动编辑
# =============================================

[General]
bypass-system = true
skip-proxy = 192.168.0.0/16, 10.0.0.0/8, 172.16.0.0/12, 127.0.0.0/8, 100.64.0.0/10, 17.0.0.0/8, localhost, *.local, *.crashlytics.com
bypass-tun = 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.0.0.0/24, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32
dns-server = 223.5.5.5, 119.29.29.29, 8.8.8.8, 8.8.4.4
fallback-dns-server = 8.8.8.8, 8.8.4.4
ipv6 = false
prefer-ipv6 = false
dns-fallback-system = false
dns-direct-system = false
icmp-auto-reply = true
always-reject-url-rewrite = false
private-ip-answer = true
dns-direct-fallback-proxy = true
update-url =

[Proxy]
{proxy_lines}

[Proxy Group]
🚀 节点选择 = select, {proxy_names_csv}, DIRECT
♻️ 自动选优 = url-test, {proxy_names_csv}, url=http://www.gstatic.com/generate_204, interval=300, tolerance=50
📹 YouTube = select, 🚀 节点选择, {proxy_names_csv}, DIRECT
🤖 AI 服务 = select, 🚀 节点选择, {proxy_names_csv}, DIRECT
📲 Telegram = select, 🚀 节点选择, {proxy_names_csv}, DIRECT
🍎 Apple = select, DIRECT, 🚀 节点选择, {proxy_names_csv}
🧩 Microsoft = select, DIRECT, 🚀 节点选择, {proxy_names_csv}
🎮 Steam = select, DIRECT, 🚀 节点选择, {proxy_names_csv}
🐟 漏网之鱼 = select, 🚀 节点选择, DIRECT

[Rule]
# 本地/私有
IP-CIDR,192.168.0.0/16,DIRECT
IP-CIDR,10.0.0.0/8,DIRECT
IP-CIDR,172.16.0.0/12,DIRECT
IP-CIDR,127.0.0.0/8,DIRECT
IP-CIDR,100.64.0.0/10,DIRECT

# AI 服务
DOMAIN-SUFFIX,openai.com,🤖 AI 服务
DOMAIN-SUFFIX,ai.com,🤖 AI 服务
DOMAIN-SUFFIX,claude.ai,🤖 AI 服务
DOMAIN-SUFFIX,anthropic.com,🤖 AI 服务
DOMAIN-SUFFIX,bard.google.com,🤖 AI 服务
DOMAIN-SUFFIX,gemini.google.com,🤖 AI 服务
DOMAIN-SUFFIX,copilot.microsoft.com,🤖 AI 服务
DOMAIN-KEYWORD,openai,🤖 AI 服务

# YouTube
DOMAIN-SUFFIX,youtube.com,📹 YouTube
DOMAIN-SUFFIX,googlevideo.com,📹 YouTube
DOMAIN-SUFFIX,ytimg.com,📹 YouTube
DOMAIN-SUFFIX,youtu.be,📹 YouTube

# Telegram
IP-CIDR,91.108.4.0/22,📲 Telegram,no-resolve
IP-CIDR,91.108.8.0/22,📲 Telegram,no-resolve
IP-CIDR,91.108.12.0/22,📲 Telegram,no-resolve
IP-CIDR,91.108.16.0/22,📲 Telegram,no-resolve
IP-CIDR,91.108.20.0/22,📲 Telegram,no-resolve
IP-CIDR,91.108.56.0/22,📲 Telegram,no-resolve
IP-CIDR,149.154.160.0/20,📲 Telegram,no-resolve
IP-CIDR6,2001:b28:f23d::/48,📲 Telegram,no-resolve
IP-CIDR6,2001:b28:f23f::/48,📲 Telegram,no-resolve
IP-CIDR6,2001:67c:4e8::/48,📲 Telegram,no-resolve
DOMAIN-SUFFIX,telegram.org,📲 Telegram
DOMAIN-SUFFIX,t.me,📲 Telegram
DOMAIN-SUFFIX,telegram.me,📲 Telegram
DOMAIN-SUFFIX,telegra.ph,📲 Telegram

# Apple
DOMAIN-SUFFIX,apple.com,🍎 Apple
DOMAIN-SUFFIX,icloud.com,🍎 Apple
DOMAIN-SUFFIX,icloud-content.com,🍎 Apple
DOMAIN-SUFFIX,mzstatic.com,🍎 Apple
DOMAIN-SUFFIX,cdn-apple.com,🍎 Apple

# Microsoft
DOMAIN-SUFFIX,microsoft.com,🧩 Microsoft
DOMAIN-SUFFIX,windows.net,🧩 Microsoft
DOMAIN-SUFFIX,msftconnecttest.com,🧩 Microsoft
DOMAIN-SUFFIX,azure.com,🧩 Microsoft
DOMAIN-SUFFIX,live.com,🧩 Microsoft
DOMAIN-SUFFIX,office.com,🧩 Microsoft
DOMAIN-SUFFIX,office365.com,🧩 Microsoft

# Steam
DOMAIN-SUFFIX,steampowered.com,🎮 Steam
DOMAIN-SUFFIX,steamcommunity.com,🎮 Steam
DOMAIN-SUFFIX,steamstatic.com,🎮 Steam
DOMAIN-SUFFIX,steam-chat.com,🎮 Steam

# 国内常见域名直连
DOMAIN-SUFFIX,cn,DIRECT
DOMAIN-SUFFIX,taobao.com,DIRECT
DOMAIN-SUFFIX,tmall.com,DIRECT
DOMAIN-SUFFIX,alipay.com,DIRECT
DOMAIN-SUFFIX,alibaba.com,DIRECT
DOMAIN-SUFFIX,aliyun.com,DIRECT
DOMAIN-SUFFIX,jd.com,DIRECT
DOMAIN-SUFFIX,qq.com,DIRECT
DOMAIN-SUFFIX,tencent.com,DIRECT
DOMAIN-SUFFIX,weixin.com,DIRECT
DOMAIN-SUFFIX,wechat.com,DIRECT
DOMAIN-SUFFIX,bilibili.com,DIRECT
DOMAIN-SUFFIX,163.com,DIRECT
DOMAIN-SUFFIX,126.com,DIRECT
DOMAIN-SUFFIX,baidu.com,DIRECT
DOMAIN-SUFFIX,bdstatic.com,DIRECT
DOMAIN-SUFFIX,douyin.com,DIRECT
DOMAIN-SUFFIX,toutiao.com,DIRECT
DOMAIN-SUFFIX,bytedance.com,DIRECT
DOMAIN-SUFFIX,feishu.cn,DIRECT
DOMAIN-SUFFIX,zhihu.com,DIRECT
DOMAIN-SUFFIX,weibo.com,DIRECT
DOMAIN-SUFFIX,xiaomi.com,DIRECT
DOMAIN-SUFFIX,meituan.com,DIRECT
DOMAIN-SUFFIX,dianping.com,DIRECT
DOMAIN-SUFFIX,douban.com,DIRECT
DOMAIN-SUFFIX,pinduoduo.com,DIRECT
DOMAIN-SUFFIX,ctrip.com,DIRECT

# 需要代理的海外常见域名
DOMAIN-SUFFIX,google.com,🚀 节点选择
DOMAIN-SUFFIX,google.com.hk,🚀 节点选择
DOMAIN-SUFFIX,googleapis.com,🚀 节点选择
DOMAIN-SUFFIX,gstatic.com,🚀 节点选择
DOMAIN-SUFFIX,gmail.com,🚀 节点选择
DOMAIN-SUFFIX,facebook.com,🚀 节点选择
DOMAIN-SUFFIX,instagram.com,🚀 节点选择
DOMAIN-SUFFIX,twitter.com,🚀 节点选择
DOMAIN-SUFFIX,x.com,🚀 节点选择
DOMAIN-SUFFIX,twimg.com,🚀 节点选择
DOMAIN-SUFFIX,t.co,🚀 节点选择
DOMAIN-SUFFIX,github.com,🚀 节点选择
DOMAIN-SUFFIX,githubusercontent.com,🚀 节点选择
DOMAIN-SUFFIX,github.io,🚀 节点选择
DOMAIN-SUFFIX,reddit.com,🚀 节点选择
DOMAIN-SUFFIX,redd.it,🚀 节点选择
DOMAIN-SUFFIX,wikipedia.org,🚀 节点选择
DOMAIN-SUFFIX,wikimedia.org,🚀 节点选择
DOMAIN-SUFFIX,amazon.com,🚀 节点选择
DOMAIN-SUFFIX,netflix.com,🚀 节点选择
DOMAIN-SUFFIX,nflxvideo.net,🚀 节点选择
DOMAIN-SUFFIX,spotify.com,🚀 节点选择
DOMAIN-SUFFIX,discord.com,🚀 节点选择
DOMAIN-SUFFIX,discord.gg,🚀 节点选择
DOMAIN-SUFFIX,discordapp.com,🚀 节点选择
DOMAIN-SUFFIX,whatsapp.com,🚀 节点选择
DOMAIN-SUFFIX,medium.com,🚀 节点选择
DOMAIN-SUFFIX,notion.so,🚀 节点选择
DOMAIN-SUFFIX,notion.site,🚀 节点选择
DOMAIN-SUFFIX,v2ex.com,🚀 节点选择

# GeoIP 中国直连
GEOIP,CN,DIRECT

# 兜底
FINAL,🐟 漏网之鱼

[URL Rewrite]
^https?://(www.)?g.cn https://www.google.com 302
^https?://(www.)?google.cn https://www.google.com 302

[MITM]
hostname = www.google.cn, www.g.cn
""")


# ============================================================
# 主入口
# ============================================================

def main():
    parser = argparse.ArgumentParser(description="一键生成 Clash Verge + Shadowrocket 配置")
    parser.add_argument("-c", "--config", required=True,
                        help="服务端配置 JSON 文件路径 (server.json)")
    parser.add_argument("-d", "--output-dir", default=".",
                        help="输出目录 (默认: 当前目录)")
    args = parser.parse_args()

    servers = load_servers(args.config)

    os.makedirs(args.output_dir, exist_ok=True)
    clash_path = os.path.join(args.output_dir, "clash_config.yaml")
    sr_path = os.path.join(args.output_dir, "shadowrocket.conf")

    # ---- Clash Verge ----
    with open(clash_path, "w", encoding="utf-8") as f:
        f.write(generate_clash_config(servers))

    # ---- Shadowrocket ----
    with open(sr_path, "w", encoding="utf-8") as f:
        f.write(generate_shadowrocket_config(servers))

    # ---- VMess 分享链接 ----
    vmess_uris = [generate_vmess_uri(s) for s in servers]

    print("=" * 55)
    print("  代理客户端配置文件生成完毕")
    print("=" * 55)
    print()
    print(f"[1] Clash Verge:   {clash_path}")
    print(f"[2] Shadowrocket:  {sr_path}")
    print(f"    节点数量: {len(servers)}")
    print()
    print("[3] VMess 分享链接 (可直接导入 Shadowrocket / v2rayN):")
    for uri in vmess_uris:
        print(f"    {uri}")
    print()
    print("使用方法:")
    print("  Clash Verge  -> 配置 -> 新建 Local -> 选 .yaml 文件 -> 激活")
    print("  Shadowrocket -> 配置 -> 添加配置 -> 从本地文件导入 .conf")
    print("  或复制 vmess:// 链接 -> Shadowrocket 自动识别导入")


if __name__ == "__main__":
    main()
