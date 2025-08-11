# 🧊 sing-box 一键安装脚本（VLESS + Reality）

这是一个用于自动部署 [sing-box](https://github.com/SagerNet/sing-box) 服务端的 Shell 脚本，支持：

- ✅ VLESS + Reality + Vision 流量
- ✅ 自动生成配置、端口、UUID、密钥
- ✅ 兼容 Debian/Ubuntu、Alpine 和 RHEL/Fedora（使用 `apt` 或 `dnf`或 `apk`）
- ✅ 自动配置 systemd 服务或OpenRC服务
- ✅ 一键版本更新功能

---

## 📥 快速安装

### Debian/Ubuntu 和 RHEL/Fedora 系统

请使用 `root` 权限运行以下命令：

**国外主机**
```bash
curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/sing-box.sh | bash
```

**国内主机**
```bash
curl -fsSL https://www.imengying.eu.org/https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/sing-box.sh | bash
```

### Alpine 系统

**国外主机**
```bash
curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/sing-box-alpine.sh | bash
```

**国内主机**
```bash
curl -fsSL https://www.imengying.eu.org/https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/sing-box-alpine.sh | bash
```

---

## 🔄 版本更新

### 自动更新到最新版本

**国外主机**
```bash
curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/update.sh | bash
```

**国内主机**
```bash
curl -fsSL https://www.imengying.eu.org/https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/update.sh | bash
```



### 更新特性

- 🔍 **智能检测** - 自动比较当前版本与最新版本
- 💾 **安全备份** - 更新前自动备份当前版本
- 🔄 **故障回滚** - 更新失败时自动恢复到原版本
- 📋 **兼容性强** - 支持 systemd 和 OpenRC 系统
- ✅ **验证完整** - 更新后验证版本和服务状态

---

## 📂 安装内容

该脚本将自动完成以下工作：

- 安装必要依赖（curl、jq、uuidgen、tar 等）
- 下载最新版 sing-box 二进制文件
- 生成 Reality 密钥对和 UUID
- 随机分配监听端口
- 写入默认配置文件到 `/etc/sing-box/config.json`
- 创建并启用 systemd 或 OpenRC 服务
- 输出客户端连接链接

---

## 🔐 VLESS Reality 配置信息

脚本执行完成后会输出一条形如以下格式的 VLESS 链接：

```
vless://<UUID>@<IP或域名>:<PORT>?encryption=none&flow=xtls-rprx-vision&security=reality&sni=updates.cdn-apple.com&fp=chrome&pbk=<PublicKey>#VLESS-REALITY
```

复制该链接到支持 VLESS Reality 的客户端（如 v2rayN、Shadowrocket、SFI、sing-box 等）即可使用。

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

- **配置文件**：`/etc/sing-box/config.json`
- **执行文件**：`/etc/sing-box/sing-box`
- **备份目录**：`/etc/sing-box/backup/`（更新时自动创建）
- **systemd 服务文件**：`/etc/systemd/system/sing-box.service`
- **OpenRC 服务文件**：`/etc/init.d/sing-box`（Alpine 系统）

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

---

### 完全卸载

```bash
# 停止并删除服务
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
