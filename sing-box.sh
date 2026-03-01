#!/bin/bash
set -e

FORCE_AUTO="${FORCE_AUTO:-0}"
INSTALL_DIR="/etc/sing-box"
SNI="updates.cdn-apple.com"

require_root() {
  if [ "$(id -u)" != "0" ]; then
    echo "❌ 请使用 root 权限运行该脚本"
    exit 1
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

safe_curl() {
  curl -fsSL --connect-timeout 10 --max-time 300 --retry 3 "$@"
}

detect_architecture() {
  UNAME_ARCH=$(uname -m)
  case "$UNAME_ARCH" in
    x86_64) echo "amd64" ;;
    i386|i686) echo "386" ;;
    armv5*) echo "armv5" ;;
    armv6*) echo "armv6" ;;
    armv7l|armv7*) echo "armv7" ;;
    armv8*|aarch64|arm64) echo "arm64" ;;
    loongarch64) echo "loong64" ;;
    mips64el) echo "mips64le" ;;
    mips64) echo "mips64" ;;
    mipsel) echo "mipsle" ;;
    mips) echo "mips" ;;
    ppc64le) echo "ppc64le" ;;
    riscv64) echo "riscv64" ;;
    s390x) echo "s390x" ;;
    *) echo "❌ 不支持的架构: $UNAME_ARCH" >&2; return 1 ;;
  esac
}

detect_system() {
  if command -v apk >/dev/null 2>&1; then
    echo "alpine"; return
  fi
  if [ -f /etc/os-release ] && grep -qi 'alpine' /etc/os-release; then
    echo "alpine"; return
  fi
  if [ -f /etc/debian_version ]; then
    echo "debian"; return
  fi
  if [ -f /etc/redhat-release ]; then
    echo "redhat"; return
  fi
  echo "default"
}

get_service_type() {
  if [ -f /etc/init.d/sing-box ]; then echo "openrc"; return 0; fi
  if [ -f /etc/systemd/system/sing-box.service ]; then echo "systemd"; return 0; fi
  if command_exists systemctl; then echo "systemd"; return 0; fi
  echo ""
}

validate_port() {
  local input_port="$1"
  local rand_u16=""
  if [ -z "$input_port" ]; then
    rand_u16=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d " ")
    [ -z "$rand_u16" ] && rand_u16=$(date +%s)
    echo $((1025 + (rand_u16 % 64510)))
    return 0
  fi
  
  case "$input_port" in
    *[!0-9]*)
      echo "⚠️ 非法端口 \"$input_port\"，将随机分配。" >&2
      rand_u16=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d " ")
      [ -z "$rand_u16" ] && rand_u16=$(date +%s)
      echo $((1025 + (rand_u16 % 64510)))
      ;;
    *)
      if [ "$input_port" -ge 1 ] && [ "$input_port" -le 65535 ]; then
        echo "$input_port"
      else
        echo "⚠️ 端口超出范围(1–65535)，将随机分配。" >&2
        rand_u16=$(od -An -N2 -tu2 /dev/urandom 2>/dev/null | tr -d " ")
        [ -z "$rand_u16" ] && rand_u16=$(date +%s)
        echo $((1025 + (rand_u16 % 64510)))
      fi
      ;;
  esac
}

generate_vless_config() {
  local uuid="$1"
  local private_key="$2"
  local port="$3"
  local output_file="$4"
  
  jq -n \
    --arg uuid "$uuid" \
    --arg private_key "$private_key" \
    --arg sni "$SNI" \
    --arg listen "::" \
    --arg type "vless" \
    --arg tag "vless-reality" \
    --argjson port "$port" \
    '{
      log:{level:"error"},
      inbounds:[{type:$type,tag:$tag,listen:$listen,listen_port:$port,users:[{uuid:$uuid,flow:"xtls-rprx-vision"}],tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$private_key}}}],
      outbounds:[{type:"direct",tag:"direct"}]
    }' > "$output_file"
}

# =========================
# 最小修复：替换的两个函数
# =========================

