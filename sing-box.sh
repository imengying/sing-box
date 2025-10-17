#!/bin/sh
set -e

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "❌ 请使用 root 权限运行该脚本"
    exit 1
  fi
}

detect_system() {
  if command -v apk >/dev/null 2>&1; then
    echo "alpine"; return
  fi
  if [ -f /etc/os-release ] && grep -qi 'alpine' /etc/os-release; then
    echo "alpine"; return
  fi
  echo "default"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

get_service_type() {
  if command_exists systemctl; then echo "systemd"; return 0; fi
  if [ -f /etc/init.d/sing-box ]; then echo "openrc"; return 0; fi
  echo ""
}

restart_service() {
  stype="$(get_service_type)"
  case "$stype" in
    systemd)
      systemctl restart sing-box || return 1
      sleep 1
      systemctl is-active --quiet sing-box
      ;;
    openrc)
      rc-service sing-box restart || return 1
      rc-service sing-box status >/dev/null 2>&1
      ;;
    *) return 2 ;;
  esac
}

ensure_jq() {
  if command_exists jq; then return 0; fi
  if command_exists apk; then apk update >/dev/null 2>&1 || true; apk add jq >/dev/null 2>&1 || true; return 0; fi
  if command_exists apt-get; then apt-get update >/dev/null 2>&1 || true; apt-get install -y jq >/dev/null 2>&1 || true; return 0; fi
  if command_exists apt; then apt update >/dev/null 2>&1 || true; apt install -y jq >/dev/null 2>&1 || true; return 0; fi
  if command_exists dnf; then dnf makecache >/dev/null 2>&1 || true; dnf install -y jq >/dev/null 2>&1 || true; return 0; fi
}

ensure_curl() {
  if command_exists curl; then return 0; fi
  if command_exists apk; then apk update >/dev/null 2>&1 || true; apk add curl >/dev/null 2>&1 || true; return 0; fi
  if command_exists apt-get; then apt-get update >/dev/null 2>&1 || true; apt-get install -y curl >/dev/null 2>&1 || true; return 0; fi
  if command_exists apt; then apt update >/dev/null 2>&1 || true; apt install -y curl >/dev/null 2>&1 || true; return 0; fi
  if command_exists dnf; then dnf makecache >/dev/null 2>&1 || true; dnf install -y curl >/dev/null 2>&1 || true; return 0; fi
}

run_config() {
  sys="$(detect_system)"
  echo "🧭 系统识别: ${sys}"
  echo "---------------------------------------"
  printf "🔢 请输入本地监听端口（留空则随机 1025–65535）: "
  read -r INPUT_PORT
  echo "🛠️ 正在执行配置..."

  if [ "$sys" = "alpine" ]; then
    SBX_PORT="$INPUT_PORT" sh -s <<'SBX_ALPINE_EOF'
set -e
INSTALL_DIR="/etc/sing-box"
SNI="updates.cdn-apple.com"

if [ "$(id -u)" != "0" ]; then echo "❌ 请使用 root 权限运行该脚本"; exit 1; fi

if [ -f /etc/init.d/sing-box ]; then
  echo "⚠️ sing-box 服务已存在，是否继续安装？[y/N]"
  read -r choice
  [ "$choice" != "y" ] && [ "$choice" != "Y" ] && exit 0
fi

apk update
apk add curl jq tar util-linux

for cmd in curl jq tar uuidgen; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ 缺少必要命令: $cmd"; exit 1; }
done

UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  x86_64) ARCH="amd64" ;;
  i386|i686) ARCH="386" ;;
  armv5*) ARCH="armv5" ;;
  armv6*) ARCH="armv6" ;;
  armv7l|armv7*) ARCH="armv7" ;;
  aarch64|arm64) ARCH="arm64" ;;
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

VERSION_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
VERSION=${VERSION_TAG#v}
FILENAME="sing-box-${VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
curl -LO "$DOWNLOAD_URL"
[ -s "$FILENAME" ] || { echo "❌ 下载失败，文件为空或不存在"; exit 1; }

tar -xzf "$FILENAME"
mv "sing-box-${VERSION}-linux-${ARCH}/sing-box" .
chmod +x sing-box
rm -rf "sing-box-${VERSION}-linux-${ARCH}" "$FILENAME"

KEYS=$("$INSTALL_DIR/sing-box" generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'PublicKey' | awk '{print $2}')
UUID=$(uuidgen)

PORT=""
if [ -n "$SBX_PORT" ]; then
  case "$SBX_PORT" in
    *[!0-9]*)
      echo "⚠️ 非法端口 \"$SBX_PORT\"，将随机分配。"
      ;;
    *)
      if [ "$SBX_PORT" -ge 1 ] && [ "$SBX_PORT" -le 65535 ]; then
        PORT="$SBX_PORT"
      else
        echo "⚠️ 端口超出范围(1–65535)，将随机分配。"
      fi
      ;;
  esac
