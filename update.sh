#!/bin/bash

set -e

# === 基本设置 ===
INSTALL_DIR="/etc/sing-box"

# === 工具函数 ===
command_exists() { command -v "$1" >/dev/null 2>&1; }

safe_curl() {
  curl -fsSL --connect-timeout 10 --max-time 30 --retry 3 "$@"
}

# === 检查 root 权限 ===
if [ "$(id -u)" != "0" ]; then
  echo "❌ 请使用 root 权限运行该脚本"
  exit 1
fi

# === 检查 sing-box 是否存在 ===
if [ ! -f "$INSTALL_DIR/sing-box" ]; then
  echo "❌ 未找到 sing-box，请先使用 sing-box.sh 安装"
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
VERSION_TAG=$(
  safe_curl -H "Accept: application/vnd.github+json" -H "User-Agent: curl/8" \
    https://api.github.com/repos/SagerNet/sing-box/releases/latest \
    | jq -r '.tag_name // empty' 2>/dev/null
)
VERSION_TAG=$(printf "%s" "$VERSION_TAG" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

if [ -z "$VERSION_TAG" ] || [ "$VERSION_TAG" = "null" ]; then
  echo "❌ 无法获取最新版本信息，请检查网络连接或稍后重试"
  echo "💡 可能原因：网络问题、GitHub API限流、或防火墙拦截"
  exit 1
fi

LATEST_VERSION=${VERSION_TAG#v}

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
  armv7l | armv7*) ARCH="armv7" ;;
  armv8* | aarch64 | arm64) ARCH="arm64" ;;
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

# === 备份当前版本 ===
echo "💾 备份当前版本..."
BACKUP_DIR="$INSTALL_DIR/backup"
mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -f "$INSTALL_DIR/sing-box" ]; then
  cp "$INSTALL_DIR/sing-box" "$BACKUP_DIR/sing-box.${TIMESTAMP}.bak"
  echo "✅ 已备份到: $BACKUP_DIR/sing-box.${TIMESTAMP}.bak"
fi

if [ -f "$INSTALL_DIR/config.json" ]; then
  cp "$INSTALL_DIR/config.json" "$BACKUP_DIR/config.json.${TIMESTAMP}.bak"
  echo "✅ 已备份到: $BACKUP_DIR/config.json.${TIMESTAMP}.bak"
fi

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

if ! safe_curl -o "$FILENAME" "$DOWNLOAD_URL"; then
  echo "❌ 下载失败，请检查网络连接"
  echo "💡 下载地址: $DOWNLOAD_URL"
  echo "🔄 恢复服务..."
  case "$SERVICE_TYPE" in
    systemd) systemctl start sing-box ;;
    openrc) rc-service sing-box start ;;
  esac
  exit 1
fi

if [ ! -s "$FILENAME" ]; then
  echo "❌ 下载的文件为空或不存在"
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

# === 恢复文件权限 ===
echo "🔐 恢复文件权限..."
chown -R nobody:nogroup "$INSTALL_DIR" 2>/dev/null || \
chown -R nobody:nobody "$INSTALL_DIR" 2>/dev/null || true

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