# 获取最新版本（stdout 只输出版本号；日志打印到 stderr）
get_latest_version() {
  echo "🔍 正在检查最新版本..." >&2
  VERSION_TAG=$(
    safe_curl -H "Accept: application/vnd.github+json" -H "User-Agent: curl/8" \
      https://api.github.com/repos/SagerNet/sing-box/releases/latest \
      | jq -r '.tag_name // empty' 2>/dev/null
  )
  VERSION_TAG=$(printf "%s" "$VERSION_TAG" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  if [ -z "$VERSION_TAG" ] || [ "$VERSION_TAG" = "null" ]; then
    echo "❌ 无法获取最新版本信息，请检查网络连接或稍后重试" >&2
    echo "💡 可能原因：网络问题、GitHub API限流、或防火墙拦截" >&2
    return 1
  fi
  printf "%s" "${VERSION_TAG#v}"
}

# ✅ 修复：强制 v4/v6 探测 + 结果校验；未检测到时显示“无”
# 检测公网 IP（stdout 只输出最终 IP/域名；日志到 stderr）
detect_public_ip() {
  echo "🔍 正在检测公网IP地址..." >&2

  # 分别强制使用 IPv4 / IPv6；失败不会中断脚本（set -e 安全处理）
  RAW4=$( (safe_curl -4 https://api.ipify.org 2>/dev/null || true) | tr -d '\r\n' )
  RAW6=$( (safe_curl -6 https://api64.ipify.org 2>/dev/null || true) | tr -d '\r\n' )

  # 形态校验函数（避免把 IPv4 当成 IPv6）
  is_ipv4() {
    printf '%s' "$1" | grep -Eq \
      '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$' \
      >/dev/null 2>&1 || return 1
    return 0
  }
  is_ipv6() {
    [ -n "$1" ] || return 1
    printf '%s' "$1" | grep -Eq '^[0-9A-Fa-f:]+$' >/dev/null 2>&1 || return 1
    printf '%s' "$1" | grep -q ':' >/dev/null 2>&1 || return 1
    return 0
  }

  local IPV4=""
  local IPV6=""
  is_ipv4 "$RAW4" && IPV4="$RAW4"
  is_ipv6 "$RAW6" && IPV6="$RAW6"

  if [ -n "$IPV4" ]; then
    echo "✅ 检测到 IPv4: $IPV4" >&2
  else
    echo "ℹ️  IPv4: 无" >&2
  fi
  if [ -n "$IPV6" ]; then
    echo "✅ 检测到 IPv6: $IPV6" >&2
  else
    echo "ℹ️  IPv6: 无" >&2
  fi

  if [ -n "$IPV6" ] && [ -n "$IPV4" ]; then
    if [ "$FORCE_AUTO" = "1" ]; then
      local PREFER_IPV=${PREFER_IPV:-6}
      if [ "$PREFER_IPV" = "4" ]; then
        printf "%s" "$IPV4"
      else
        printf "%s" "$IPV6"
      fi
    else
      if [ -t 0 ]; then
        local ip_choice=""
        while :; do
          printf "请选择使用的IP版本 [4/6] (默认6): " >&2
          read -r ip_choice || ip_choice=""
          case "$ip_choice" in
            4) printf "%s" "$IPV4"; break ;;
            6|"") printf "%s" "$IPV6"; break ;;
            *) echo "⚠️ 请输入 4 或 6" >&2 ;;
          esac
        done
      else
        echo "ℹ️  非交互环境，默认使用 IPv6" >&2
        printf "%s" "$IPV6"
      fi
    fi
  elif [ -n "$IPV6" ]; then
    printf "%s" "$IPV6"
  elif [ -n "$IPV4" ]; then
    printf "%s" "$IPV4"
  else
    echo "⚠️ 无法检测到公网IP，请手动替换" >&2
    printf "%s" "yourdomain.com"
  fi
}

format_ip_for_url() {
  ip="$1"
  case "$ip" in
    *:*) echo "[$ip]" ;;
    *) echo "$ip" ;;
  esac
}

generate_vless_url() {
  local uuid="$1"
  local ip="$2"
  local port="$3"
  local public_key="$4"
  
  local formatted_ip=$(format_ip_for_url "$ip")
  echo "vless://${uuid}@${formatted_ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=firefox&pbk=${public_key}#VLESS-REALITY"
}