fi
if [ -z "$PORT" ]; then
  rand_u16=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d " ")
  [ -z "$rand_u16" ] && rand_u16=$(date +%s)
  PORT=$((1025 + (rand_u16 % 64510)))
fi
echo "📍 使用端口: $PORT"

jq -n \
  --arg uuid "$UUID" \
  --arg private_key "$PRIVATE_KEY" \
  --arg sni "$SNI" \
  --arg listen "::" \
  --arg type "vless" \
  --arg tag "vless-reality" \
  --argjson port "$PORT" \
  '{
    "inbounds":[{"type":$type,"tag":$tag,"listen":$listen,"listen_port":$port,"users":[{"uuid":$uuid,"flow":"xtls-rprx-vision"}],"tls":{"enabled":true,"server_name":$sni,"reality":{"enabled":true,"handshake":{"server":$sni,"server_port":443},"private_key":$private_key}}}],
    "outbounds":[{"type":"direct","tag":"direct"}]
  }' > "$INSTALL_DIR/config.json"

cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
name="sing-box"
description="sing-box service"
command="${INSTALL_DIR}/sing-box"
command_args="run -c ${INSTALL_DIR}/config.json"
command_background="yes"
pidfile="/run/sing-box.pid"
start_stop_daemon_args="--make-pidfile --pidfile \${pidfile}"
depend(){ need net; }
EOF
chmod +x /etc/init.d/sing-box
rc-update add sing-box default
rc-service sing-box restart

DOMAIN_OR_IP=$(curl -s https://api64.ipify.org)
[ -z "$DOMAIN_OR_IP" ] && DOMAIN_OR_IP="yourdomain.com"
if echo "$DOMAIN_OR_IP" | grep -q ":"; then FORMATTED_IP="[$DOMAIN_OR_IP]"; else FORMATTED_IP="$DOMAIN_OR_IP"; fi
VLESS_URL="vless://${UUID}@${FORMATTED_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=firefox&pbk=${PUBLIC_KEY}#VLESS-REALITY"
printf '✅ sing-box 安装并运行成功！\n%s\n' "$VLESS_URL"
SBX_ALPINE_EOF
  else
    SBX_PORT="$INPUT_PORT" sh -s <<'SBX_DEFAULT_EOF'
set -e
INSTALL_DIR="/etc/sing-box"
SNI="updates.cdn-apple.com"

if [ "$(id -u)" != "0" ]; then echo "❌ 请使用 root 权限运行该脚本"; exit 1; fi

if [ -x "$(command -v apt-get)" ]; then
  PKG_MANAGER="apt-get"; INSTALL_CMD="apt-get install -y"; UPDATE_CMD="apt-get update"; DEP_PKGS="curl tar jq uuid-runtime"
elif [ -x "$(command -v dnf)" ]; then
  PKG_MANAGER="dnf"; INSTALL_CMD="dnf install -y"; UPDATE_CMD="dnf makecache"; DEP_PKGS="curl tar jq util-linux"
else
  echo "❌ 不支持的系统类型，未找到 apt-get/dnf"; exit 1
fi

echo "🔍 正在更新软件包索引..."
$UPDATE_CMD

for cmd in curl tar jq uuidgen; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "📦 安装缺失组件: $cmd"
    case "$cmd" in
      uuidgen) $INSTALL_CMD uuid-runtime || $INSTALL_CMD util-linux ;;
      curl|tar|jq) $INSTALL_CMD "$cmd" ;;
    esac
  fi
done

if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet sing-box; then
  read -r -p "⚠️ sing-box 服务已在运行，是否继续安装？[y/N] " choice
  [ "$choice" != "y" ] && [ "$choice" != "Y" ] && exit 0
fi

UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  x86_64) ARCH="amd64" ;;
  i386|i686) ARCH="386" ;;
  armv5*) ARCH="armv5" ;;
  armv6*) ARCH="armv6" ;;
  armv7*) ARCH="armv7" ;;
  armv8*|aarch64) ARCH="arm64" ;;
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

VERSION_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
VERSION=${VERSION_TAG#v}
FILENAME="sing-box-${VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
curl -LO "$DOWNLOAD_URL"
[ -s "$FILENAME" ] || { echo "❌ 下载失败，文件为空或不存在"; exit 1; }

tar -xzf "$FILENAME"
mv "sing-box-${VERSION}-linux-${ARCH}/sing-box" .
chmod +x sing-box
rm -rf "sing-box-${VERSION}-linux-${ARCH}" "$FILENAME"

KEYS=$("$INSTALL_DIR/sing-box" generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep 'PublicKey' | awk '{print $2}')
UUID=$(uuidgen)

PORT=""
if [ -n "$SBX_PORT" ]; then
  case "$SBX_PORT" in
    *[!0-9]*)
      echo "⚠️ 非法端口 \"$SBX_PORT\"，将随机分配。"
      ;;
    *)
      if [ "$SBX_PORT" -ge 1 ] && [ "$SBX_PORT" -le 65535 ]; then
        PORT="$SBX_PORT"
      else
        echo "⚠️ 端口超出范围(1–65535)，将随机分配。"
      fi
      ;;
  esac
