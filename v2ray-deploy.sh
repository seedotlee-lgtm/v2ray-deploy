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
