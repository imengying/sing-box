#!/bin/bash

set -e

# === 检查 root 权限 ===
if [ "$(id -u)" != "0" ]; then
  echo "❌ 请使用 root 权限运行该脚本"
  exit 1
fi

# === 检测系统类型并安装依赖 ===
if [ -x "$(command -v apt)" ]; then
  PKG_MANAGER="apt"
  $PKG_MANAGER update -y
  $PKG_MANAGER install -y curl wget tar jq uuid-runtime
elif [ -x "$(command -v dnf)" ]; then
  PKG_MANAGER="dnf"
  $PKG_MANAGER install -y curl wget tar jq util-linux
elif [ -x "$(command -v yum)" ]; then
  PKG_MANAGER="yum"
  $PKG_MANAGER install -y curl wget tar jq util-linux
else
  echo "❌ 不支持的系统类型，未找到 apt/dnf/yum"
  exit 1
fi

# === 确定系统架构（映射为 sing-box 支持的架构名称） ===
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

# === 下载最新版本的 sing-box ===
VERSION_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
VERSION=${VERSION_TAG#v}
FILENAME="sing-box-${VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"

cd /usr/local/bin
curl -LO "$DOWNLOAD_URL"

# === 校验下载是否成功 ===
if [ ! -s "$FILENAME" ]; then
  echo "❌ 下载失败，文件为空或不存在，可能是网络问题或链接无效"
  exit 1
fi

tar -xzf "$FILENAME"
mv sing-box-${VERSION}-linux-${ARCH}/sing-box .
chmod +x sing-box
rm -rf sing-box-${VERSION}-linux-${ARCH} "$FILENAME"

# === 创建配置目录 ===
mkdir -p /etc/sing-box

# === 生成 Reality 密钥和 UUID ===
KEYS=$(/usr/local/bin/sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'PublicKey' | awk '{print $2}')
UUID=$(uuidgen)
PORT=$(( ( RANDOM % 64510 )  + 1025 ))

# === 写入配置文件 ===
cat > /etc/sing-box/config.json <<EOF
{
  "inbounds": [
    {
      "tag": "VLESS-REALITY-${PORT}.json",
      "type": "vless",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "flow": "xtls-rprx-vision",
          "uuid": "${UUID}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "updates.cdn-apple.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "updates.cdn-apple.com",
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
      "type": "direct"
    },
    {
      "tag": "public_key_${PUBLIC_KEY}",
      "type": "direct"
    }
  ]
}
EOF

# === 写入 systemd 启动文件 ===
cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=sing-box service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
User=nobody
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# === 启动服务 ===
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# === 自动获取公网 IP ===
DOMAIN_OR_IP=$(curl -s https://api64.ipify.org)
if [ -z "$DOMAIN_OR_IP" ]; then
  echo "⚠️ 无法自动检测公网 IP，请手动修改为你的服务器域名或 IP"
  DOMAIN_OR_IP="yourdomain.com"
fi

# === 输出链接信息 ===
VLESS_URL="vless://${UUID}@${DOMAIN_OR_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=updates.cdn-apple.com&fp=chrome&pbk=${PUBLIC_KEY}#VLESS-REALITY"

echo ""
echo "✅ sing-box 安装并运行成功！"
echo ""
echo "📌 请将以下 VLESS 链接导入到你的客户端："
echo "----------------------------------------------------------"
echo "$VLESS_URL"
echo "----------------------------------------------------------"
echo ""
echo "🔧 使用 systemctl 管理 sing-box："
echo "状态查看:  systemctl status sing-box"
echo "重启服务:  systemctl restart sing-box"
echo "停止服务:  systemctl stop sing-box"
