#!/bin/bash
#
# V2Ray + WebSocket + TLS + Web 一键部署脚本
#
# 用法:
#   首次部署:       bash v2ray-deploy.sh install
#   仅更换域名:     bash v2ray-deploy.sh change-domain
#   查看当前配置:   bash v2ray-deploy.sh info
#

set -eE

# ============================================================
#  颜色输出
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# 捕获错误, 显示失败位置
trap 'echo -e "${RED}[FATAL] 脚本在第 ${LINENO} 行出错, 命令: ${BASH_COMMAND}${NC}"' ERR

# ============================================================
#  前置检查
# ============================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then error "请以 root 用户运行此脚本 (sudo su)"; fi
}

check_os() {
    if ! command -v apt &>/dev/null; then
        error "此脚本仅支持 Debian/Ubuntu 系统"
    fi
}

# ============================================================
#  收集用户输入
# ============================================================
collect_input() {
    echo ""
    echo -e "${CYAN}========== 请提供以下信息 ==========${NC}"
    echo ""

    # 域名
    read -rp "请输入你的域名 (如 example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then error "域名不能为空"; fi

    # UUID (不提供则自动生成)
    DEFAULT_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || echo "")
    echo ""
    echo -e "已为你生成随机 UUID: ${CYAN}${DEFAULT_UUID}${NC}"
    read -rp "请输入 V2Ray 用户 ID (UUID), 直接回车使用自动生成的: " USER_UUID
    USER_UUID=${USER_UUID:-$DEFAULT_UUID}
    if [[ -z "$USER_UUID" ]]; then error "无法生成 UUID, 请手动输入"; fi

    # V2Ray 内部端口 (不提供则随机生成 10000-60000 的高位端口)
    DEFAULT_PORT=$(shuf -i 10000-60000 -n 1 2>/dev/null || echo $(( RANDOM % 50001 + 10000 )))
    echo ""
    echo -e "已为你生成随机端口: ${CYAN}${DEFAULT_PORT}${NC}"
    read -rp "请输入 V2Ray 监听端口, 直接回车使用自动生成的: " V2RAY_PORT
    V2RAY_PORT=${V2RAY_PORT:-$DEFAULT_PORT}

    # WebSocket path
    read -rp "请输入 WebSocket 路径 [默认 /login]: " WS_PATH
    WS_PATH=${WS_PATH:-/login}
    # 确保以 / 开头
    if [[ "$WS_PATH" != /* ]]; then WS_PATH="/$WS_PATH"; fi

    # 邮箱 (certbot 需要)
    echo ""
    read -rp "请输入你的邮箱 (用于 Let's Encrypt 证书通知): " CERT_EMAIL
    if [[ -z "$CERT_EMAIL" ]]; then error "邮箱不能为空"; fi

    echo ""
    echo -e "${CYAN}========== 配置确认 ==========${NC}"
    echo -e "  域名:          ${GREEN}${DOMAIN}${NC}"
    echo -e "  UUID:          ${GREEN}${USER_UUID}${NC}"
    echo -e "  V2Ray 端口:    ${GREEN}${V2RAY_PORT}${NC}"
    echo -e "  WebSocket 路径: ${GREEN}${WS_PATH}${NC}"
    echo -e "  证书邮箱:      ${GREEN}${CERT_EMAIL}${NC}"
    echo ""
    read -rp "确认以上信息? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then error "已取消"; fi
}

# ============================================================
#  1. 安装 V2Ray
# ============================================================
install_v2ray() {
    info "正在安装 V2Ray..."
    if command -v v2ray &>/dev/null; then
        warn "V2Ray 已安装, 跳过安装步骤"
    else
        info "下载 V2Ray 安装脚本..."
        local tmp_script=$(mktemp)
        if ! curl -fsSL -o "$tmp_script" https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh; then
            rm -f "$tmp_script"
            error "V2Ray 安装脚本下载失败, 请检查网络连接"
        fi
        info "执行 V2Ray 安装脚本..."
        bash "$tmp_script"
        rm -f "$tmp_script"
    fi
    info "V2Ray 安装完成"
}

# ============================================================
#  2. 配置 V2Ray (vmess + ws)
# ============================================================
configure_v2ray() {
    info "写入 V2Ray 配置..."
    cat > /usr/local/etc/v2ray/config.json <<VEOF
{
    "inbounds": [
        {
            "port": ${V2RAY_PORT},
            "listen": "127.0.0.1",
            "protocol": "vmess",
            "settings": {
                "clients": [
                    {
                        "id": "${USER_UUID}",
                        "alterId": 0
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "${WS_PATH}"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {}
        }
    ]
}
VEOF

    systemctl restart v2ray
    systemctl enable v2ray
    info "V2Ray 配置完成并已启动"
}

# ============================================================
#  3. 安装 Nginx 并部署 Web 站点
# ============================================================
install_nginx() {
    info "安装 Nginx..."
    apt update -y
    apt install -y nginx

    info "创建 Web 站点目录..."
    mkdir -p /var/www/${DOMAIN}
    cat > /var/www/${DOMAIN}/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        body { font-family: Arial, sans-serif; display: flex; justify-content: center;
               align-items: center; min-height: 100vh; margin: 0; background: #f5f5f5; }
        .container { text-align: center; padding: 2rem; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to My Site</h1>
        <p>The site is under construction.</p>
    </div>
</body>
</html>
HTMLEOF
}

# ============================================================
#  4. 配置 Nginx (HTTP, 含 WS 转发, 等待 certbot 添加 TLS)
# ============================================================
configure_nginx() {
    info "写入 Nginx 配置..."

    # 写入 sites-available
    cat > /etc/nginx/sites-available/${DOMAIN} <<NEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    root /var/www/${DOMAIN};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ${WS_PATH} {
        if (\$http_upgrade != "websocket") {
            return 404;
        }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${V2RAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NEOF

    # 链接到 sites-enabled
    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/default

    nginx -t || error "Nginx 配置检测失败"
    systemctl restart nginx
    systemctl enable nginx
    info "Nginx 配置完成并已启动 (IPv4 + IPv6)"
}

# ============================================================
#  5. 防火墙放行端口
# ============================================================
setup_firewall() {
    if command -v ufw &>/dev/null; then
        info "配置 UFW 防火墙..."
        # 确保 UFW 启用 IPv6 支持
        if [[ -f /etc/default/ufw ]] && grep -q '^IPV6=no' /etc/default/ufw; then
            sed -i 's/^IPV6=no/IPV6=yes/' /etc/default/ufw
            info "已启用 UFW IPv6 支持"
        fi
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow ${V2RAY_PORT}/tcp
        ufw allow ${V2RAY_PORT}/udp
        ufw --force enable
        info "已放行 80, 443, ${V2RAY_PORT} 端口 (IPv4 + IPv6)"
    else
        warn "未检测到 ufw, 请自行确保 80, 443, ${V2RAY_PORT} 端口已放行 (IPv4 + IPv6)"
    fi
}

# ============================================================
#  6. 安装证书 (独立流程, 可单独调用)
# ============================================================
install_cert() {
    local domain="${1:-$DOMAIN}"
    local email="${2:-$CERT_EMAIL}"

    if [[ -z "$domain" ]]; then read -rp "请输入域名: " domain; fi
    if [[ -z "$domain" ]]; then error "域名不能为空"; fi
    if [[ -z "$email" ]]; then read -rp "请输入邮箱 (用于 Let's Encrypt): " email; fi
    if [[ -z "$email" ]]; then error "邮箱不能为空"; fi

    info "安装 certbot..."
    apt install -y snapd
    snap install --classic certbot 2>/dev/null || true
    ln -sf /snap/bin/certbot /usr/bin/certbot

    info "为 ${domain} 申请并安装 TLS 证书..."
    certbot --nginx -d "$domain" --non-interactive --agree-tos -m "$email" --redirect

    info "TLS 证书安装完成"
    info "certbot 已自动配置定时续期 (查看: systemctl list-timers | grep certbot)"

    systemctl restart nginx
    info "Nginx 已重启, 请访问 https://${domain} 验证"
}

# ============================================================
#  更换域名流程 (独立)
# ============================================================
change_domain() {
    echo ""
    echo -e "${CYAN}========== 更换域名 ==========${NC}"
    echo ""

    # 读取当前域名
    OLD_DOMAIN=""
    if [[ -f /usr/local/etc/v2ray/config.json ]]; then
        # 尝试从 nginx 配置获取当前域名
        OLD_DOMAIN=$(grep -m1 'server_name' /etc/nginx/sites-enabled/default 2>/dev/null | awk '{print $2}' | tr -d ';' || echo "")
    fi

    if [[ -n "$OLD_DOMAIN" ]]; then
        echo -e "当前域名: ${YELLOW}${OLD_DOMAIN}${NC}"
    fi

    read -rp "请输入新域名: " NEW_DOMAIN
    if [[ -z "$NEW_DOMAIN" ]]; then error "域名不能为空"; fi

    read -rp "请输入邮箱 (用于 Let's Encrypt): " CERT_EMAIL
    if [[ -z "$CERT_EMAIL" ]]; then error "邮箱不能为空"; fi

    echo ""
    echo -e "  旧域名: ${YELLOW}${OLD_DOMAIN:-未知}${NC}"
    echo -e "  新域名: ${GREEN}${NEW_DOMAIN}${NC}"
    echo ""
    read -rp "确认更换? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then error "已取消"; fi

    # 1. 创建新站点目录 (如果不存在)
    if [[ ! -d /var/www/${NEW_DOMAIN} ]]; then
        if [[ -n "$OLD_DOMAIN" && -d /var/www/${OLD_DOMAIN} ]]; then
            info "复制站点文件..."
            cp -r /var/www/${OLD_DOMAIN} /var/www/${NEW_DOMAIN}
        else
            mkdir -p /var/www/${NEW_DOMAIN}
            echo "<h1>Welcome</h1>" > /var/www/${NEW_DOMAIN}/index.html
        fi
    fi

    # 2. 读取当前 v2ray 配置中的端口和路径
    V2RAY_PORT=$(grep -oP '"port"\s*:\s*\K\d+' /usr/local/etc/v2ray/config.json 2>/dev/null || echo "10000")
    WS_PATH=$(grep -oP '"path"\s*:\s*"\K[^"]+' /usr/local/etc/v2ray/config.json 2>/dev/null || echo "/login")

    # 3. 重写 nginx 配置 (去除旧证书配置, certbot 会重新添加)
    info "更新 Nginx 配置..."
    cat > /etc/nginx/sites-available/${NEW_DOMAIN} <<NEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${NEW_DOMAIN};

    root /var/www/${NEW_DOMAIN};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ${WS_PATH} {
        if (\$http_upgrade != "websocket") {
            return 404;
        }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${V2RAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NEOF

    rm -f /etc/nginx/sites-enabled/default
    ln -sf /etc/nginx/sites-available/${NEW_DOMAIN} /etc/nginx/sites-enabled/default

    nginx -t || error "Nginx 配置检测失败"
    systemctl restart nginx

    # 4. 申请新证书
    install_cert "$NEW_DOMAIN" "$CERT_EMAIL"

    # 5. 重新生成客户端配置
    local uuid
    uuid=$(grep -oP '"id"\s*:\s*"\K[^"]+' /usr/local/etc/v2ray/config.json 2>/dev/null || echo "")
    if [[ -n "$uuid" ]]; then
        generate_client_configs "$NEW_DOMAIN" "$uuid" "$WS_PATH"
    fi

    info "域名更换完成!"
    echo ""
    show_info
    echo -e "${YELLOW}提示: 请确保新域名的 DNS A 记录已指向本服务器 IP${NC}"
    echo -e "${YELLOW}如使用 Cloudflare, 请在 Cloudflare 控制台更新 DNS 记录${NC}"
}

# ============================================================
#  生成客户端配置文件 (Clash Verge + Shadowrocket)
# ============================================================
generate_client_configs() {
    local domain="$1"
    local uuid="$2"
    local ws_path="$3"

    local script_dir
    script_dir=$(cd "$(dirname "$0")" && pwd)
    local gen_script="${script_dir}/generate_client_config.py"
    local req_file="${script_dir}/requirements.txt"
    local output_dir="${script_dir}/client-configs"
    local server_json="${output_dir}/server.json"

    if [[ ! -f "$gen_script" ]]; then
        warn "未找到 generate_client_config.py, 跳过客户端配置生成"
        return 0
    fi

    # 确保 Python3 可用
    if ! command -v python3 &>/dev/null; then
        info "安装 Python3..."
        if ! apt install -y python3 python3-venv 2>/dev/null; then
            warn "Python3 安装失败, 跳过客户端配置生成"
            return 0
        fi
    fi

    if ! command -v python3 &>/dev/null; then
        warn "Python3 不可用, 跳过客户端配置生成"
        return 0
    fi

    # 安装依赖 (如 requirements.txt 非空)
    if [[ -f "$req_file" ]] && grep -qvE '^\s*#|^\s*$' "$req_file" 2>/dev/null; then
        info "安装 Python 依赖..."
        python3 -m pip install -r "$req_file" --quiet 2>/dev/null || \
        python3 -m pip install -r "$req_file" --quiet --break-system-packages 2>/dev/null || \
        warn "Python 依赖安装失败, 继续尝试生成..."
    fi

    # 写出 server.json
    mkdir -p "$output_dir"
    cat > "$server_json" <<SEOF
{
    "name": "VMess-${domain}",
    "server": "${domain}",
    "port": 443,
    "uuid": "${uuid}",
    "alterId": 0,
    "cipher": "auto",
    "network": "ws",
    "ws_path": "${ws_path}",
    "ws_host": "${domain}",
    "tls": true,
    "servername": "${domain}"
}
SEOF
    info "服务端配置已写入: ${server_json}"

    # 调用 Python 脚本生成客户端配置
    info "生成客户端配置文件..."
    if python3 "$gen_script" -c "$server_json" -d "$output_dir"; then
        echo ""
        info "客户端配置文件已生成到: ${output_dir}/"
        echo -e "  ${GREEN}${output_dir}/clash_config.yaml${NC}   - Clash Verge"
        echo -e "  ${GREEN}${output_dir}/shadowrocket.conf${NC}   - Shadowrocket"
        echo -e "  ${GREEN}${output_dir}/server.json${NC}         - 服务端参数 (可二次生成)"
        echo ""
    else
        warn "客户端配置生成失败, 可稍后手动执行:"
        warn "  python3 ${gen_script} -c ${server_json} -d ${output_dir}"
    fi
}

# ============================================================
#  显示当前配置信息
# ============================================================
show_info() {
    echo ""
    echo -e "${CYAN}========== 当前配置信息 ==========${NC}"

    # 获取本机公网 IP
    local server_ip server_ip6
    server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "获取失败")
    server_ip6=$(get_server_ipv6)

    echo -e "  服务器 IPv4 地址: ${GREEN}${server_ip}${NC}"
    if [[ -n "$server_ip6" ]]; then
        echo -e "  服务器 IPv6 地址: ${GREEN}${server_ip6}${NC}"
    fi
    echo ""

    if [[ -f /usr/local/etc/v2ray/config.json ]]; then
        local uuid=$(grep -oP '"id"\s*:\s*"\K[^"]+' /usr/local/etc/v2ray/config.json 2>/dev/null)
        local port=$(grep -oP '"port"\s*:\s*\K\d+' /usr/local/etc/v2ray/config.json 2>/dev/null)
        local path=$(grep -oP '"path"\s*:\s*"\K[^"]+' /usr/local/etc/v2ray/config.json 2>/dev/null)
        local domain=$(grep -m1 'server_name' /etc/nginx/sites-enabled/default 2>/dev/null | awk '{print $2}' | tr -d ';')

        echo -e "  域名:          ${GREEN}${domain:-未知}${NC}"
        echo -e "  UUID:          ${GREEN}${uuid:-未知}${NC}"
        echo -e "  V2Ray 内部端口: ${GREEN}${port:-未知}${NC}"
        echo -e "  WebSocket 路径: ${GREEN}${path:-未知}${NC}"
        echo ""
        echo -e "${CYAN}--- 客户端配置 ---${NC}"
        echo -e "  地址 (address):     ${GREEN}${domain}${NC}"
        echo -e "  端口 (port):        ${GREEN}443${NC}"
        echo -e "  用户ID (id):        ${GREEN}${uuid}${NC}"
        echo -e "  额外ID (alterId):   ${GREEN}0${NC}"
        echo -e "  加密方式 (security): ${GREEN}auto${NC}"
        echo -e "  传输协议 (network):  ${GREEN}ws${NC}"
        echo -e "  路径 (path):        ${GREEN}${path}${NC}"
        echo -e "  传输安全 (tls):     ${GREEN}tls${NC}"
    else
        warn "未找到 V2Ray 配置文件"
    fi

    echo ""

    # 服务状态
    echo -e "${CYAN}--- 服务状态 ---${NC}"
    if systemctl is-active --quiet v2ray 2>/dev/null; then
        echo -e "  V2Ray: ${GREEN}运行中${NC}"
    else
        echo -e "  V2Ray: ${RED}未运行${NC}"
    fi
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "  Nginx:  ${GREEN}运行中${NC}"
    else
        echo -e "  Nginx:  ${RED}未运行${NC}"
    fi
    echo ""
}

# ============================================================
#  获取本机公网 IP (IPv4 / IPv6)
# ============================================================
get_server_ip() {
    local ip
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
         curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    echo "$ip"
}

get_server_ipv6() {
    local ip6
    ip6=$(curl -s --max-time 5 https://api6.ipify.org 2>/dev/null || \
          curl -s --max-time 5 -6 https://ifconfig.me 2>/dev/null || echo "")
    # 排除返回 IPv4 地址的情况 (某些接口在无 IPv6 时降级返回 IPv4)
    if [[ "$ip6" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo ""
    else
        echo "$ip6"
    fi
}

# ============================================================
#  通过 GoDaddy API 设置 DNS (需要 godaddy-dns.sh 在同目录)
# ============================================================
setup_godaddy_dns() {
    local domain="$1"
    local ip="$2"
    local ip6="${3:-}"  # 可选 IPv6, 有则同时设置 AAAA 记录

    # 定位 godaddy-dns.sh
    local script_dir
    script_dir=$(cd "$(dirname "$0")" && pwd)
    local gdscript="${script_dir}/godaddy-dns.sh"

    if [[ ! -f "$gdscript" ]]; then
        error "未找到 godaddy-dns.sh, 请确保它与 v2ray-deploy.sh 在同一目录下"
    fi

    # 拆分子域名和主域名
    # 如 dev.example.com -> name=dev, main_domain=example.com
    # 如 example.com -> name=@, main_domain=example.com
    local name main_domain
    local dot_count
    dot_count=$(echo "$domain" | tr -cd '.' | wc -c)

    if [[ "$dot_count" -ge 2 ]]; then
        name=$(echo "$domain" | cut -d. -f1)
        main_domain=$(echo "$domain" | cut -d. -f2-)
    else
        name="@"
        main_domain="$domain"
    fi

    echo ""
    echo -e "${CYAN}--- GoDaddy DNS 设置 ---${NC}"
    echo -e "  主域名:   ${GREEN}${main_domain}${NC}"
    echo -e "  记录名:   ${GREEN}${name}${NC}"
    echo -e "  A 记录:   ${GREEN}${ip}${NC}"
    [[ -n "$ip6" ]] && echo -e "  AAAA 记录: ${GREEN}${ip6}${NC}"
    echo ""

    if [[ -n "$ip" ]]; then
        info "设置 A 记录..."
        bash "$gdscript" set -d "$main_domain" -n "$name" -t A -v "$ip"
    fi

    if [[ -n "$ip6" ]]; then
        info "设置 AAAA (IPv6) 记录..."
        bash "$gdscript" set -d "$main_domain" -n "$name" -t AAAA -v "$ip6"
    fi
}

# ============================================================
#  等待 DNS 生效 (A/AAAA 均可选, 至少传一个)
# ============================================================
wait_for_dns() {
    local domain="$1"
    local expected_ip="${2:-}"    # 空则跳过 A 记录检测
    local expected_ip6="${3:-}"   # 空则跳过 AAAA 记录检测
    local max_wait=600
    local interval=15

    if [[ -z "$expected_ip" && -z "$expected_ip6" ]]; then
        warn "wait_for_dns: 未指定目标 IP, 跳过等待"
        return 0
    fi

    local target_desc=""
    [[ -n "$expected_ip" ]]  && target_desc+=" A=${expected_ip}"
    [[ -n "$expected_ip6" ]] && target_desc+=" AAAA=${expected_ip6}"
    info "等待 DNS 全球生效 (${domain} ->${target_desc}) ..."
    info "使用外部 DNS 服务器验证 (8.8.8.8, 1.1.1.1)"

    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        local a_ok=true ip6_ok=true
        local resolved_google="" resolved_cloudflare=""
        local resolved6_google="" resolved6_cloudflare=""

        if [[ -n "$expected_ip" ]]; then
            resolved_google=$(dig +short "$domain" A @8.8.8.8 2>/dev/null | head -1)
            resolved_cloudflare=$(dig +short "$domain" A @1.1.1.1 2>/dev/null | head -1)
            [[ "$resolved_google" != "$expected_ip" || "$resolved_cloudflare" != "$expected_ip" ]] && a_ok=false
        fi

        if [[ -n "$expected_ip6" ]]; then
            resolved6_google=$(dig +short "$domain" AAAA @8.8.8.8 2>/dev/null | head -1)
            resolved6_cloudflare=$(dig +short "$domain" AAAA @1.1.1.1 2>/dev/null | head -1)
            [[ "$resolved6_google" != "$expected_ip6" || "$resolved6_cloudflare" != "$expected_ip6" ]] && ip6_ok=false
        fi

        if [[ "$a_ok" == "true" && "$ip6_ok" == "true" ]]; then
            [[ -n "$expected_ip" ]]  && info "DNS A    记录已全球生效: ${domain} -> ${expected_ip}"
            [[ -n "$expected_ip6" ]] && info "DNS AAAA 记录已全球生效: ${domain} -> ${expected_ip6}"
            return 0
        fi

        local status_msg="等待中..."
        [[ -n "$expected_ip" ]]  && status_msg+=" A: Google=${resolved_google:-无} CF=${resolved_cloudflare:-无}"
        [[ -n "$expected_ip6" ]] && status_msg+=" AAAA: Google=${resolved6_google:-无} CF=${resolved6_cloudflare:-无}"
        echo -e "  ${YELLOW}${status_msg} (已等待 ${elapsed}s)${NC}"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    warn "DNS 在 ${max_wait}s 内未完全生效"
    if [[ -n "$expected_ip" ]]; then
        warn "  A    Google DNS: $(dig +short "$domain" A    @8.8.8.8 2>/dev/null | head -1 || echo 无) | CF: $(dig +short "$domain" A    @1.1.1.1 2>/dev/null | head -1 || echo 无) | 期望: ${expected_ip}"
    fi
    if [[ -n "$expected_ip6" ]]; then
        warn "  AAAA Google DNS: $(dig +short "$domain" AAAA @8.8.8.8 2>/dev/null | head -1 || echo 无) | CF: $(dig +short "$domain" AAAA @1.1.1.1 2>/dev/null | head -1 || echo 无) | 期望: ${expected_ip6}"
    fi
    read -rp "是否继续? (y/n): " CONT
    if [[ "$CONT" != "y" && "$CONT" != "Y" ]]; then error "已取消, 请等 DNS 生效后重新运行"; fi
}

# ============================================================
#  新增一个 IPv6-only 域名 (复用现有 V2Ray 服务)
# ============================================================
add_ipv6_only() {
    check_root
    check_os

    echo ""
    echo -e "${CYAN}========== 新增 IPv6-only 域名 ==========${NC}"
    echo ""

    # 1. 检测服务器 IPv6
    info "检测服务器公网 IPv6 地址..."
    local server_ip6
    server_ip6=$(get_server_ipv6)
    if [[ -z "$server_ip6" ]]; then
        error "未检测到公网 IPv6 地址, 请确认服务器已分配 IPv6"
    fi
    info "服务器 IPv6: ${server_ip6}"

    # 2. 读取现有 V2Ray 配置 (复用 port / ws_path / uuid)
    if [[ ! -f /usr/local/etc/v2ray/config.json ]]; then
        error "未找到 V2Ray 配置文件, 请先运行 install"
    fi
    local v2ray_port ws_path uuid
    v2ray_port=$(grep -oP '"port"\s*:\s*\K\d+' /usr/local/etc/v2ray/config.json 2>/dev/null || echo "")
    ws_path=$(grep -oP '"path"\s*:\s*"\K[^"]+' /usr/local/etc/v2ray/config.json 2>/dev/null || echo "")
    uuid=$(grep -oP '"id"\s*:\s*"\K[^"]+' /usr/local/etc/v2ray/config.json 2>/dev/null || echo "")
    if [[ -z "$v2ray_port" || -z "$ws_path" || -z "$uuid" ]]; then
        error "无法从 V2Ray 配置中读取端口/路径/UUID, 请检查 /usr/local/etc/v2ray/config.json"
    fi
    info "复用现有 V2Ray: port=${v2ray_port}, ws_path=${ws_path}"

    # 3. 收集输入
    local new_domain email
    read -rp "请输入新的 IPv6-only 域名 (如 dev6.example.com): " new_domain
    [[ -z "$new_domain" ]] && error "域名不能为空"
    read -rp "请输入证书邮箱 (Let's Encrypt 通知): " email
    [[ -z "$email" ]] && error "邮箱不能为空"

    echo ""
    echo -e "  新域名:         ${GREEN}${new_domain}${NC}"
    echo -e "  AAAA 目标:      ${GREEN}${server_ip6}${NC}"
    echo -e "  V2Ray 端口:     ${GREEN}${v2ray_port}${NC} ${YELLOW}(复用)${NC}"
    echo -e "  WebSocket 路径: ${GREEN}${ws_path}${NC} ${YELLOW}(复用)${NC}"
    echo -e "  UUID:           ${GREEN}${uuid}${NC} ${YELLOW}(复用)${NC}"
    echo -e "  证书邮箱:       ${GREEN}${email}${NC}"
    echo ""
    read -rp "确认以上信息? (y/n): " CONFIRM
    [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && error "已取消"

    # 4. AAAA 记录 — 由用户确认是否自动写入, 否则直接跳到证书步骤
    echo ""
    echo -e "${CYAN}--- DNS AAAA 记录 ---${NC}"
    echo -e "  ${new_domain} → AAAA → ${server_ip6}"
    echo ""
    read -rp "是否通过 GoDaddy API 自动新增/修改 AAAA 记录? (y=自动, n=跳过): " USE_GODADDY
    if [[ "$USE_GODADDY" == "y" || "$USE_GODADDY" == "Y" ]]; then
        setup_godaddy_dns "$new_domain" "" "$server_ip6"
        if ! command -v dig &>/dev/null; then
            apt install -y dnsutils 2>/dev/null || true
        fi
        wait_for_dns "$new_domain" "" "$server_ip6"
    else
        warn "已跳过 DNS 自动设置, 假定 ${new_domain} 的 AAAA 记录已指向 ${server_ip6}"
        warn "若 AAAA 未生效则下一步 certbot 申请会失败, 建议先验证:"
        warn "  dig AAAA ${new_domain} @8.8.8.8"
    fi

    # 5. 站点目录
    info "创建站点目录..."
    mkdir -p /var/www/${new_domain}
    if [[ ! -f /var/www/${new_domain}/index.html ]]; then
        cat > /var/www/${new_domain}/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>Welcome</title></head>
<body><h1>Welcome to My Site</h1><p>The site is under construction.</p></body>
</html>
HTMLEOF
    fi

    # 6. nginx 配置 (仅 IPv6 监听, 不影响其它域名的 IPv4 监听)
    info "写入 IPv6-only Nginx 配置..."
    cat > /etc/nginx/sites-available/${new_domain} <<NEOF
server {
    listen [::]:80;
    server_name ${new_domain};

    root /var/www/${new_domain};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ${ws_path} {
        if (\$http_upgrade != "websocket") {
            return 404;
        }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${v2ray_port};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NEOF

    ln -sf /etc/nginx/sites-available/${new_domain} /etc/nginx/sites-enabled/${new_domain}
    nginx -t || error "Nginx 配置检测失败"
    systemctl reload nginx
    info "Nginx 已重载"

    # 7. 证书 (certbot --nginx 会自动追加 listen [::]:443 ssl;)
    install_cert "$new_domain" "$email"

    # 8. 客户端配置
    info "为新域名生成客户端配置..."
    generate_client_configs "$new_domain" "$uuid" "$ws_path"

    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  IPv6-only 域名添加完成!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "  域名:   ${GREEN}${new_domain}${NC} (仅 IPv6 可达)"
    echo -e "  访问:   ${GREEN}https://${new_domain}${NC}"
    echo ""
    warn "注意: IPv4-only 客户端无法访问此域名 (DNS 无 A 记录)"
    warn "V2Ray 服务未变, 客户端仍使用同一 UUID/路径, 仅切换地址即可"
}

# ============================================================
#  为已有 IPv4 域名单独添加 IPv6 支持
# ============================================================
add_ipv6() {
    check_root
    check_os

    echo ""
    echo -e "${CYAN}========== 为已有域名添加 IPv6 支持 ==========${NC}"
    echo ""

    # 1. 检测服务器 IPv6
    info "检测服务器公网 IPv6 地址..."
    local server_ip6
    server_ip6=$(get_server_ipv6)
    if [[ -z "$server_ip6" ]]; then
        error "未检测到公网 IPv6 地址，请确认服务器已分配 IPv6 并连通外网"
    fi
    info "检测到公网 IPv6: ${server_ip6}"

    # 2. 确认域名
    local domain
    domain=$(grep -m1 'server_name' /etc/nginx/sites-enabled/default 2>/dev/null | awk '{print $2}' | tr -d ';')
    if [[ -n "$domain" ]]; then
        echo -e "检测到当前域名: ${GREEN}${domain}${NC}"
        read -rp "使用此域名? (直接回车确认, 输入新域名则覆盖): " INPUT_DOMAIN
        [[ -n "$INPUT_DOMAIN" ]] && domain="$INPUT_DOMAIN"
    else
        read -rp "请输入已部署好的域名: " domain
    fi
    if [[ -z "$domain" ]]; then error "域名不能为空"; fi

    echo ""
    echo -e "  域名:   ${GREEN}${domain}${NC}"
    echo -e "  IPv6:   ${GREEN}${server_ip6}${NC}"
    echo ""
    read -rp "确认为以上域名添加 IPv6 支持? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then error "已取消"; fi

    # 3. 更新 Nginx 配置 — 插入 listen [::]:PORT 指令
    local nginx_conf
    nginx_conf=$(readlink -f /etc/nginx/sites-enabled/default 2>/dev/null || true)
    if [[ -z "$nginx_conf" || ! -f "$nginx_conf" ]]; then
        nginx_conf="/etc/nginx/sites-available/${domain}"
    fi
    if [[ ! -f "$nginx_conf" ]]; then
        error "未找到 Nginx 配置文件 (${nginx_conf}), 请手动检查"
    fi
    info "Nginx 配置文件: ${nginx_conf}"

    if grep -q 'listen \[::\]' "$nginx_conf"; then
        warn "Nginx 配置已含 IPv6 listen 指令, 跳过此步骤"
    else
        local backup="${nginx_conf}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$nginx_conf" "$backup"
        info "已备份原配置: ${backup}"

        # 对每条 "listen PORT[...];" 行, 在其后追加对应的 "listen [::]:PORT[..."];" 行
        # sed 逻辑: 匹配 IPv4 listen 行 → p 打印原行 → s 变换为 IPv6 行 → 默认打印变换结果
        sed -i -E '/^[[:space:]]*listen [0-9]+/ {
            p
            s/^([[:space:]]*)listen ([0-9]+)(.*)/\1listen [::]:\2\3/
        }' "$nginx_conf"

        info "已插入 IPv6 listen 指令"
    fi

    nginx -t || error "Nginx 配置检测失败, 请手动检查 ${nginx_conf} (备份: ${nginx_conf}.bak.*)"
    systemctl reload nginx
    info "Nginx 已重载"

    # 4. DNS AAAA 记录
    echo ""
    echo -e "${CYAN}--- DNS AAAA 记录 ---${NC}"
    echo -e "需要为 ${GREEN}${domain}${NC} 添加 AAAA 记录 -> ${GREEN}${server_ip6}${NC}"
    echo ""
    read -rp "是否通过 GoDaddy API 自动设置 AAAA 记录? (y/n): " USE_GODADDY
    if [[ "$USE_GODADDY" == "y" || "$USE_GODADDY" == "Y" ]]; then
        setup_godaddy_dns "$domain" "" "$server_ip6"
        if ! command -v dig &>/dev/null; then
            apt install -y dnsutils 2>/dev/null || true
        fi
        wait_for_dns "$domain" "" "$server_ip6"
    else
        echo ""
        info "请在 DNS 控制台手动添加以下记录:"
        echo -e "  域名:   ${GREEN}${domain}${NC}"
        echo -e "  类型:   ${GREEN}AAAA${NC}"
        echo -e "  值:     ${GREEN}${server_ip6}${NC}"
        echo ""
        info "添加后可用以下命令验证生效:"
        echo -e "  dig AAAA ${domain} @8.8.8.8"
        echo -e "  dig AAAA ${domain} @1.1.1.1"
    fi

    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  IPv6 支持添加完成!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    show_info
}

# ============================================================
#  完整安装流程 (不含 DNS)
# ============================================================
full_install() {
    check_root
    check_os
    collect_input

    echo ""
    echo -e "${CYAN}[步骤 1/7] 安装 V2Ray${NC}"
    install_v2ray

    echo ""
    echo -e "${CYAN}[步骤 2/7] 配置 V2Ray${NC}"
    configure_v2ray

    echo ""
    echo -e "${CYAN}[步骤 3/7] 安装 Nginx 并部署 Web 站点${NC}"
    install_nginx

    echo ""
    echo -e "${CYAN}[步骤 4/7] 配置 Nginx${NC}"
    configure_nginx

    echo ""
    echo -e "${CYAN}[步骤 5/7] 配置防火墙${NC}"
    setup_firewall

    echo ""
    echo -e "${CYAN}[步骤 6/7] 申请并安装 TLS 证书${NC}"
    install_cert "$DOMAIN" "$CERT_EMAIL"

    echo ""
    echo -e "${CYAN}[步骤 7/7] 生成客户端配置文件${NC}"
    generate_client_configs "$DOMAIN" "$USER_UUID" "$WS_PATH"

    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  全部部署完成!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    show_info
    echo -e "${YELLOW}提示: 请确保域名 DNS A 记录已指向本服务器 IPv4 (见上方)${NC}"
    echo -e "${YELLOW}示例: ${DOMAIN} -> A 记录 -> 上方显示的 IPv4 地址${NC}"
    echo -e "${YELLOW}如服务器有 IPv6, 还需添加 AAAA 记录: ${DOMAIN} -> AAAA 记录 -> 上方显示的 IPv6 地址${NC}"
}

# ============================================================
#  完全版安装流程 (含 GoDaddy DNS 设置)
# ============================================================
full_install_with_dns() {
    check_root
    check_os
    collect_input

    # 获取本机 IP (IPv4 + 可选 IPv6)
    info "获取服务器公网 IP..."
    local server_ip server_ip6
    server_ip=$(get_server_ip)
    if [[ -z "$server_ip" ]]; then error "无法获取服务器公网 IP, 请检查网络"; fi
    info "服务器 IPv4: ${server_ip}"

    server_ip6=$(get_server_ipv6)
    if [[ -n "$server_ip6" ]]; then
        info "服务器 IPv6: ${server_ip6} (将同时设置 AAAA 记录)"
    else
        info "未检测到公网 IPv6 地址, 跳过 AAAA 记录设置"
    fi

    echo ""
    echo -e "${CYAN}[步骤 1/9] 安装 V2Ray${NC}"
    install_v2ray

    echo ""
    echo -e "${CYAN}[步骤 2/9] 配置 V2Ray${NC}"
    configure_v2ray

    echo ""
    echo -e "${CYAN}[步骤 3/9] 安装 Nginx 并部署 Web 站点${NC}"
    install_nginx

    echo ""
    echo -e "${CYAN}[步骤 4/9] 配置 Nginx${NC}"
    configure_nginx

    echo ""
    echo -e "${CYAN}[步骤 5/9] 配置防火墙${NC}"
    setup_firewall

    echo ""
    echo -e "${CYAN}[步骤 6/9] 设置 GoDaddy DNS${NC}"
    setup_godaddy_dns "$DOMAIN" "$server_ip" "$server_ip6"

    echo ""
    echo -e "${CYAN}[步骤 7/9] 等待 DNS 生效${NC}"
    # 安装 dig (如果没有)
    if ! command -v dig &>/dev/null; then
        apt install -y dnsutils 2>/dev/null || true
    fi
    wait_for_dns "$DOMAIN" "$server_ip" "$server_ip6"

    echo ""
    echo -e "${CYAN}[步骤 8/9] 申请并安装 TLS 证书${NC}"
    install_cert "$DOMAIN" "$CERT_EMAIL"

    echo ""
    echo -e "${CYAN}[步骤 9/9] 生成客户端配置文件${NC}"
    generate_client_configs "$DOMAIN" "$USER_UUID" "$WS_PATH"

    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  全部部署完成 (含 DNS)!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    show_info
}

# ============================================================
#  主入口
# ============================================================
usage() {
    echo ""
    echo "用法: bash $0 <命令>"
    echo ""
    echo "命令:"
    echo "  install         部署 V2Ray + WS + TLS + Web (DNS 需自行配置)"
    echo "  full            完全版部署, 含自动设置 GoDaddy DNS (A + AAAA)"
    echo "  add-ipv6        为已有 IPv4 域名补充 IPv6 (双栈)"
    echo "  add-ipv6-only   新增一个仅 IPv6 解析的域名 (复用现有 V2Ray)"
    echo "  change-domain   仅更换域名并重新申请证书"
    echo "  info            查看当前配置信息"
    echo ""
    echo "说明:"
    echo "  install        适用于已手动配好 DNS 的场景"
    echo "  full           一站式部署, 自动调用 godaddy-dns.sh 设置 A/AAAA 记录并等待生效"
    echo "                 需要 godaddy-dns.sh 在同一目录下且已配置好 API 凭证"
    echo "  add-ipv6       服务器已有 V2Ray + Nginx + 证书, 补充 IPv6 listen 指令及 AAAA 记录"
    echo "  add-ipv6-only  新域名仅写 AAAA 记录, nginx 仅 [::] 监听, 复用现有 V2Ray 端口/UUID/路径"
    echo "                 AAAA 记录可选自动写入或跳过 (假定已手动配置)"
    echo ""
}

case "${1:-}" in
    install)
        full_install
        ;;
    full)
        full_install_with_dns
        ;;
    add-ipv6)
        add_ipv6
        ;;
    add-ipv6-only)
        add_ipv6_only
        ;;
    change-domain)
        check_root
        change_domain
        ;;
    info)
        show_info
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        ;;
esac