ensure_jq() {
  if command_exists jq; then return 0; fi
  echo "📦 正在安装 jq..." >&2
  
  if command_exists apk; then
    apk update >/dev/null 2>&1 || true
    apk add jq >/dev/null 2>&1 || true
  elif command_exists apt-get; then
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y jq >/dev/null 2>&1 || true
  elif command_exists apt; then
    apt update >/dev/null 2>&1 || true
    apt install -y jq >/dev/null 2>&1 || true
  elif command_exists dnf; then
    dnf makecache >/dev/null 2>&1 || true
    dnf install -y jq >/dev/null 2>&1 || true
  fi
  
  if ! command_exists jq; then
    echo "❌ jq 安装失败，请手动安装后重试" >&2
    return 1
  fi
  echo "✅ jq 安装成功" >&2
  return 0
}

ensure_curl() {
  if command_exists curl; then return 0; fi
  echo "📦 正在安装 curl..." >&2
  
  if command_exists apk; then
    apk update >/dev/null 2>&1 || true
    apk add curl >/dev/null 2>&1 || true
  elif command_exists apt-get; then
    apt-get update >/dev/null 2>&1 || true
    apt-get install -y curl >/dev/null 2>&1 || true
  elif command_exists apt; then
    apt update >/dev/null 2>&1 || true
    apt install -y curl >/dev/null 2>&1 || true
  elif command_exists dnf; then
    dnf makecache >/dev/null 2>&1 || true
    dnf install -y curl >/dev/null 2>&1 || true
  fi
  
  if ! command_exists curl; then
    echo "❌ curl 安装失败，请手动安装后重试" >&2
    return 1
  fi
  echo "✅ curl 安装成功" >&2
  return 0
}

# 获取当前版本
get_current_version() {
  if [ ! -f "$INSTALL_DIR/sing-box" ]; then
    echo "未安装"
    return 0
  fi
  
  local version=$("$INSTALL_DIR/sing-box" version 2>/dev/null | awk '{print $3}' || echo "unknown")
  echo "$version"
}

# 下载sing-box
download_singbox() {
  local version="$1"
  local arch="$2"
  local dest_dir="$3"
  
  local FILENAME="sing-box-${version}-linux-${arch}.tar.gz"
  local DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${version}/${FILENAME}"
  
  echo "⬇️ 正在下载 sing-box v${version} (${arch})..." >&2
  
  (
    cd "$dest_dir" || exit 1
    if ! safe_curl -O "$DOWNLOAD_URL"; then
      echo "❌ 下载失败，请检查网络连接" >&2
      echo "💡 下载地址: $DOWNLOAD_URL" >&2
      exit 1
    fi
    
    if [ ! -s "$FILENAME" ]; then
      echo "❌ 下载的文件为空或不存在" >&2
      exit 1
    fi
    
    echo "📦 正在解压..." >&2
    tar -xzf "$FILENAME"
    mv "sing-box-${version}-linux-${arch}/sing-box" .
    chmod +x sing-box
    rm -rf "sing-box-${version}-linux-${arch}" "$FILENAME"
  ) || return 1
  
  echo "✅ sing-box 下载成功" >&2
}

# 服务管理函数
restart_service() {
  local stype="$(get_service_type)"
  case "$stype" in
    systemd)
      systemctl restart sing-box || return 1
      sleep 1
      systemctl is-active --quiet sing-box
      ;;
    openrc)
      rc-service sing-box restart || return 1
      sleep 1
      rc-service sing-box status >/dev/null 2>&1
      ;;
    *) return 2 ;;
  esac
}

stop_service() {
  local stype="$(get_service_type)"
  case "$stype" in
    systemd) systemctl stop sing-box ;;
    openrc) rc-service sing-box stop ;;
    *) return 1 ;;
  esac
}

start_service() {
  local stype="$(get_service_type)"
  case "$stype" in
    systemd) systemctl start sing-box ;;
    openrc) rc-service sing-box start ;;
    *) return 1 ;;
  esac
}

