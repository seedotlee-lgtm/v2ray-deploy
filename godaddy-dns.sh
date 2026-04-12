#!/bin/bash
#
# GoDaddy DNS 记录管理脚本
# 支持查询、新增、修改 DNS 记录 (A / AAAA / CNAME / TXT / MX 等)
#
# 用法:
#   bash godaddy-dns.sh                 交互模式
#   bash godaddy-dns.sh list            列出所有 DNS 记录
#   bash godaddy-dns.sh set             新增或修改记录 (交互)
#   bash godaddy-dns.sh set -d example.com -n www -t A -v 1.2.3.4   非交互模式
#

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

# ============================================================
#  配置文件 (保存 API Key, 避免每次输入)
# ============================================================
CONFIG_FILE="$HOME/.godaddy-dns.conf"
API_BASE="https://api.godaddy.com"

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
GODADDY_API_KEY="${GODADDY_API_KEY}"
GODADDY_API_SECRET="${GODADDY_API_SECRET}"
GODADDY_DOMAIN="${GODADDY_DOMAIN}"
EOF
    chmod 600 "$CONFIG_FILE"
    info "配置已保存到 ${CONFIG_FILE}"
}

# ============================================================
#  确保 API 凭证可用
# ============================================================
ensure_credentials() {
    load_config

    if [[ -z "$GODADDY_API_KEY" || -z "$GODADDY_API_SECRET" ]]; then
        echo ""
        echo -e "${CYAN}========== GoDaddy API 配置 ==========${NC}"
        echo -e "请到 ${CYAN}https://developer.godaddy.com/keys${NC} 获取 API Key"
        echo ""
        read -rp "API Key: " GODADDY_API_KEY
        if [[ -z "$GODADDY_API_KEY" ]]; then error "API Key 不能为空"; fi
        read -rp "API Secret: " GODADDY_API_SECRET
        if [[ -z "$GODADDY_API_SECRET" ]]; then error "API Secret 不能为空"; fi

        read -rp "默认域名 (可选, 直接回车跳过): " GODADDY_DOMAIN

        read -rp "是否保存配置以便下次使用? (y/n): " SAVE_CONF
        if [[ "$SAVE_CONF" == "y" || "$SAVE_CONF" == "Y" ]]; then
            save_config
        fi
    fi
}

# ============================================================
#  API 请求封装
# ============================================================
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local args=(
        -s -w "\n%{http_code}"
        -X "$method"
        -H "Authorization: sso-key ${GODADDY_API_KEY}:${GODADDY_API_SECRET}"
        -H "Content-Type: application/json"
    )
    if [[ -n "$data" ]]; then
        args+=(-d "$data")
    fi

    local response
    response=$(curl "${args[@]}" "${API_BASE}${endpoint}" 2>&1) || {
        echo -e "${RED}[API 错误] curl 请求失败, 请检查网络连接${NC}" >&2
        return 1
    }

    local http_code
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')

    # 检查 http_code 是否为有效数字
    if ! [[ "$http_code" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[API 错误] 无法获取 HTTP 状态码, 响应: ${response}${NC}" >&2
        return 1
    fi

    echo "$body"

    if [[ "$http_code" -ge 400 ]]; then
        local msg
        msg=$(echo "$body" | grep -oP '"message"\s*:\s*"\K[^"]+' 2>/dev/null || echo "未知错误")
        echo -e "${RED}[API 错误] HTTP ${http_code}: ${msg}${NC}" >&2
        return 1
    fi
}

# ============================================================
#  获取域名, 支持参数传入或交互输入
# ============================================================
get_domain() {
    local domain="$1"
    # 命令行 -d 传入了就直接用
    if [[ -n "$domain" ]]; then
        echo -e "${GREEN}[INFO]${NC} 使用域名: ${domain}" >&2
        echo "$domain"
        return
    fi
    # 交互询问, 有默认值时显示提示
    if [[ -n "$GODADDY_DOMAIN" ]]; then
        read -rp "请输入主域名 [回车使用 ${GODADDY_DOMAIN}]: " domain
        domain=${domain:-$GODADDY_DOMAIN}
    else
        read -rp "请输入主域名 (如 example.com): " domain
    fi
    if [[ -z "$domain" ]]; then error "域名不能为空"; fi
    echo "$domain"
}

# ============================================================
#  list: 列出 DNS 记录
# ============================================================
cmd_list() {
    ensure_credentials

    local domain type name
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain) domain="$2"; shift 2 ;;
            -t|--type)   type="$2"; shift 2 ;;
            -n|--name)   name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    domain=$(get_domain "$domain")

    local endpoint="/v1/domains/${domain}/records"
    if [[ -n "$type" && -n "$name" ]]; then
        endpoint="${endpoint}/${type}/${name}"
    elif [[ -n "$type" ]]; then
        endpoint="${endpoint}/${type}"
    fi

    info "查询 ${domain} 的 DNS 记录..."
    echo ""

    local result
    result=$(api_call GET "$endpoint") || error "查询失败"

    # 空结果检查
    if [[ -z "$result" || "$result" == "[]" ]]; then
        warn "未找到任何 DNS 记录"
        return
    fi

    # 检查是否有 jq
    if command -v jq &>/dev/null; then
        echo "$result" | jq -r '
            ["TYPE","NAME","VALUE","TTL"],
            (.[] | [.type, .name, .data, (.ttl|tostring)]) |
            @tsv
        ' 2>/dev/null | column -t -s $'\t' || {
            # jq 解析失败, 直接输出原始内容
            warn "格式化失败, 原始返回:"
            echo "$result"
        }
    else
        # 无 jq 时简单格式化输出
        echo "$result" | grep -oP '\{[^}]+\}' | while read -r record; do
            local rtype rname rdata rttl
            rtype=$(echo "$record" | grep -oP '"type"\s*:\s*"\K[^"]+')
            rname=$(echo "$record" | grep -oP '"name"\s*:\s*"\K[^"]+')
            rdata=$(echo "$record" | grep -oP '"data"\s*:\s*"\K[^"]+')
            rttl=$(echo "$record" | grep -oP '"ttl"\s*:\s*\K\d+')
            printf "%-8s %-20s %-40s TTL:%s\n" "$rtype" "$rname" "$rdata" "$rttl"
        done
    fi
    echo ""
}

