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

# === 更新软件包索引 ===
echo "🔍 正在更新软件包索引..."
apk update

# === 安装缺失组件（忽略 curl）===
for cmd in jq tar uuidgen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "📦 正在安装缺失命令: $cmd"
    case "$cmd" in
      uuidgen)
        apk add util-linux
        ;;
      *)
        apk add "$cmd"
        ;;
    esac
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

# === 使用 jq 生成配置文件 ===
jq -n --arg uuid "$UUID" --arg private_key "$PRIVATE_KEY" --arg sni "$SNI" --argjson port "$PORT" --arg public_key "$PUBLIC_KEY" '
{
  inbounds: [
    {
      tag: "VLESS-REALITY-\($port).json",
      type: "vless",
      listen: "::",
      listen_port: $port,
      users: [
        {
          flow: "xtls-rprx-vision",
          uuid: $uuid
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
          private_key: $private_key,
          short_id: [""]
        }
      }
    }
  ],
  outbounds: [
    { type: "direct" },
    {
      tag: "public_key_\($public_key)",
      type: "direct"
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

# === 获取公网 IP ===
DOMAIN_OR_IP=$(curl -s https://api64.ipify.org)
if [ -z "$DOMAIN_OR_IP" ]; then
  echo "⚠️ 无法自动检测公网 IP，请手动替换为你的域名或 IP"
  DOMAIN_OR_IP="yourdomain.com"
fi

# === 输出 VLESS 链接 ===
VLESS_URL="vless://${UUID}@${DOMAIN_OR_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PUBLIC_KEY}#VLESS-REALITY"

echo ""
echo "✅ sing-box 安装并运行成功！"
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