is_service_active() {
  local stype="$(get_service_type)"
  case "$stype" in
    systemd) systemctl is-active --quiet sing-box ;;
    openrc) rc-service sing-box status >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

binary_supports_check() {
  local bin_path="$1"
  "$bin_path" help 2>/dev/null | grep -Eq '(^|[[:space:]])check([[:space:]]|$)'
}

validate_singbox_binary() {
  local bin_path="$1"
  local expected_version="$2"
  local config_file="$INSTALL_DIR/config.json"

  local detected_version=$("$bin_path" version 2>/dev/null | head -n1 | awk '{print $3}' || echo "unknown")
  if [ "$detected_version" != "$expected_version" ]; then
    echo "❌ 新程序版本校验失败：期望 $expected_version，实际 $detected_version" >&2
    return 1
  fi

  if [ -f "$config_file" ] && binary_supports_check "$bin_path"; then
    if ! "$bin_path" check -c "$config_file" >/dev/null 2>&1; then
      echo "❌ 新程序配置校验失败，请检查: $config_file" >&2
      return 1
    fi
  fi

  return 0
}

rollback_binary() {
  local old_bin="$1"
  local current_bin="$INSTALL_DIR/sing-box"

  [ -f "$current_bin" ] && rm -f "$current_bin"
  if [ ! -f "$old_bin" ]; then
    echo "❌ 回滚失败：未找到旧程序文件 $old_bin" >&2
    return 1
  fi

  if ! mv "$old_bin" "$current_bin"; then
    echo "❌ 回滚失败：无法恢复旧程序文件" >&2
    return 1
  fi

  chmod +x "$current_bin" 2>/dev/null || true
  chown -R nobody:nogroup "$INSTALL_DIR" 2>/dev/null || \
  chown -R nobody:nobody "$INSTALL_DIR" 2>/dev/null || true
  return 0
}

install_alpine() {
  local input_port="$1"
  
  if [ "$(id -u)" != "0" ]; then echo "❌ 请使用 root 权限运行该脚本"; exit 1; fi
  
  if [ -f /etc/init.d/sing-box ]; then
    if [ "$FORCE_AUTO" != "1" ]; then
      if [ -t 0 ]; then
        echo "⚠️ sing-box 服务已存在，是否继续安装？[y/N]"
        read -r choice
        [ "$choice" != "y" ] && [ "$choice" != "Y" ] && exit 0
      else
        echo "ℹ️  非交互环境，默认取消安装（如需继续请使用 --auto）" >&2
        exit 0
      fi
    fi
  fi
  
  echo "📦 正在安装依赖..."
  apk update
  apk add curl jq tar util-linux
  
  for cmd in curl jq tar uuidgen; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "❌ 缺少必要命令: $cmd"; exit 1; }
  done
  
  local ARCH=$(detect_architecture) || exit 1
  local VERSION=$(get_latest_version) || exit 1
  
  mkdir -p "$INSTALL_DIR"
  download_singbox "$VERSION" "$ARCH" "$INSTALL_DIR" || exit 1
  
  echo "🔐 正在生成密钥..." >&2
  local KEYS=$("$INSTALL_DIR/sing-box" generate reality-keypair)
  local PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
  local PUBLIC_KEY=$(echo "$KEYS" | grep 'PublicKey' | awk '{print $2}')
  local UUID=$(uuidgen)
  
  local PORT=$(validate_port "$input_port")
  echo "📍 使用端口: $PORT" >&2
  
  echo "⚙️ 正在生成配置文件..." >&2
  generate_vless_config "$UUID" "$PRIVATE_KEY" "$PORT" "$INSTALL_DIR/config.json"
  
  # 保存公钥到独立文件，方便后续查看
  echo "$PUBLIC_KEY" > "$INSTALL_DIR/public.key"
  chmod 600 "$INSTALL_DIR/public.key"
  
  echo "🔧 正在配置 OpenRC 服务..."
  cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