# ============================================================
#  set: 新增或修改 DNS 记录
# ============================================================
cmd_set() {
    ensure_credentials

    local domain="" rec_type="" rec_name="" rec_value="" rec_ttl=""
    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain) domain="$2"; shift 2 ;;
            -t|--type)   rec_type="$2"; shift 2 ;;
            -n|--name)   rec_name="$2"; shift 2 ;;
            -v|--value)  rec_value="$2"; shift 2 ;;
            --ttl)       rec_ttl="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    domain=$(get_domain "$domain")

    # 交互补全缺失参数
    if [[ -z "$rec_name" ]]; then
        echo ""
        echo -e "${CYAN}支持的记录名称示例:${NC}"
        echo "  @     主域名本身 (example.com)"
        echo "  www   子域名 (www.example.com)"
        echo "  dev   子域名 (dev.example.com)"
        echo "  *     泛域名"
        echo ""
        read -rp "请输入记录名称 (如 @ / www / dev): " rec_name
    fi
    if [[ -z "$rec_name" ]]; then error "记录名称不能为空"; fi

    if [[ -z "$rec_type" ]]; then
        echo ""
        echo -e "${CYAN}支持的记录类型:${NC}  A | AAAA | CNAME | TXT | MX | NS | SRV"
        read -rp "请输入记录类型 [默认 A]: " rec_type
        rec_type=${rec_type:-A}
    fi
    rec_type=$(echo "$rec_type" | tr '[:lower:]' '[:upper:]')

    # 查询是否已有该记录
    info "查询现有记录 ${rec_type} ${rec_name}.${domain} ..."
    local existing
    existing=$(api_call GET "/v1/domains/${domain}/records/${rec_type}/${rec_name}" 2>/dev/null || echo "[]")

    local has_record="false"
    if echo "$existing" | grep -q '"data"'; then
        has_record="true"
        local old_value
        old_value=$(echo "$existing" | grep -oP '"data"\s*:\s*"\K[^"]+' | head -1)
        echo -e "  已有记录: ${YELLOW}${rec_type} ${rec_name} -> ${old_value}${NC}"
        echo -e "  操作类型: ${CYAN}修改${NC}"
    else
        echo -e "  未找到记录: ${rec_type} ${rec_name}"
        echo -e "  操作类型: ${CYAN}新增${NC}"
    fi

    if [[ -z "$rec_value" ]]; then
        echo ""
        case "$rec_type" in
            A)     echo -e "${CYAN}请输入 IPv4 地址${NC}" ;;
            AAAA)  echo -e "${CYAN}请输入 IPv6 地址${NC}" ;;
            CNAME) echo -e "${CYAN}请输入目标域名 (如 other.example.com)${NC}" ;;
            TXT)   echo -e "${CYAN}请输入 TXT 值${NC}" ;;
            MX)    echo -e "${CYAN}请输入邮件服务器域名${NC}" ;;
            *)     echo -e "${CYAN}请输入记录值${NC}" ;;
        esac

        # A 记录时提供自动检测当前服务器 IP
        if [[ "$rec_type" == "A" ]]; then
            local detected_ip
            detected_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
                          curl -s --max-time 5 https://ifconfig.me 2>/dev/null || echo "")
            if [[ -n "$detected_ip" ]]; then
                echo -e "  检测到当前服务器 IP: ${GREEN}${detected_ip}${NC}"
                read -rp "请输入记录值 (直接回车使用 ${detected_ip}): " rec_value
                rec_value=${rec_value:-$detected_ip}
            else
                read -rp "请输入记录值: " rec_value
            fi
        else
            read -rp "请输入记录值: " rec_value
        fi
    fi
    if [[ -z "$rec_value" ]]; then error "记录值不能为空"; fi

    if [[ -z "$rec_ttl" ]]; then
        read -rp "请输入 TTL 秒数 [默认 600]: " rec_ttl
        rec_ttl=${rec_ttl:-600}
    fi

    # 确认
    echo ""
    echo -e "${CYAN}========== 操作确认 ==========${NC}"
    echo -e "  域名:   ${GREEN}${domain}${NC}"
    echo -e "  类型:   ${GREEN}${rec_type}${NC}"
    echo -e "  名称:   ${GREEN}${rec_name}${NC}"
    echo -e "  值:     ${GREEN}${rec_value}${NC}"
    echo -e "  TTL:    ${GREEN}${rec_ttl}${NC}"
    if [[ "$has_record" == "true" ]]; then
        echo -e "  操作:   ${YELLOW}修改现有记录${NC}"
    else
        echo -e "  操作:   ${YELLOW}新增记录${NC}"
    fi
    echo ""
    read -rp "确认执行? (y/n): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then error "已取消"; fi

    local json_data="[{\"data\":\"${rec_value}\",\"ttl\":${rec_ttl}}]"

    if [[ "$has_record" == "true" ]]; then
        # 修改: PUT 替换
        info "修改记录 ${rec_type} ${rec_name}.${domain} -> ${rec_value} ..."
        api_call PUT "/v1/domains/${domain}/records/${rec_type}/${rec_name}" "$json_data" >/dev/null || error "修改失败"
    else
        # 新增: PATCH 追加
        local patch_data="[{\"type\":\"${rec_type}\",\"name\":\"${rec_name}\",\"data\":\"${rec_value}\",\"ttl\":${rec_ttl}}]"
        info "新增记录 ${rec_type} ${rec_name}.${domain} -> ${rec_value} ..."
        api_call PATCH "/v1/domains/${domain}/records" "$patch_data" >/dev/null || error "新增失败"
    fi

    info "操作成功!"
    echo ""

    # 验证结果
    info "验证记录..."
    local verify
    verify=$(api_call GET "/v1/domains/${domain}/records/${rec_type}/${rec_name}" 2>/dev/null || echo "")
    if echo "$verify" | grep -q "$rec_value"; then
        local current_value
        current_value=$(echo "$verify" | grep -oP '"data"\s*:\s*"\K[^"]+' | head -1)
        echo -e "  ${GREEN}${rec_type} ${rec_name}.${domain} -> ${current_value}${NC}"
    else
        warn "验证未通过, 请手动检查 (DNS 可能需要几分钟生效)"
    fi
    echo ""
}

