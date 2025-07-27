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
  $PKG_MANAGER install -y curl wget unzip jq uuid-runtime
elif [ -x "$(command -v dnf)" ]; then
  PKG_MANAGER="dnf"
  $PKG_MANAGER install -y curl wget unzip jq util-linux
elif [ -x "$(command -v yum)" ]; then
  PKG_MANAGER="yum"
  $PKG_MANAGER install -y curl wget unzip jq util-linux
else
  echo "❌ 不支持的系统类型，未找到 apt/dnf/yum"
  exit 1
fi

# === 确定系统架构 ===
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH="arm64"
else
  echo "❌ 不支持的架构: $ARCH"
  exit 1
fi

# === 下载最新版本的 sing-box ===
VERSION_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name') # v1.11.15
VERSION=${VERSION_TAG#v}  # 去掉 v，变成 1.11.15
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/sing-box-${VERSION}-linux-${ARCH}.zip"

cd /usr/local/bin
curl -LO "$DOWNLOAD_URL"

# === 验证 ZIP 文件有效性 ===
if ! file "sing-box-${VERSION}-linux-${ARCH}.zip" | grep -q "Zip archive data"; then
  echo "❌ 下载失败，文件不是有效的 ZIP 压缩包。请检查网络或链接是否正确。"
  exit 1
fi

unzip "sing-box-${VERSION}-linux-${ARCH}.zip"
mv sing-box-${VERSION}-linux-${ARCH}/sing-box .
chmod +x sing-box
rm -rf sing-box-${VERSION}-linux-${ARCH}*

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

# === 启动并启用服务 ===
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

# === 打印链接 ===
DOMAIN_OR_IP="yourdomain.com"  # <<< 请修改为你自己的域名或服务器IP

VLESS_URL="vless://${UUID}@${DOMAIN_OR_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=updates.cdn-apple.com&fp=chrome&pbk=${PUBLIC_KEY}#VLESS-REALITY"

echo ""
echo "✅ sing-box 安装并运行成功！"
echo ""
echo "📌 请将以下 VLESS 链接导入到你的客户端（替换域名）："
echo "----------------------------------------------------------"
echo "$VLESS_URL"
echo "----------------------------------------------------------"
echo ""
echo "🔧 使用 systemctl 管理 sing-box："
echo "状态查看:  systemctl status sing-box"
echo "重启服务:  systemctl restart sing-box"
echo "停止服务:  systemctl stop sing-box"
