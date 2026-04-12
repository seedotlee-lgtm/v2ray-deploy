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
    info "Nginx 配置完成并已启动"
}

# ============================================================
#  5. 防火墙放行端口
# ============================================================
setup_firewall() {
    if command -v ufw &>/dev/null; then
        info "配置 UFW 防火墙..."
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow ${V2RAY_PORT}/tcp
        ufw allow ${V2RAY_PORT}/udp
        ufw --force enable
        info "已放行 80, 443, ${V2RAY_PORT} 端口"
    else
        warn "未检测到 ufw, 请自行确保 80, 443, ${V2RAY_PORT} 端口已放行"
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

    info "域名更换完成!"
    echo ""
    show_info
    echo -e "${YELLOW}提示: 请确保新域名的 DNS A 记录已指向本服务器 IP${NC}"
    echo -e "${YELLOW}如使用 Cloudflare, 请在 Cloudflare 控制台更新 DNS 记录${NC}"
}

# ============================================================
#  显示当前配置信息
# ============================================================
show_info() {
    echo ""
    echo -e "${CYAN}========== 当前配置信息 ==========${NC}"

    # 获取本机公网 IP
    local server_ip
    server_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "获取失败")

    echo -e "  服务器公网 IP: ${GREEN}${server_ip}${NC}"
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
#  获取本机公网 IP
# ============================================================
get_server_ip() {
    local ip
    ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
         curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
    echo "$ip"
}

# ============================================================
#  通过 GoDaddy API 设置 DNS (需要 godaddy-dns.sh 在同目录)
# ============================================================
setup_godaddy_dns() {
    local domain="$1"
    local ip="$2"

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
        # 子域名: dev.example.com
        name=$(echo "$domain" | cut -d. -f1)
        main_domain=$(echo "$domain" | cut -d. -f2-)
    else
        # 主域名: example.com
        name="@"
        main_domain="$domain"
    fi

    echo ""
    echo -e "${CYAN}--- GoDaddy DNS 设置 ---${NC}"
    echo -e "  主域名:   ${GREEN}${main_domain}${NC}"
    echo -e "  记录名:   ${GREEN}${name}${NC}"
    echo -e "  记录类型: ${GREEN}A${NC}"
    echo -e "  记录值:   ${GREEN}${ip}${NC}"
    echo ""

    bash "$gdscript" set -d "$main_domain" -n "$name" -t A -v "$ip"
}

# ============================================================
#  等待 DNS 生效
# ============================================================
wait_for_dns() {
    local domain="$1"
    local expected_ip="$2"
    local max_wait=600  # 最长等 10 分钟
    local interval=15

    # 使用外部 DNS (Google 8.8.8.8 + Cloudflare 1.1.1.1) 检测, 更接近 Let's Encrypt 的解析结果
    info "等待 DNS 全球生效 (${domain} -> ${expected_ip}) ..."
    info "使用外部 DNS 服务器验证 (8.8.8.8, 1.1.1.1)"
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        local resolved_google resolved_cloudflare
        resolved_google=$(dig +short "$domain" A @8.8.8.8 2>/dev/null | head -1)
        resolved_cloudflare=$(dig +short "$domain" A @1.1.1.1 2>/dev/null | head -1)

        if [[ "$resolved_google" == "$expected_ip" && "$resolved_cloudflare" == "$expected_ip" ]]; then
            info "DNS 已全球生效: ${domain} -> ${expected_ip}"
            return 0
        fi
        echo -e "  ${YELLOW}等待中... Google DNS: ${resolved_google:-无}, Cloudflare DNS: ${resolved_cloudflare:-无} (已等待 ${elapsed}s)${NC}"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    local final_google final_cloudflare
    final_google=$(dig +short "$domain" A @8.8.8.8 2>/dev/null | head -1)
    final_cloudflare=$(dig +short "$domain" A @1.1.1.1 2>/dev/null | head -1)
    warn "DNS 在 ${max_wait}s 内未完全生效"
    warn "  Google DNS:     ${final_google:-无}"
    warn "  Cloudflare DNS: ${final_cloudflare:-无}"
    warn "  期望 IP:        ${expected_ip}"
    read -rp "是否继续? DNS 未生效时 certbot 会失败 (y/n): " CONT
    if [[ "$CONT" != "y" && "$CONT" != "Y" ]]; then error "已取消, 请等 DNS 生效后重新运行"; fi
}