name="sing-box"
description="sing-box service"
command="${INSTALL_DIR}/sing-box"
command_args="run -c ${INSTALL_DIR}/config.json"
command_user="nobody"
command_background="yes"
pidfile="/run/sing-box.pid"
start_stop_daemon_args="--make-pidfile --pidfile \${pidfile}"
depend(){ need net; }
EOF
  chmod +x /etc/init.d/sing-box
  
  # 确保nobody用户有权限读取配置
  # Alpine系统中nobody可能属于nogroup或nobody组
  chown -R nobody:nogroup "$INSTALL_DIR" 2>/dev/null || \
  chown -R nobody:nobody "$INSTALL_DIR" 2>/dev/null || true
  
  rc-update add sing-box default
  rc-service sing-box start
  
  sleep 2
  
  echo ""
  echo "==========================================" >&2
  local DOMAIN_OR_IP=$(detect_public_ip)
  local VLESS_URL=$(generate_vless_url "$UUID" "$DOMAIN_OR_IP" "$PORT" "$PUBLIC_KEY")
  
  echo "==========================================" >&2
  echo "✅ sing-box 安装并运行成功！" >&2
  echo "==========================================" >&2
  echo "" >&2
  echo "📋 VLESS 链接：" >&2
  echo "$VLESS_URL"
  echo "" >&2
  echo "💾 配置文件位置: $INSTALL_DIR/config.json" >&2
  echo "🔧 服务管理: rc-service sing-box [start|stop|restart|status]" >&2
  echo "==========================================" >&2
}

install_default() {
  local input_port="$1"
  local PKG_MANAGER=""
  local INSTALL_CMD=""
  local UPDATE_CMD=""
  
  if [ "$(id -u)" != "0" ]; then echo "❌ 请使用 root 权限运行该脚本"; exit 1; fi
  
  if [ -x "$(command -v apt-get)" ]; then
    PKG_MANAGER="apt-get"
    INSTALL_CMD="apt-get install -y"
    UPDATE_CMD="apt-get update"
  elif [ -x "$(command -v dnf)" ]; then
    PKG_MANAGER="dnf"
    INSTALL_CMD="dnf install -y"
    UPDATE_CMD="dnf makecache"
  else
    echo "❌ 不支持的系统类型，未找到 apt-get/dnf"
    exit 1
  fi
  
  echo "🔍 正在更新软件包索引..."
  $UPDATE_CMD
  
  echo "📦 正在检查依赖..."
  for cmd in curl tar jq uuidgen; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "📦 安装缺失组件: $cmd"
      case "$cmd" in
        uuidgen) $INSTALL_CMD uuid-runtime 2>/dev/null || $INSTALL_CMD util-linux ;;
        curl|tar|jq) $INSTALL_CMD "$cmd" ;;
      esac
    fi
  done
  
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet sing-box; then
    if [ "$FORCE_AUTO" != "1" ]; then
      if [ -t 0 ]; then
        read -r -p "⚠️ sing-box 服务已在运行，是否继续安装？[y/N] " choice
        [ "$choice" != "y" ] && [ "$choice" != "Y" ] && exit 0
      else
        echo "ℹ️  非交互环境，默认取消安装（如需继续请使用 --auto）" >&2
        exit 0
      fi
    fi
  fi
  
  local ARCH=$(detect_architecture) || exit 1
  local VERSION=$(get_latest_version) || exit 1
  
  mkdir -p "$INSTALL_DIR"
  download_singbox "$VERSION" "$ARCH" "$INSTALL_DIR" || exit 1
  
  echo "🔐 正在生成密钥..." >&2
  local KEYS=$("$INSTALL_DIR/sing-box" generate reality-keypair)
  local PRIVATE_KEY=$(echo "$KEYS" | grep 'PrivateKey' | awk '{print $2}')
  local PUBLIC_KEY=$(echo "$KEYS" | grep 'PublicKey' | awk '{print $2}')
  local UUID=$(uuidgen)
  
  local PORT=$(validate_port "$input_port")
  echo "📍 使用端口: $PORT" >&2
  
  echo "⚙️ 正在生成配置文件..." >&2
  generate_vless_config "$UUID" "$PRIVATE_KEY" "$PORT" "$INSTALL_DIR/config.json"
  
  # 保存公钥到独立文件，方便后续查看
  echo "$PUBLIC_KEY" > "$INSTALL_DIR/public.key"
  chmod 600 "$INSTALL_DIR/public.key"
  
  echo "🔧 正在配置 systemd 服务..."
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
  
  # 确保nobody用户有权限读取配置
  chown -R nobody:nogroup "$INSTALL_DIR" 2>/dev/null || \
  chown -R nobody:nobody "$INSTALL_DIR" 2>/dev/null || true
  
  systemctl daemon-reload
  systemctl enable sing-box
  systemctl start sing-box
  
  sleep 2
  
  echo ""
  echo "==========================================" >&2
  local DOMAIN_OR_IP=$(detect_public_ip)
  local VLESS_URL=$(generate_vless_url "$UUID" "$DOMAIN_OR_IP" "$PORT" "$PUBLIC_KEY")
  
  echo "==========================================" >&2
  echo "✅ sing-box 安装并运行成功！" >&2
  echo "==========================================" >&2
  echo "" >&2
  echo "📋 VLESS 链接：" >&2
  echo "$VLESS_URL"
  echo "" >&2
  echo "💾 配置文件位置: $INSTALL_DIR/config.json" >&2
  echo "🔧 服务管理: systemctl [start|stop|restart|status] sing-box" >&2
  echo "📊 查看日志: journalctl -u sing-box -f" >&2
  echo "==========================================" >&2
}

