#!/bin/bash

# --- 全局变量和彩色输出 ---
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_NC='\033[0m' # No Color

# 日志函数
info() { echo -e "${C_GREEN}[INFO]${C_NC} $1"; }
warn() { echo -e "${C_YELLOW}[WARN]${C_NC} $1"; }
error() { echo -e "${C_RED}[ERROR]${C_NC} $1"; exit 1; }

# --- 功能函数 ---

# 1. 检查运行环境
check_environment() {
    info "开始检查运行环境..."
    if [ "$(id -u)" != "0" ]; then
        error "请使用 root 权限运行该脚本。"
    fi
    if ! command -v systemctl &> /dev/null; then
        error "未找到 systemd，此脚本仅支持使用 systemd 的系统。"
    fi
    if ! command -v curl &> /dev/null; then
        error "核心命令 'curl' 未找到，请先安装 curl 后再运行此脚本。"
    fi
    info "环境检查通过。"
}

# 2. 安装依赖
install_dependencies() {
    info "正在检测包管理器并安装依赖..."
    local PKG_MANAGER=""
    local DEPS="tar jq"

    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
        DEPS+=" uuid-runtime"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        DEPS+=" util-linux"
    else
        error "不支持的系统类型，未找到 apt 或 dnf。"
    fi

    info "使用 $PKG_MANAGER 更新软件源并安装依赖: $DEPS"
    $PKG_MANAGER update -y
    if ! $PKG_MANAGER install -y $DEPS; then
        error "依赖安装失败，请检查您的网络或软件源配置。"
    fi

    for cmd in tar jq uuidgen; do
        if ! command -v $cmd &> /dev/null; then
            error "核心命令 '$cmd' 安装失败或未找到，脚本无法继续。"
        fi
    done
    info "依赖安装成功。"
}

# 3. 确定系统架构
detect_architecture() {
    local UNAME_ARCH
    UNAME_ARCH=$(uname -m)
    info "检测到系统架构: $UNAME_ARCH"

    case "$UNAME_ARCH" in
        x86_64) ARCH="amd64" ;;
        i386 | i686) ARCH="386" ;;
        armv5*) ARCH="armv5" ;;
        armv6*) ARCH="armv6" ;;
        armv7*) ARCH="armv7" ;;
        armv8* | aarch64) ARCH="arm64" ;;
        loongarch64) ARCH="loong64" ;;
        mips64el) ARCH="mips64le" ;;
        mips64) ARCH="mips64" ;;
        mipsel) ARCH="mipsle" ;;
        mips) ARCH="mips" ;;
        ppc64le) ARCH="ppc64le" ;;
        riscv64) ARCH="riscv64" ;;
        s390x) ARCH="s390x" ;;
        *) error "不支持的架构: $UNAME_ARCH" ;;
    esac
    info "映射为 sing-box 架构: $ARCH"
}

