#!/bin/sh
# sbx.sh - 合并后的管理脚本（配置 / 更新）
# - 自动识别系统（Alpine 使用 apk，其它使用默认脚本）
# - 配置输出 fingerprint 改为 firefox
# - 提供两项操作：1) 配置  2) 更新

set -e

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "❌ 请使用 root 权限运行该脚本"
    exit 1
  fi
}

detect_system() {
  # 返回值：alpine 或 default
  if command -v apk >/dev/null 2>&1; then
    echo "alpine"
    return
  fi
  if [ -f /etc/os-release ] && grep -qi 'alpine' /etc/os-release; then
    echo "alpine"
    return
  fi
  echo "default"
}

run_config() {
  local sys="$(detect_system)"
  echo "🧭 系统识别: ${sys}"
  echo "🛠️ 正在执行配置..."
  if [ "$sys" = "alpine" ]; then
    # 执行合并后的 Alpine 配置脚本（已将 fingerprint 从 chrome 改为 firefox）
    sh -s <<'SBX_ALPINE_EOF'
#!/bin/sh

set -e

# === 基本设置 ===
INSTALL_DIR="/etc/sing-box"
SNI="updates.cdn-apple.com"
REALITY_DOMAIN="$SNI"

# === 检查 root 权限 ===
if [ "$(id -u)" != "0" ]; then
  echo "❌ 请使用 root 权限运行该脚本"
  exit 1
fi

# === 检查 sing-box 是否已存在 ===
if [ -f /etc/init.d/sing-box ]; then
  echo "⚠️ sing-box 服务已存在，是否继续安装？[y/N]"
  read -r choice
  [ "$choice" != "y" ] && [ "$choice" != "Y" ] && exit 0
fi

# === 安装依赖 ===
apk update
apk add curl jq tar util-linux

# === 检查必要命令 ===
for cmd in jq tar uuidgen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ 缺少必要命令: $cmd"
    exit 1
  fi
done

# === 检测系统架构 ===
UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  x86_64) ARCH="amd64" ;;
  i386 | i686) ARCH="386" ;;
  armv5*) ARCH="armv5" ;;
  armv6*) ARCH="armv6" ;;
  armv7l | armv7*) ARCH="armv7" ;;
  aarch64 | arm64) ARCH="arm64" ;;
  loongarch64) ARCH="loong64" ;;
  mips64el) ARCH="mips64le" ;;
  mips64) ARCH="mips64" ;;
  mipsel) ARCH="mipsle" ;;
  mips) ARCH="mips" ;;
  ppc64le) ARCH="ppc64le" ;;
  riscv64) ARCH="riscv64" ;;
  s390x) ARCH="s390x" ;;
  *) echo "❌ 不支持的架构: $UNAME_ARCH"; exit 1 ;;
esac