run_config() {
  local sys="$(detect_system)"
  echo "🧭 系统识别: ${sys}"
  echo "---------------------------------------"
  local INPUT_PORT=""
  if [ "$FORCE_AUTO" != "1" ]; then
    if [ -t 0 ]; then
      printf "🔢 请输入本地监听端口（留空则随机 1025–65535）: "
      read -r INPUT_PORT
    else
      echo "ℹ️  非交互环境，端口将随机分配（可用 AUTO_PORT 指定）" >&2
    fi
  else
    INPUT_PORT="$AUTO_PORT"
  fi
  echo "🛠️ 正在执行配置..."
  echo ""
  
  if [ "$sys" = "alpine" ]; then
    install_alpine "$INPUT_PORT"
  else
    install_default "$INPUT_PORT"
  fi
}

run_update() {
  echo "⬆️  正在执行 sing-box 一键更新..."
  require_root
  
  if [ ! -f "$INSTALL_DIR/sing-box" ]; then
    echo "❌ 未找到 sing-box，请先安装"
    exit 1
  fi
  
  ensure_jq || exit 1
  ensure_curl || exit 1
  
  local stype="$(get_service_type)"
  if [ -z "$stype" ]; then
    echo "❌ 未找到 sing-box 服务配置"
    exit 1
  fi
  
  local CURRENT_VERSION=$(get_current_version)
  echo "📋 当前版本: $CURRENT_VERSION"
  
  local LATEST_VERSION=$(get_latest_version) || exit 1
  echo "📋 最新版本: $LATEST_VERSION"
  
  if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    echo "✅ 已是最新版本，无需更新"
    exit 0
  fi
  
  echo "🔄 发现新版本，准备更新..."
  
  local ARCH=$(detect_architecture) || exit 1
  local STAGE_DIR=$(mktemp -d /tmp/sing-box-update.XXXXXX)
  local STAGED_BIN="$STAGE_DIR/sing-box"
  local NEW_BIN="$INSTALL_DIR/sing-box.new"
  local OLD_BIN="$INSTALL_DIR/sing-box.old"
  
  trap 'rm -rf "$STAGE_DIR"' EXIT INT TERM
  
  echo "⬇️  下载并预校验新版本..."
  if ! download_singbox "$LATEST_VERSION" "$ARCH" "$STAGE_DIR"; then
    echo "❌ 下载失败，更新中止（当前服务保持运行）"
    exit 1
  fi
  
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
  
  echo "⏹️  停止 sing-box 服务..."
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
  
  # 恢复文件权限
  chown -R nobody:nogroup "$INSTALL_DIR" 2>/dev/null || \
  chown -R nobody:nobody "$INSTALL_DIR" 2>/dev/null || true
  
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
    case "$stype" in
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
  case "$stype" in
    systemd)
      echo "  状态查看: systemctl status sing-box"
      echo "  重启服务: systemctl restart sing-box"
      echo "  查看日志: journalctl -u sing-box -f"
      ;;
    openrc)
      echo "  状态查看: rc-service sing-box status"
      echo "  重启服务: rc-service sing-box restart"
      ;;
  esac
}