# 4. 下载并安装 sing-box
install_sing-box() {
    info "正在获取最新版本的 sing-box..."
    local TMP_DIR
    TMP_DIR=$(mktemp -d)
    trap 'rm -rf -- "$TMP_DIR"' EXIT

    local API_URL="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    local VERSION_TAG
    VERSION_TAG=$(curl -s -L "$API_URL" | jq -r '.tag_name')

    if [ -z "$VERSION_TAG" ]; then
        error "无法从 GitHub API 获取最新版本号，请检查网络或 API 速率限制。"
    fi

    local VERSION=${VERSION_TAG#v}
    local FILENAME="sing-box-${VERSION}-linux-${ARCH}.tar.gz"
    local DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"

    info "正在从以下地址下载 sing-box v${VERSION}:"
    echo -e "${C_BLUE}$DOWNLOAD_URL${C_NC}"

    if ! curl -L -o "$TMP_DIR/$FILENAME" "$DOWNLOAD_URL"; then
        error "下载失败，请检查网络连接或下载链接。"
    fi

    if [ ! -s "$TMP_DIR/$FILENAME" ]; then
        error "下载文件为空或不存在，安装中止。"
    fi
    info "下载成功，正在解压..."

    tar -xzf "$TMP_DIR/$FILENAME" -C "$TMP_DIR"
    local EXTRACTED_DIR="sing-box-${VERSION}-linux-${ARCH}"

    if [ ! -f "$TMP_DIR/$EXTRACTED_DIR/sing-box" ]; then
        error "解压失败或在解压文件中未找到 sing-box 执行文件。"
    fi

    mkdir -p /etc/sing-box
    install -m 755 "$TMP_DIR/$EXTRACTED_DIR/sing-box" /etc/sing-box/sing-box
    info "sing-box 已成功安装到 /etc/sing-box/sing-box"
}

# 5. 生成配置文件
generate_config() {
    info "正在生成 Reality 密钥对和配置文件..."
    local KEYS
    KEYS=$(/etc/sing-box/sing-box generate reality-keypair)
    local PRIVATE_KEY
    PRIVATE_KEY=$(echo "$KEYS" | awk '/PrivateKey/ {print $2}')
    local PUBLIC_KEY
    PUBLIC_KEY=$(echo "$KEYS" | awk '/PublicKey/ {print $2}')
    local UUID
    UUID=$(uuidgen)
    local PORT
    PORT=$((RANDOM % 55536 + 10000))
    local SNI_LIST=("www.apple.com" "www.bing.com" "www.microsoft.com" "updates.cdn-apple.com")
    local SERVER_NAME=${SNI_LIST[$RANDOM % ${#SNI_LIST[@]}]}

    info "使用端口: $PORT"
    info "使用 SNI: $SERVER_NAME"

    mkdir -p /etc/sing-box

    cat > /etc/sing-box/config.json <<EOF
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "uuid": "${UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "transport": {
        "type": "reality",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${SERVER_NAME}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [""]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
    CONFIG_PORT="$PORT"
    CONFIG_UUID="$UUID"
    CONFIG_PUBLIC_KEY="$PUBLIC_KEY"
    CONFIG_SERVER_NAME="$SERVER_NAME"

    info "配置文件已生成于 /etc/sing-box/config.json"
}

# 6. 设置并启动 systemd 服务
setup_systemd_service() {
    info "正在创建并配置 systemd 服务..."
    cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/etc/sing-box/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=10
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    info "正在重载 systemd 并启动 sing-box 服务..."
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box

    sleep 1

    if systemctl is-active --quiet sing-box; then
        info "sing-box 服务已成功启动并设置为开机自启。"
    else
        error "sing-box 服务启动失败，请运行 'journalctl -u sing-box' 查看日志。"
    fi
}

# 7. 显示配置信息
display_results() {
    info "正在获取公网 IP..."
    local PUBLIC_IP
    PUBLIC_IP=$(curl -s4 https://api.ipify.org) || PUBLIC_IP=$(curl -s6 https://api64.ipify.org)

    if [ -z "$PUBLIC_IP" ]; then
        warn "无法自动检测公网 IP，请手动替换下面的 [your_server_ip] 为你的服务器 IP 或域名。"
        PUBLIC_IP="[your_server_ip]"
    else
        info "检测到公网 IP: $PUBLIC_IP"
    fi

    local VLESS_URL="vless://${CONFIG_UUID}@${PUBLIC_IP}:${CONFIG_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${CONFIG_SERVER_NAME}&fp=chrome&pbk=${CONFIG_PUBLIC_KEY}#sing-box_reality"

    echo ""
    echo -e "${C_GREEN}✅ sing-box 安装并配置成功！${C_NC}"
    echo ""
    echo -e "${C_YELLOW}=============== 配置信息 ===============${C_NC}"
    echo -e "地址 (Address):      ${C_BLUE}${PUBLIC_IP}${C_NC}"
    echo -e "端口 (Port):         ${C_BLUE}${CONFIG_PORT}${C_NC}"
    echo -e "UUID:                ${C_BLUE}${CONFIG_UUID}${C_NC}"
    echo -e "流控 (Flow):         ${C_BLUE}xtls-rprx-vision${C_NC}"
    echo -e "加密 (Encryption):   ${C_BLUE}none${C_NC}"
    echo -e "安全 (Security):     ${C_BLUE}reality${C_NC}"
    echo -e "SNI:                 ${C_BLUE}${CONFIG_SERVER_NAME}${C_NC}"
    echo -e "公钥 (PublicKey):    ${C_BLUE}${CONFIG_PUBLIC_KEY}${C_NC}"
    echo -e "指纹 (Fingerprint):  ${C_BLUE}chrome${C_NC}"
    echo -e "${C_YELLOW}========================================${C_NC}"
    echo ""
    echo -e "${C_GREEN}分享链接 (VLESS URL):${C_NC}"
    echo -e "${C_BLUE}${VLESS_URL}${C_NC}"
    echo ""
    echo -e "${C_YELLOW}使用 systemctl 管理 sing-box:${C_NC}"
    echo "  - 查看状态: systemctl status sing-box"
    echo "  - 启动服务: systemctl start sing-box"
    echo "  - 停止服务: systemctl stop sing-box"
    echo "  - 重启服务: systemctl restart sing-box"
    echo "  - 查看日志: journalctl -u sing-box"
}

# --- 主函数 ---
main() {
    check_environment
    install_dependencies
    detect_architecture
    install_sing-box
    generate_config
    setup_systemd_service
    display_results
}

# --- 脚本入口 ---
main "$@"
