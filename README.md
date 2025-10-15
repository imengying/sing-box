# 🧊 sing-box 一键安装脚本（VLESS + Reality）

这是一个用于自动部署 [sing-box](https://github.com/SagerNet/sing-box) 服务端的 Shell 脚本，支持：

* ✅ VLESS + Reality + Vision 流量
* ✅ 自动生成配置、端口、UUID、密钥
* ✅ 兼容 Debian/Ubuntu、Alpine 和 RHEL/Fedora（使用 `apt`、`dnf` 或 `apk`）
* ✅ 自动配置 systemd 服务或 OpenRC 服务
* ✅ 一键版本更新功能
* ✅ **配置更新功能（保留 UUID/端口/密钥）**
* ✅ **支持 IPv4 / IPv6 双栈自动检测（IPv6 优先）**

---

## 🌐 IPv4 / IPv6 说明

脚本在安装完成后会自动检测服务器的公网 IP：

* 若检测到 **IPv6 地址**，输出的 VLESS 链接会自动使用方括号 `[]` 包裹 IPv6；
* 若仅有 **IPv4 地址**，则直接使用 IPv4；
* **默认优先使用 IPv6**，如需使用 IPv4 地址，只需将输出链接中的 IPv6 地址改为你的 IPv4 地址即可。

---

## 📥 快速使用

**请使用 `root` 权限运行以下命令：**

### Debian/Ubuntu、RHEL/Fedora 和 Alpine 系统

```bash
curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/sing-box.sh | bash
```

---

## 🎯 功能选项

运行脚本后会显示功能菜单：

1. **配置** - 全新安装 sing-box（自动识别系统）
2. **更新** - 更新 sing-box 版本（保留所有配置）
3. **更新配置** - 刷新配置文件但保留 UUID、端口和密钥（适合调整其他参数）

---

## ✨ 更新配置功能说明

**新增的"更新配置"功能特点：**

* 🔒 **保留关键参数**：UUID、端口、私钥保持不变
* 🔄 **更新其他配置**：SNI、监听地址、TLS 设置等自动更新为最新标准
* 📦 **自动备份**：每次更新前自动备份配置到 `/etc/sing-box/backup/`
* 🔑 **重新生成链接**：根据保留的参数生成新的 VLESS 链接（公钥会重新计算）
* ✅ **无缝切换**：客户端无需更改 UUID 和端口

**使用场景：**
- 需要调整 SNI 域名但不想改变 UUID/端口
- 配置文件损坏需要重建但要保留现有连接参数
- 升级配置格式但保持客户端兼容性

---

## 📂 安装内容

该脚本将自动完成以下工作：

* 安装必要依赖（curl、jq、uuidgen、tar 等）
* 下载最新版 sing-box 二进制文件
* 生成 Reality 密钥对和 UUID
* 随机分配监听端口
* 写入默认配置文件到 `/etc/sing-box/config.json`
* 创建并启用 systemd 或 OpenRC 服务
* 自动检测公网 IP（IPv4 / IPv6）并输出客户端链接

---

## 🔐 VLESS Reality 配置信息

脚本执行完成后会输出一条形如以下格式的 VLESS 链接：

```
vless://<UUID>@<IP或域名>:<PORT>?encryption=none&flow=xtls-rprx-vision&security=reality&sni=updates.cdn-apple.com&fp=firefox&pbk=<PublicKey>#VLESS-REALITY
```

📌 **IPv6 输出示例：**

```
vless://<UUID>@[2408:8207:abcd:1234::1]:443?...#VLESS-REALITY
```

📌 **IPv4 输出示例：**

```
vless://<UUID>@203.0.113.10:443?...#VLESS-REALITY
```

> 💡 如果脚本输出为 IPv6 地址而你希望使用 IPv4，只需将链接中的 IPv6 地址替换为你的 IPv4 即可使用。

---

## 🧰 服务管理

### systemd 系统 (Debian/Ubuntu/RHEL/Fedora)

```bash
# 查看服务状态
systemctl status sing-box

# 启动服务
systemctl start sing-box

# 停止服务
systemctl stop sing-box

# 重启服务
systemctl restart sing-box

# 开机自启
systemctl enable sing-box

# 禁用开机自启
systemctl disable sing-box

# 查看实时日志
journalctl -u sing-box -f

# 查看历史日志
journalctl -u sing-box --no-pager
```

### OpenRC 系统 (Alpine)

```bash
# 查看服务状态
rc-service sing-box status

# 启动服务
rc-service sing-box start

# 停止服务
rc-service sing-box stop

# 重启服务
rc-service sing-box restart

# 开机自启
rc-update add sing-box default

# 禁用开机自启
rc-update del sing-box default
```

---

## ⚙️ 配置文件

### 文件位置

* **配置文件**：`/etc/sing-box/config.json`
* **执行文件**：`/etc/sing-box/sing-box`
* **备份目录**：`/etc/sing-box/backup/`（更新配置时自动创建）
* **systemd 服务文件**：`/etc/systemd/system/sing-box.service`
* **OpenRC 服务文件**：`/etc/init.d/sing-box`（Alpine 系统）

### 修改配置

手动编辑配置文件后需要重启服务使其生效：

```bash
# 编辑配置文件
nano /etc/sing-box/config.json

# 重启服务 (systemd)
systemctl restart sing-box

# 或重启服务 (OpenRC)
rc-service sing-box restart
```

### 查看当前配置

```bash
# 查看配置文件内容
cat /etc/sing-box/config.json

# 格式化显示配置
jq . /etc/sing-box/config.json
```

### 查看配置备份

```bash
# 列出所有备份
ls -lh /etc/sing-box/backup/

# 恢复备份（替换 YYYYMMDD_HHMMSS 为实际时间戳）
cp /etc/sing-box/backup/config.json.YYYYMMDD_HHMMSS /etc/sing-box/config.json
systemctl restart sing-box  # 或 rc-service sing-box restart
```

---

## 🗑️ 卸载

### 完全卸载

```bash
# 停止并删除服务 (systemd)
systemctl stop sing-box
systemctl disable sing-box
rm -f /etc/systemd/system/sing-box.service
systemctl daemon-reload

# 或 OpenRC 系统
rc-service sing-box stop
rc-update del sing-box default
rm -f /etc/init.d/sing-box

# 删除程序文件
rm -rf /etc/sing-box
```

---

## 🔧 常见问题

### Q: 如何更换 SNI 域名？

运行脚本选择"更新配置"功能，或手动编辑 `/etc/sing-box/config.json`，修改 `server_name` 和 `handshake.server` 字段后重启服务。

### Q: 如何更换端口？

需要手动编辑配置文件，修改 `listen_port` 字段，然后重启服务。注意客户端也需要更新端口。

### Q: 如何重新生成 UUID 和密钥？

重新运行安装脚本（选项 1）即可生成新的配置，原配置会被覆盖。建议先备份。

### Q: 配置备份在哪里？

所有通过"更新配置"功能产生的备份都存储在 `/etc/sing-box/backup/` 目录下，以时间戳命名。

---

## 📝 更新日志

* **v1.3** - 新增配置更新功能（保留 UUID/端口/密钥）
* **v1.2** - 支持 IPv4/IPv6 双栈自动检测
* **v1.1** - 支持 Alpine Linux (OpenRC)
* **v1.0** - 初始版本，支持 Debian/Ubuntu/RHEL/Fedora

---

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！