fi
if [ -z "$PORT" ]; then
  rand_u16=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d " ")
  [ -z "$rand_u16" ] && rand_u16=$(date +%s)
  PORT=$((1025 + (rand_u16 % 64510)))
fi
echo "📍 使用端口: $PORT"

jq -n \
  --arg uuid "$UUID" \
  --arg private_key "$PRIVATE_KEY" \
  --arg sni "$SNI" \
  --arg listen "::" \
  --arg type "vless" \
  --arg tag "vless-reality" \
  --argjson port "$PORT" \
  '{
    inbounds:[{type:$type,tag:$tag,listen:$listen,listen_port:$port,users:[{uuid:$uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$private_key}}}],
    outbounds:[{type:"direct",tag:"direct"}]
  }' > "$INSTALL_DIR/config.json"

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

systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

DOMAIN_OR_IP=$(curl -s https://api64.ipify.org)
[ -z "$DOMAIN_OR_IP" ] && DOMAIN_OR_IP="yourdomain.com"
case "$DOMAIN_OR_IP" in *:*) FORMATTED_IP="[$DOMAIN_OR_IP]";; *) FORMATTED_IP="$DOMAIN_OR_IP";; esac
VLESS_URL="vless://${UUID}@${FORMATTED_IP}:${PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=firefox&pbk=${PUBLIC_KEY}#VLESS-REALITY"
printf '✅ sing-box 安装并运行成功！\n%s\n' "$VLESS_URL"
SBX_DEFAULT_EOF
  fi
}

run_update() {
  echo "⬆️  正在执行 sing-box 一键更新..."
  if ! command -v bash >/dev/null 2>&1; then
    if command -v apk >/dev/null 2>&1; then apk update >/dev/null 2>&1 || true; apk add bash >/dev/null 2>&1 || true
    elif command -v apt-get >/dev/null 2>&1; then apt-get update >/dev/null 2>&1 || true; apt-get install -y bash >/dev/null 2>&1 || true
    elif command -v dnf >/dev/null 2>&1; then dnf makecache >/dev/null 2>&1 || true; dnf install -y bash >/dev/null 2>&1 || true
    fi
  fi
  ensure_jq || true
  ensure_curl || true

  bash -s <<'SBX_UPDATE_EOF'
#!/bin/bash
set -e
INSTALL_DIR="/etc/sing-box"

if [ "$(id -u)" != "0" ]; then echo "❌ 请使用 root 权限运行该脚本"; exit 1; fi
if [ ! -f "$INSTALL_DIR/sing-box" ]; then echo "❌ 未找到 sing-box，请先安装"; exit 1; fi

if command -v systemctl >/dev/null 2>&1; then SERVICE_TYPE="systemd"
elif [ -f /etc/init.d/sing-box ]; then SERVICE_TYPE="openrc"
else echo "❌ 未找到 sing-box 服务配置"; exit 1
fi

CURRENT_VERSION=$("$INSTALL_DIR/sing-box" version 2>/dev/null | head -n1 | awk '{print $3}' || echo "unknown")
echo "📋 当前版本: $CURRENT_VERSION"
echo "🔍 正在检查最新版本..."
command -v jq >/dev/null 2>&1 || { echo "❌ 缺少 jq，请先安装 jq"; exit 1; }

VERSION_TAG=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name')
LATEST_VERSION=${VERSION_TAG#v}
[ -n "$VERSION_TAG" ] && [ "$VERSION_TAG" != "null" ] || { echo "❌ 无法获取最新版本信息"; exit 1; }
echo "📋 最新版本: $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then echo "✅ 已是最新版本，无需更新"; exit 0; fi
echo "🔄 发现新版本，准备更新..."

UNAME_ARCH=$(uname -m)
case "$UNAME_ARCH" in
  x86_64) ARCH="amd64" ;;
  i386|i686) ARCH="386" ;;
  armv5*) ARCH="armv5" ;;
  armv6*) ARCH="armv6" ;;
  armv7*) ARCH="armv7" ;;
  armv8*|aarch64) ARCH="arm64" ;;
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

echo "⏹️ 停止 sing-box 服务..."
case "$SERVICE_TYPE" in
  systemd) systemctl stop sing-box ;;
  openrc) rc-service sing-box stop ;;
esac