# ============================================================
#  delete: 删除 DNS 记录
# ============================================================
cmd_delete() {
    ensure_credentials

    local domain="" rec_type="" rec_name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--domain) domain="$2"; shift 2 ;;
            -t|--type)   rec_type="$2"; shift 2 ;;
            -n|--name)   rec_name="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    domain=$(get_domain "$domain")

    if [[ -z "$rec_name" ]]; then
        read -rp "请输入要删除的记录名称 (如 @ / www / dev): " rec_name
    fi
    if [[ -z "$rec_name" ]]; then error "记录名称不能为空"; fi

    if [[ -z "$rec_type" ]]; then
        read -rp "请输入记录类型 [默认 A]: " rec_type
        rec_type=${rec_type:-A}
    fi
    rec_type=$(echo "$rec_type" | tr '[:lower:]' '[:upper:]')

    # 确认
    echo ""
    echo -e "${RED}即将删除: ${rec_type} ${rec_name}.${domain}${NC}"
    read -rp "确认删除? (输入 yes 确认): " CONFIRM
    if [[ "$CONFIRM" != "yes" ]]; then error "已取消"; fi

    info "删除记录..."
    api_call DELETE "/v1/domains/${domain}/records/${rec_type}/${rec_name}" >/dev/null || error "删除失败"
    info "删除成功!"
    echo ""
}