# ============================================================
#  完整安装流程 (不含 DNS)
# ============================================================
full_install() {
    check_root
    check_os
    collect_input

    echo ""
    echo -e "${CYAN}[步骤 1/6] 安装 V2Ray${NC}"
    install_v2ray

    echo ""
    echo -e "${CYAN}[步骤 2/6] 配置 V2Ray${NC}"
    configure_v2ray

    echo ""
    echo -e "${CYAN}[步骤 3/6] 安装 Nginx 并部署 Web 站点${NC}"
    install_nginx

    echo ""
    echo -e "${CYAN}[步骤 4/6] 配置 Nginx${NC}"
    configure_nginx

    echo ""
    echo -e "${CYAN}[步骤 5/6] 配置防火墙${NC}"
    setup_firewall

    echo ""
    echo -e "${CYAN}[步骤 6/6] 申请并安装 TLS 证书${NC}"
    install_cert "$DOMAIN" "$CERT_EMAIL"

    echo ""
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}  全部部署完成!${NC}"
    echo -e "${GREEN}=====================================${NC}"
    show_info
    echo -e "${YELLOW}提示: 请确保域名 DNS A 记录已指向本服务器 IP (见上方)${NC}"
    echo -e "${YELLOW}示例: ${DOMAIN} -> A 记录 -> 上方显示的公网 IP${NC}"
}

# ============================================================
#  完全版安装流程 (含 GoDaddy DNS 设置)
# ============================================================
full_install_with_dns() {
    check_root
    check_os
    collect_input

    # 获取本机 IP
    info "获取服务器公网 IP..."
    local server_ip
    server_ip=$(get_server_ip)
    if [[ -z "$server_ip" ]]; then error "无法获取服务器公网 IP, 请检查网络"; fi
    info "服务器公网 IP: ${server_ip}"

    echo ""
    echo -e "${CYAN}[步骤 1/8] 安装 V2Ray${NC}"
    install_v2ray

    echo ""
    echo -e "${CYAN}[步骤 2/8] 配置 V2Ray${NC}"
    configure_v2ray

    echo ""
    echo -e "${CYAN}[步骤 3/8] 安装 Nginx 并部署 Web 站点${NC}"
    install_nginx

    echo ""
    echo -e "${CYAN}[步骤 4/8] 配置 Nginx${NC}"
    configure_nginx

    echo ""
    echo -e "${CYAN}[步骤 5/8] 配置防火墙${NC}"
    setup_firewall

    echo ""
    echo -e "${CYAN}[步骤 6/8] 设置 GoDaddy DNS${NC}"
    setup_godaddy_dns "$DOMAIN" "$server_ip"

    echo ""
    echo -e "${CYAN}[步骤 7/8] 等待 DNS 生效${NC}"
    # 安装 dig (如果没有)
    if ! command -v dig &>/dev/null; then
        apt install -y dnsutils 2>/dev/null || true
    fi
    wait_for_dns "$DOMAIN" "$server_ip"

    echo ""
    echo -e "${CYAN}[步骤 8/8] 申请并安装 TLS 证书${NC}"
    install_cert "$DOMAIN" "$CERT_EMAIL"

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
    echo "  install        部署 V2Ray + WS + TLS + Web (DNS 需自行配置)"
    echo "  full           完全版部署, 含自动设置 GoDaddy DNS"
    echo "  change-domain  仅更换域名并重新申请证书"
    echo "  info           查看当前配置信息"
    echo ""
    echo "说明:"
    echo "  install  适用于已手动配好 DNS 的场景"
    echo "  full     一站式部署, 自动调用 godaddy-dns.sh 设置 A 记录并等待生效"
    echo "           需要 godaddy-dns.sh 在同一目录下且已配置好 API 凭证"
    echo ""
}

case "${1:-}" in
    install)
        full_install
        ;;
    full)
        full_install_with_dns
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