run_update_config() {
  echo "🛠️  正在更新配置（保留 UUID / 端口 / PublicKey）..."
  require_root
  
  local CONFIG_FILE="$INSTALL_DIR/config.json"
  
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 未找到配置文件: $CONFIG_FILE"
    exit 1
  fi
  
  ensure_jq || exit 1
  
  local UUID=$(jq -r '.inbounds[0].users[0].uuid // empty' "$CONFIG_FILE")
  local PORT=$(jq -r '.inbounds[0].listen_port // empty' "$CONFIG_FILE")
  local PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key // empty' "$CONFIG_FILE")
  
  if [ -z "$UUID" ] || [ -z "$PORT" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "❌ 配置中缺少必要字段（uuid/port/private_key）"
    exit 1
  fi
  
  echo "⚙️ 生成新配置..."
  generate_vless_config "$UUID" "$PRIVATE_KEY" "$PORT" "$CONFIG_FILE"
  
  echo "ℹ️  已保持 UUID 与端口不变；由于沿用原 private_key，PublicKey 保持不变。"
  
  if restart_service; then
    echo "✅ 配置已更新并成功重启"
  else
    st=$?
    if [ "$st" -eq 2 ]; then
      echo "⚠️  未检测到服务管理器，需手动重启 sing-box"
    else
      echo "❌ 服务重启失败，请检查状态"
    fi
  fi
}

run_show_config() {
  local CONFIG_FILE="$INSTALL_DIR/config.json"
  
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 未找到配置文件: $CONFIG_FILE"
    echo "💡 请先安装 sing-box"
    exit 1
  fi
  
  ensure_jq || exit 1
  
  local UUID=$(jq -r '.inbounds[0].users[0].uuid // empty' "$CONFIG_FILE")
  local PORT=$(jq -r '.inbounds[0].listen_port // empty' "$CONFIG_FILE")
  local PRIVATE_KEY=$(jq -r '.inbounds[0].tls.reality.private_key // empty' "$CONFIG_FILE")
  
  if [ -z "$UUID" ] || [ -z "$PORT" ] || [ -z "$PRIVATE_KEY" ]; then
    echo "❌ 配置文件格式不正确"
    exit 1
  fi
  
  # 从保存的文件中读取公钥
  local PUBLIC_KEY=""
  if [ -f "$INSTALL_DIR/public.key" ]; then
    PUBLIC_KEY=$(cat "$INSTALL_DIR/public.key" 2>/dev/null || echo "")
  fi
  
  # 如果公钥文件不存在或为空
  if [ -z "$PUBLIC_KEY" ]; then
    echo "⚠️  未找到保存的公钥文件"
    echo "💡 提示：安装时的公钥已丢失，建议重新安装或查看安装时的输出"
    PUBLIC_KEY="<公钥已丢失，请查看安装时的输出或重新安装>"
  fi
  
  local CURRENT_VERSION=$(get_current_version)
  
  echo "==========================================" >&2
  echo "📋 sing-box 配置信息" >&2
  echo "==========================================" >&2
  echo "" >&2
  echo "🔢 版本: $CURRENT_VERSION" >&2
  echo "🔑 UUID: $UUID" >&2
  echo "🔌 端口: $PORT" >&2
  echo "🔐 私钥: $PRIVATE_KEY" >&2
  echo "🔓 公钥: $PUBLIC_KEY" >&2
  echo "" >&2
  
  # 智能检测IP
  echo "🌐 正在生成 VLESS 链接..." >&2
  local DOMAIN_OR_IP=$(detect_public_ip)
  local VLESS_URL=$(generate_vless_url "$UUID" "$DOMAIN_OR_IP" "$PORT" "$PUBLIC_KEY")
  
  echo "" >&2
  echo "📋 VLESS 链接：" >&2
  echo "$VLESS_URL"
  echo "" >&2
  echo "💾 配置文件: $CONFIG_FILE" >&2
  echo "==========================================" >&2
}

run_show_status() {
  if [ ! -f "$INSTALL_DIR/sing-box" ]; then
    echo "❌ sing-box 未安装"
    exit 1
  fi
  
  local stype="$(get_service_type)"
  if [ -z "$stype" ]; then
    echo "❌ 未找到 sing-box 服务配置"
    exit 1
  fi
  
  local CURRENT_VERSION=$(get_current_version)
  
  echo "=========================================="
  echo "📊 sing-box 服务状态"
  echo "=========================================="
  echo ""
  echo "🔢 版本: $CURRENT_VERSION"
  echo "🔧 服务类型: $stype"
  echo ""
  
  case "$stype" in
    systemd)
      systemctl status sing-box --no-pager
      ;;
    openrc)
      rc-service sing-box status
      ;;
  esac
}