# === 下载 sing-box 最新版本 ===
VERSION_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
VERSION=${VERSION_TAG#v}
FILENAME="sing-box-${VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

curl -LO "$DOWNLOAD_URL"

if [ ! -s "$FILENAME" ]; then
  echo "❌ 下载失败，文件为空或不存在"
  exit 1
fi

tar -xzf "$FILENAME"
mv sing-box-${VERSION}-linux-${ARCH}/sing-box .
chmod +x sing-box
rm -rf sing-box-${VERSION}-linux-${ARCH} "$FILENAME"

# === 生成密钥与 UUID ===
KEYS=$("$INSTALL_DIR/sing-box" generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'PublicKey' | awk '{print $2}')
UUID=$(uuidgen)
PORT=$(( ( RANDOM % 64510 )  + 1025 ))

# === 使用 jq 生成结构化配置 ===
jq -n \
  --arg uuid "$UUID" \
  --arg private_key "$PRIVATE_KEY" \
  --arg sni "$SNI" \
  --arg listen "::" \
  --arg type "vless" \
  --arg tag "vless-reality" \
  --argjson port "$PORT" \
  '
{
  "inbounds": [
    {
      "type": $type,
      "tag": $tag,
      "listen": $listen,
      "listen_port": $port,
      "users": [
        {
          "uuid": $uuid,
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": $sni,
        "reality": {
          "enabled": true,
          "handshake": {
            "server": $sni,
            "server_port": 443
          },
          "private_key": $private_key
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
' > "$INSTALL_DIR/config.json"

# === 写入 OpenRC 启动脚本 ===
cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run

name="sing-box"
description="sing-box service"
command="${INSTALL_DIR}/sing-box"
command_args="run -c ${INSTALL_DIR}/config.json"
pidfile="/var/run/sing-box.pid"
command_background="yes"

depend() {
  need net
}
EOF

chmod +x /etc/init.d/sing-box
rc-update add sing-box default
rc-service sing-box restart

# === 获取公网 IP（支持 IPv6） ===
DOMAIN_OR_IP=$(curl -s https://api64.ipify.org)

if [ -z "$DOMAIN_OR_IP" ]; then
  echo "⚠️ 无法自动检测公网 IP，请手动替换为你的域名或 IP"
  DOMAIN_OR_IP="yourdomain.com"
fi

# === 检测 IPv6 并加上 [] ===
if echo "$DOMAIN_OR_IP" | grep -q ":"; then
  FORMATTED_IP="[${DOMAIN_OR_IP}]"
else
  FORMATTED_IP="$DOMAIN_OR_IP"
fi

# === 输出 VLESS 链接 ===
VLESS_URL="vless://${UUID}@${FORMATTED_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=firefox&pbk=${PUBLIC_KEY}#VLESS-REALITY"

echo ""
echo "✅ sing-box 安装并运行成功！"
echo ""
echo "📌 检测到公网 IP: $DOMAIN_OR_IP"
if echo "$DOMAIN_OR_IP" | grep -q ":"; then
  echo "🌐 类型: IPv6"
else
  echo "🌐 类型: IPv4"
fi
echo ""
echo "📌 请将以下 VLESS 链接导入客户端："
echo "----------------------------------------------------------"
echo "$VLESS_URL"
echo "----------------------------------------------------------"
echo ""
echo "🔧 使用 rc-service 管理 sing-box："
echo "状态查看:  rc-service sing-box status"
echo "重启服务:  rc-service sing-box restart"
echo "停止服务:  rc-service sing-box stop"

SBX_ALPINE_EOF
  else
    # 执行合并后的默认配置脚本（已将 fingerprint 从 chrome 改为 firefox）
    bash -s <<'SBX_DEFAULT_EOF'
#!/bin/sh

set -e

# === 基本设置 ===
INSTALL_DIR="/etc/sing-box"
SNI="updates.cdn-apple.com"
REALITY_DOMAIN="$SNI"

# === 检查 root 权限 ===
if [ "$(id -u)" != "0" ]; then
  echo "❌ 请使用 root 权限运行该脚本"
  exit 1
fi

# === 检测包管理器并定义安装命令 ===
if [ -x "$(command -v apt)" ]; then
  PKG_MANAGER="apt"
  INSTALL_CMD="apt install -y"
  UPDATE_CMD="apt update -y"
  DEP_PKGS=(tar jq uuid-runtime)
elif [ -x "$(command -v dnf)" ]; then
  PKG_MANAGER="dnf"
  INSTALL_CMD="dnf install -y"
  UPDATE_CMD="dnf makecache"
  DEP_PKGS=(tar jq util-linux)
else
  echo "❌ 不支持的系统类型，未找到 apt/dnf"
  exit 1
fi

# === 更新软件包索引 ===
echo "🔍 正在更新软件包索引..."
$UPDATE_CMD

# === 安装缺失依赖 ===
for cmd in tar jq uuidgen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "📦 安装缺失组件: $cmd"
    case "$cmd" in
      uuidgen)
        $INSTALL_CMD uuid-runtime || $INSTALL_CMD util-linux
        ;;
      *)
        $INSTALL_CMD "$cmd"
        ;;
    esac
  fi
done

# === 检查 sing-box 是否已运行 ===
if systemctl is-active --quiet sing-box; then
  read -r -p "⚠️ sing-box 服务已在运行，是否继续安装？[y/N] " choice
  [[ "$choice" != "y" && "$choice" != "Y" ]] && exit 0
fi

# === 检测系统架构 ===
UNAME_ARCH=$(uname -m)
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
  *)
    echo "❌ 不支持的架构: $UNAME_ARCH"
    exit 1
    ;;
esac

# === 下载 sing-box 最新版本 ===
VERSION_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
VERSION=${VERSION_TAG#v}
FILENAME="sing-box-${VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

curl -LO "$DOWNLOAD_URL"

if [ ! -s "$FILENAME" ]; then
  echo "❌ 下载失败，文件为空或不存在"
  exit 1
fi

tar -xzf "$FILENAME"
mv sing-box-${VERSION}-linux-${ARCH}/sing-box .
chmod +x sing-box
rm -rf sing-box-${VERSION}-linux-${ARCH} "$FILENAME"

# === 生成密钥与 UUID ===
KEYS=$("$INSTALL_DIR/sing-box" generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'PublicKey' | awk '{print $2}')
UUID=$(uuidgen)
PORT=$(( ( RANDOM % 64510 )  + 1025 ))

# === 使用 jq 生成配置文件 ===
jq -n \
  --arg uuid "$UUID" \
  --arg private_key "$PRIVATE_KEY" \
  --arg sni "$SNI" \
  --arg listen "::" \
  --arg type "vless" \
  --arg tag "vless-reality" \
  --argjson port "$PORT" \
  '
{
  inbounds: [
    {
      type: $type,
      tag: $tag,
      listen: $listen,
      listen_port: $port,
      users: [
        {
          uuid: $uuid,
          flow: "xtls-rprx-vision"
        }
      ],
      tls: {
        enabled: true,
        server_name: $sni,
        reality: {
          enabled: true,
          handshake: {
            server: $sni,
            server_port: 443
          },
          private_key: $private_key
        }
      }
    }
  ],
  outbounds: [
    {
      type: "direct",
      tag: "direct"
    }
  ]
}
' > "$INSTALL_DIR/config.json"

# === 写入 systemd 启动文件 ===
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=${INSTALL_DIR}/sing-box run -c ${INSTALL_DIR}/config.json
Restart=on-failure
User=nobody
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
ProtectControlGroups=true
ProtectKernelModules=true

[Install]
WantedBy=multi-user.target
EOF

# === 启动服务 ===
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# === 获取公网 IP（支持 IPv4 / IPv6） ===
DOMAIN_OR_IP=$(curl -s https://api64.ipify.org)

if [ -z "$DOMAIN_OR_IP" ]; then
  echo "⚠️ 无法自动检测公网 IP，请手动替换为你的域名或 IP"
  DOMAIN_OR_IP="yourdomain.com"
fi

# === 检测 IPv6 并加上 [] ===
if [[ "$DOMAIN_OR_IP" == *:* ]]; then
  # IPv6 地址检测（包含冒号）
  FORMATTED_IP="[${DOMAIN_OR_IP}]"
else
  FORMATTED_IP="$DOMAIN_OR_IP"
fi

# === 输出 VLESS 链接 ===
VLESS_URL="vless://${UUID}@${FORMATTED_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=firefox&pbk=${PUBLIC_KEY}#VLESS-REALITY"

echo ""
echo "✅ sing-box 安装并运行成功！"
echo ""
echo "📌 请将以下 VLESS 链接导入客户端："
echo "----------------------------------------------------------"
echo "$VLESS_URL"
echo "----------------------------------------------------------"
echo ""
echo "🔧 使用 systemctl 管理 sing-box："
echo "状态查看:  systemctl status sing-box"
echo "重启服务:  systemctl restart sing-box"
echo "停止服务:  systemctl stop sing-box"

SBX_DEFAULT_EOF
  fi
}


run_update() {
  echo "⬆️  正在执行 sing-box 一键更新..."
  # 确保 bash 可用（Alpine 可能默认没有 bash）
  if ! command -v bash >/dev/null 2>&1; then
    if command -v apk >/dev/null 2>&1; then
      echo "📦 正在安装 bash（Alpine）..."
      apk update && apk add bash
    fi
  fi
  bash -s <<'SBX_UPDATE_EOF'
#!/bin/bash

set -e

# === 基本设置 ===
INSTALL_DIR="/etc/sing-box"

# === 检查 root 权限 ===
if [ "$(id -u)" != "0" ]; then
  echo "❌ 请使用 root 权限运行该脚本"
  exit 1
fi

# === 检查 sing-box 是否存在 ===
if [ ! -f "$INSTALL_DIR/sing-box" ]; then
  echo "❌ 未找到 sing-box，请先安装"
  exit 1
fi

# === 检测系统类型和服务管理器 ===
if [ -f /etc/systemd/system/sing-box.service ]; then
  SERVICE_TYPE="systemd"
  SERVICE_CMD="systemctl"
elif [ -f /etc/init.d/sing-box ]; then
  SERVICE_TYPE="openrc"
  SERVICE_CMD="rc-service"
else
  echo "❌ 未找到 sing-box 服务配置"
  exit 1
fi

# === 获取当前版本 ===
CURRENT_VERSION=$("$INSTALL_DIR/sing-box" version 2>/dev/null | head -n1 | awk '{print $3}' || echo "unknown")
echo "📋 当前版本: $CURRENT_VERSION"

# === 获取最新版本 ===
echo "🔍 正在检查最新版本..."
VERSION_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
LATEST_VERSION=${VERSION_TAG#v}

if [ -z "$VERSION_TAG" ] || [ "$VERSION_TAG" = "null" ]; then
  echo "❌ 无法获取最新版本信息"
  exit 1
fi

echo "📋 最新版本: $LATEST_VERSION"

# === 版本比较 ===
if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
  echo "✅ 已是最新版本，无需更新"
  exit 0
fi

echo "🔄 发现新版本，准备更新..."

# === 检测系统架构 ===
UNAME_ARCH=$(uname -m)
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
  *)
    echo "❌ 不支持的架构: $UNAME_ARCH"
    exit 1
    ;;
esac

# === 停止服务 ===
echo "⏹️ 停止 sing-box 服务..."
case "$SERVICE_TYPE" in
  systemd)
    systemctl stop sing-box
    ;;
  openrc)
    rc-service sing-box stop
    ;;
esac

# === 下载新版本 ===
FILENAME="sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"

echo "⬇️ 下载新版本: $LATEST_VERSION"
cd /tmp
curl -LO "$DOWNLOAD_URL"

if [ ! -s "$FILENAME" ]; then
  echo "❌ 下载失败，文件为空或不存在"
  echo "🔄 恢复服务..."
  case "$SERVICE_TYPE" in
    systemd) systemctl start sing-box ;;
    openrc) rc-service sing-box start ;;
  esac
  exit 1
fi

# === 解压并替换 ===
echo "📦 解压并安装新版本..."
tar -xzf "$FILENAME"
cp "sing-box-${LATEST_VERSION}-linux-${ARCH}/sing-box" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/sing-box"

# === 清理临时文件 ===
rm -rf "/tmp/sing-box-${LATEST_VERSION}-linux-${ARCH}" "/tmp/$FILENAME"

# === 验证新版本 ===
NEW_VERSION=$("$INSTALL_DIR/sing-box" version 2>/dev/null | head -n1 | awk '{print $3}' || echo "unknown")
if [ "$NEW_VERSION" != "$LATEST_VERSION" ]; then
  echo "❌ 版本验证失败，请检查安装过程"
  case "$SERVICE_TYPE" in
    systemd) systemctl start sing-box ;;
    openrc) rc-service sing-box start ;;
  esac
  exit 1
fi

# === 启动服务 ===
echo "🚀 启动 sing-box 服务..."
case "$SERVICE_TYPE" in
  systemd)
    systemctl start sing-box
    sleep 2
    if systemctl is-active --quiet sing-box; then
      echo "✅ 服务启动成功"
    else
      echo "❌ 服务启动失败"
      systemctl status sing-box
      exit 1
    fi
    ;;
  openrc)
    rc-service sing-box start
    sleep 2
    if rc-service sing-box status >/dev/null 2>&1; then
      echo "✅ 服务启动成功"
    else
      echo "❌ 服务启动失败"
      rc-service sing-box status
      exit 1
    fi
    ;;
esac

echo ""
echo "🎉 sing-box 更新完成！"
echo "📋 版本: $CURRENT_VERSION → $LATEST_VERSION"
echo ""
echo "🔧 管理命令："
case "$SERVICE_TYPE" in
  systemd)
    echo "状态查看: systemctl status sing-box"
    echo "重启服务: systemctl restart sing-box"
    echo "查看日志: journalctl -u sing-box -f"
    ;;
  openrc)
    echo "状态查看: rc-service sing-box status"
    echo "重启服务: rc-service sing-box restart"
    ;;
esac

SBX_UPDATE_EOF
}


main_menu() {
  echo "======================================="
  echo " sing-box 管理脚本（合并版）"
  echo "======================================="
  echo "1) 配置（自动识别系统并安装/配置）"
  echo "2) 更新（保留配置并更新版本）"
  echo "q) 退出"
  echo "---------------------------------------"
  printf "请选择 [1/2/q]: "; read choice
  case "$choice" in
    1) require_root; run_config ;;
    2) require_root; run_update ;;
    q|Q) echo "已退出。"; exit 0 ;;
    *) echo "无效选择"; exit 2 ;;
  esac
}

main_menu