FILENAME="sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"

echo "⬇️ 下载新版本: $LATEST_VERSION"
cd /tmp
curl -LO "$DOWNLOAD_URL"
[ -s "$FILENAME" ] || {
  echo "❌ 下载失败，文件为空或不存在"
  echo "🔄 恢复服务..."
  case "$SERVICE_TYPE" in systemd) systemctl start sing-box ;; openrc) rc-service sing-box start ;; esac
  exit 1
}

echo "📦 解压并安装新版本..."
tar -xzf "$FILENAME"
cp "sing-box-${LATEST_VERSION}-linux-${ARCH}/sing-box" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/sing-box"
rm -rf "/tmp/sing-box-${LATEST_VERSION}-linux-${ARCH}" "/tmp/$FILENAME"

NEW_VERSION=$("$INSTALL_DIR/sing-box" version 2>/dev/null | head -n1 | awk '{print $3}' || echo "unknown")
if [ "$NEW_VERSION" != "$LATEST_VERSION" ]; then
  echo "❌ 版本验证失败，请检查安装过程"
  case "$SERVICE_TYPE" in systemd) systemctl start sing-box ;; openrc) rc-service sing-box start ;; esac
  exit 1
fi

echo "🚀 启动 sing-box 服务..."
case "$SERVICE_TYPE" in
  systemd)
    systemctl start sing-box
    sleep 2
    systemctl is-active --quiet sing-box && echo "✅ 服务启动成功" || { echo "❌ 服务启动失败"; systemctl status sing-box || true; exit 1; }
    ;;
  openrc)
    rc-service sing-box start
    sleep 2
    rc-service sing-box status >/dev/null 2>&1 && echo "✅ 服务启动成功" || { echo "❌ 服务启动失败"; rc-service sing-box status || true; exit 1; }
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

run_update_config() {
  echo "🛠️  正在更新配置（保留 UUID / 端口 / PublicKey）..."
  ensure_jq || true

  bash -s <<'SBX_UPDATE_CFG_EOF'
#!/bin/sh
set -e
INSTALL_DIR="/etc/sing-box"
CONFIG_FILE="$INSTALL_DIR/config.json"
SNI="updates.cdn-apple.com"

[ "$(id -u)" = "0" ] || { echo "❌ 请使用 root 权限运行该脚本"; exit 1; }
[ -f "$CONFIG_FILE" ] || { echo "❌ 未找到配置文件: $CONFIG_FILE"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "❌ 缺少 jq，请先安装 jq"; exit 1; }

UUID=$(jq -r '.inbounds[0].users[0].uuid // empty' "$CONFIG_FILE")
PORT=$(jq -r '.inbounds[0].listen_port // empty' "$CONFIG_FILE")
PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key // empty' "$CONFIG_FILE")
[ -n "$UUID" ] && [ -n "$PORT" ] && [ -n "$PRIVATE_KEY" ] || { echo "❌ 配置中缺少必要字段（uuid/port/private_key）"; exit 1; }

jq -n \
  --arg uuid "$UUID" \
  --arg private_key "$PRIVATE_KEY" \
  --arg sni "$SNI" \
  --arg listen "::" \
  --arg type "vless" \
  --arg tag "vless-reality" \
  --argjson port "$PORT" \
  '{
    inbounds:[{type:$type,tag:$tag,listen:$listen,listen_port:$port,users:[{uuid:$uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$private_key}}}],
    outbounds:[{type:"direct",tag:"direct"}]
  }' > "$CONFIG_FILE"

if command -v systemctl >/dev/null 2>&1 || [ -f /etc/init.d/sing-box ]; then :; else echo "⚠️ 未检测到服务管理器文件，已完成配置更新但未重启服务"; fi
echo "ℹ️ 已保持 UUID 与端口不变；由于沿用原 private_key，PublicKey 保持不变。"
SBX_UPDATE_CFG_EOF

  if restart_service; then
    echo "✅ 配置已更新并成功重启"
  else
    st=$?
    if [ "$st" -eq 2 ]; then
      echo "⚠️ 未检测到服务管理器，需手动重启 sing-box"
    else
      echo "❌ 服务重启失败，请检查状态"
    fi
  fi
}

main_menu() {
  echo "======================================="
  echo " sing-box 管理脚本"
  echo "======================================="
  echo "1 安装sing-box"
  echo "2 更新sing-box"
  echo "3 更新配置文件"
  echo "q 退出"
  echo "---------------------------------------"
  printf "请选择 [1/2/3/q]: "
  read -r choice
  case "$choice" in
    1) require_root; run_config ;;
    2) require_root; run_update ;;
    3) require_root; run_update_config ;;
    q|Q) echo "已退出。"; exit 0 ;;
    *) echo "无效选择"; exit 2 ;;
  esac
}

main_menu