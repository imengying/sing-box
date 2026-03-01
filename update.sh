#!/bin/bash

set -e

# === 基本设置 ===
INSTALL_DIR="/etc/sing-box"

# === 工具函数 ===
command_exists() { command -v "$1" >/dev/null 2>&1; }

safe_curl() {
  curl -fsSL --connect-timeout 10 --max-time 300 --retry 3 "$@"
}

stop_service() {
  case "$SERVICE_TYPE" in
    systemd) systemctl stop sing-box ;;
    openrc) rc-service sing-box stop ;;
    *) return 1 ;;
  esac
}

start_service() {
  case "$SERVICE_TYPE" in
    systemd) systemctl start sing-box ;;
    openrc) rc-service sing-box start ;;
    *) return 1 ;;
  esac
}

is_service_active() {
  case "$SERVICE_TYPE" in
    systemd) systemctl is-active --quiet sing-box ;;
    openrc) rc-service sing-box status >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

binary_supports_check() {
  bin_path="$1"
  "$bin_path" help 2>/dev/null | grep -Eq '(^|[[:space:]])check([[:space:]]|$)'
}

validate_singbox_binary() {
  bin_path="$1"
  expected_version="$2"
  config_file="$INSTALL_DIR/config.json"

  detected_version=$("$bin_path" version 2>/dev/null | head -n1 | awk '{print $3}' || echo "unknown")
  if [ "$detected_version" != "$expected_version" ]; then
    echo "❌ 新程序版本校验失败：期望 $expected_version，实际 $detected_version"
    return 1
  fi

  if [ -f "$config_file" ] && binary_supports_check "$bin_path"; then
    if ! "$bin_path" check -c "$config_file" >/dev/null 2>&1; then
      echo "❌ 新程序配置校验失败，请检查: $config_file"
      return 1
    fi
  fi

  return 0
}

rollback_binary() {
  old_bin="$1"
  current_bin="$INSTALL_DIR/sing-box"

  [ -f "$current_bin" ] && rm -f "$current_bin"
  if [ ! -f "$old_bin" ]; then
    echo "❌ 回滚失败：未找到旧程序文件 $old_bin"
    return 1
  fi

  if ! mv "$old_bin" "$current_bin"; then
    echo "❌ 回滚失败：无法恢复旧程序文件"
    return 1
  fi

  chmod +x "$current_bin" 2>/dev/null || true
  chown -R nobody:nogroup "$INSTALL_DIR" 2>/dev/null || \
  chown -R nobody:nobody "$INSTALL_DIR" 2>/dev/null || true
  return 0
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

echo "⚠️  无备份模式：将直接替换程序文件，当前 config.json 保持不变"

# === 下载新版本 ===
FILENAME="sing-box-${LATEST_VERSION}-linux-${ARCH}.tar.gz"
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${VERSION_TAG}/${FILENAME}"
STAGE_DIR=$(mktemp -d /tmp/sing-box-update.XXXXXX)
STAGED_BIN="$STAGE_DIR/sing-box-${LATEST_VERSION}-linux-${ARCH}/sing-box"
NEW_BIN="$INSTALL_DIR/sing-box.new"
OLD_BIN="$INSTALL_DIR/sing-box.old"

trap 'rm -rf "$STAGE_DIR"' EXIT INT TERM

echo "⬇️ 下载并预校验新版本: $LATEST_VERSION"
if ! safe_curl -o "$STAGE_DIR/$FILENAME" "$DOWNLOAD_URL"; then
  echo "❌ 下载失败，请检查网络连接"
  echo "💡 下载地址: $DOWNLOAD_URL"
  echo "🔄 更新中止（当前服务保持运行）"
  exit 1
fi

if [ ! -s "$STAGE_DIR/$FILENAME" ]; then
  echo "❌ 下载的文件为空或不存在"
  echo "🔄 更新中止（当前服务保持运行）"
  exit 1
fi

echo "📦 解压并预校验新版本..."
if ! tar -xzf "$STAGE_DIR/$FILENAME" -C "$STAGE_DIR"; then
  echo "❌ 解压失败，更新中止（当前服务保持运行）"
  exit 1
fi

if [ ! -f "$STAGED_BIN" ]; then
  echo "❌ 新版本程序文件缺失，更新中止（当前服务保持运行）"
  exit 1
fi

chmod +x "$STAGED_BIN"
if ! validate_singbox_binary "$STAGED_BIN" "$LATEST_VERSION"; then
  echo "❌ 新程序预校验失败，更新中止（当前服务保持运行）"
  exit 1
fi

rm -f "$NEW_BIN"
if ! install -m 755 "$STAGED_BIN" "$NEW_BIN"; then
  echo "❌ 写入临时程序失败，更新中止（当前服务保持运行）"
  exit 1
fi

trap - EXIT INT TERM
rm -rf "$STAGE_DIR"

# === 停止服务并原子切换 ===
echo "⏹️ 停止 sing-box 服务..."
if ! stop_service; then
  echo "❌ 停止服务失败，更新中止"
  rm -f "$NEW_BIN" 2>/dev/null || true
  exit 1
fi

echo "🔁 原子切换程序文件..."
rm -f "$OLD_BIN"
if ! mv "$INSTALL_DIR/sing-box" "$OLD_BIN"; then
  echo "❌ 无法保存旧程序，更新中止"
  start_service || true
  rm -f "$NEW_BIN" 2>/dev/null || true
  exit 1
fi

if ! mv "$NEW_BIN" "$INSTALL_DIR/sing-box"; then
  echo "❌ 切换新程序失败，正在回滚..."
  mv "$OLD_BIN" "$INSTALL_DIR/sing-box" 2>/dev/null || true
  start_service || true
  exit 1
fi

# === 恢复文件权限 ===
echo "🔐 恢复文件权限..."
chown -R nobody:nogroup "$INSTALL_DIR" 2>/dev/null || \
chown -R nobody:nobody "$INSTALL_DIR" 2>/dev/null || true

# === 验证新版本 ===
if ! validate_singbox_binary "$INSTALL_DIR/sing-box" "$LATEST_VERSION"; then
  echo "❌ 切换后校验失败，正在回滚旧程序..."
  if rollback_binary "$OLD_BIN"; then
    if start_service && is_service_active; then
      echo "✅ 已回滚到旧版本并恢复服务"
    else
      echo "❌ 已回滚旧版本，但服务恢复失败，请手动检查"
    fi
  else
    echo "❌ 回滚失败，请手动处理"
  fi
  exit 1
fi

# === 启动服务 ===
echo "🚀 启动 sing-box 服务..."
if ! start_service; then
  echo "❌ 服务启动失败，正在回滚旧程序..."
  if rollback_binary "$OLD_BIN"; then
    start_service || true
  fi
  exit 1
fi

sleep 2
if ! is_service_active; then
  echo "❌ 服务启动失败，正在回滚旧程序..."
  if rollback_binary "$OLD_BIN"; then
    if start_service && is_service_active; then
      echo "✅ 已回滚到旧版本并恢复服务"
    else
      echo "❌ 已回滚旧版本，但服务恢复失败，请手动检查"
    fi
  else
    echo "❌ 回滚失败，请手动处理"
  fi
  case "$SERVICE_TYPE" in
    systemd) systemctl status sing-box || true ;;
    openrc) rc-service sing-box status || true ;;
  esac
  exit 1
fi

echo "✅ 服务启动成功"
rm -f "$OLD_BIN"

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