# ============================================================
#  config: 重新配置 API 凭证
# ============================================================
cmd_config() {
    load_config

    local subcmd="${1:-}"

    # bash godaddy-dns.sh config domain  —— 只改默认域名
    if [[ "$subcmd" == "domain" ]]; then
        echo ""
        if [[ -n "$GODADDY_DOMAIN" ]]; then
            echo -e "当前默认域名: ${YELLOW}${GODADDY_DOMAIN}${NC}"
        else
            echo -e "当前默认域名: ${YELLOW}未设置${NC}"
        fi
        read -rp "请输入新的默认域名: " GODADDY_DOMAIN
        if [[ -z "$GODADDY_DOMAIN" ]]; then error "域名不能为空"; fi
        save_config
        return
    fi

    # bash godaddy-dns.sh config  —— 完整配置
    echo ""
    echo -e "${CYAN}========== 配置 GoDaddy API 凭证 ==========${NC}"
    echo -e "获取地址: ${CYAN}https://developer.godaddy.com/keys${NC}"
    echo ""

    if [[ -n "$GODADDY_API_KEY" ]]; then
        local masked="${GODADDY_API_KEY:0:6}...${GODADDY_API_KEY: -4}"
        echo -e "当前 API Key:  ${YELLOW}${masked}${NC}"
        echo -e "当前默认域名: ${YELLOW}${GODADDY_DOMAIN:-未设置}${NC}"
        echo ""
    fi

    local new_key new_secret new_domain
    read -rp "API Key${GODADDY_API_KEY:+ [回车保持不变]}: " new_key
    read -rp "API Secret${GODADDY_API_SECRET:+ [回车保持不变]}: " new_secret
    read -rp "默认域名${GODADDY_DOMAIN:+ [回车保持 ${GODADDY_DOMAIN}]}: " new_domain

    if [[ -n "$new_key" ]]; then GODADDY_API_KEY="$new_key"; fi
    if [[ -n "$new_secret" ]]; then GODADDY_API_SECRET="$new_secret"; fi
    if [[ -n "$new_domain" ]]; then GODADDY_DOMAIN="$new_domain"; fi

    if [[ -z "$GODADDY_API_KEY" ]]; then error "API Key 不能为空"; fi
    if [[ -z "$GODADDY_API_SECRET" ]]; then error "API Secret 不能为空"; fi

    save_config
}

# ============================================================
#  主入口
# ============================================================
usage() {
    echo ""
    echo "用法: bash $0 <命令> [选项]"
    echo ""
    echo "命令:"
    echo "  list            列出 DNS 记录"
    echo "  set             新增或修改 DNS 记录"
    echo "  delete          删除 DNS 记录"
    echo "  config          配置 API 凭证 (已有配置时可回车保持不变)"
    echo "  config domain   仅修改默认域名"
    echo ""
    echo "选项:"
    echo "  -d, --domain   主域名 (如 example.com)"
    echo "  -n, --name     记录名称 (如 @ / www / dev)"
    echo "  -t, --type     记录类型 (默认 A, 可选 AAAA/CNAME/TXT/MX/NS/SRV)"
    echo "  -v, --value    记录值 (如 IP 地址)"
    echo "  --ttl          TTL 秒数 (默认 600)"
    echo ""
    echo "示例:"
    echo "  bash $0 list -d example.com"
    echo "  bash $0 list -d example.com -t A"
    echo "  bash $0 set -d example.com -n dev -t A -v 1.2.3.4"
    echo "  bash $0 set -d example.com -n @ -t CNAME -v other.com"
    echo "  bash $0 set    (交互模式)"
    echo "  bash $0 delete -d example.com -n old -t A"
    echo ""
}

case "${1:-}" in
    list)
        shift; cmd_list "$@"
        ;;
    set)
        shift; cmd_set "$@"
        ;;
    delete)
        shift; cmd_delete "$@"
        ;;
    config)
        shift; cmd_config "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        ;;
esac