run_uninstall() {
  echo "=========================================="
  echo "⚠️  警告：即将卸载 sing-box"
  echo "=========================================="
  echo ""
  echo "这将删除："
  echo "  • sing-box 程序文件"
  echo "  • 配置文件"
  echo "  • 系统服务配置"
  echo ""
  if [ "$FORCE_AUTO" != "1" ]; then
    if [ -t 0 ]; then
      printf "确认卸载？[y/N] "
      read -r confirm
      
      if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消卸载"
        exit 0
      fi
    else
      echo "ℹ️  非交互环境，默认取消卸载（如需强制卸载请使用 --auto）" >&2
      exit 0
    fi
  fi
  
  require_root
  
  stype="$(get_service_type)"
  
  if [ -n "$stype" ]; then
    echo "⏹️  停止服务..."
    case "$stype" in
      systemd)
        systemctl stop sing-box 2>/dev/null || true
        systemctl disable sing-box 2>/dev/null || true
        rm -f /etc/systemd/system/sing-box.service
        systemctl daemon-reload
        ;;
      openrc)
        rc-service sing-box stop 2>/dev/null || true
        rc-update del sing-box default 2>/dev/null || true
        rm -f /etc/init.d/sing-box
        ;;
    esac
    echo "✅ 服务已停止并移除"
  fi
  
  if [ -d "$INSTALL_DIR" ]; then
    echo "🗑️  删除程序文件..."
    rm -rf "$INSTALL_DIR"
    echo "✅ 程序文件已删除"
  fi
  
  echo ""
  echo "=========================================="
  echo "✅ sing-box 已完全卸载"
  echo "=========================================="
}

main_menu() {
  echo "=========================================="
  echo "  sing-box 管理脚本"
  echo "=========================================="
  echo "1. 安装 sing-box"
  echo "2. 更新 sing-box"
  echo "3. 更新配置文件"
  echo "4. 查看配置信息"
  echo "5. 查看服务状态"
  echo "6. 卸载 sing-box"
  echo "q. 退出"
  echo "=========================================="
  printf "请选择 [1-6/q]: "
  read -r choice
  
  case "$choice" in
    1) require_root; run_config ;;
    2) require_root; run_update ;;
    3) require_root; run_update_config ;;
    4) run_show_config ;;
    5) run_show_status ;;
    6) run_uninstall ;;
    q|Q) echo "已退出。"; exit 0 ;;
    *) echo "无效选择"; exit 2 ;;
  esac
}

main() {
  if [ "$1" = "-y" ] || [ "$1" = "--auto" ]; then
    export FORCE_AUTO="1"
    shift
  fi

  case "$1" in
    install|i)
      require_root
      run_config
      ;;
    update|u)
      require_root
      run_update
      ;;
    config|c)
      require_root
      run_update_config
      ;;
    info)
      run_show_config
      ;;
    status|s)
      run_show_status
      ;;
    uninstall)
      run_uninstall
      ;;
    "")
      main_menu
      ;;
    *)
      echo "未知参数: $1"
      echo "可用参数: [-y/--auto] install(i) | update(u) | config(c) | info | status(s) | uninstall"
      exit 1
      ;;
  esac
}

main "$@"
