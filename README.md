# 🧊 sing-box 一键安装脚本（VLESS + Reality）

这是一个用于自动部署 [sing-box](https://github.com/SagerNet/sing-box) 服务端的 Shell 脚本，支持：

* ✅ VLESS + Reality + Vision 流量
* ✅ 自动生成配置、UUID、密钥
* ✅ 手动配置端口
* ✅ 兼容 Debian/Ubuntu、Alpine 和 RHEL/Fedora（使用 `apt`、`dnf` 或 `apk`）
* ✅ 自动配置 systemd 服务或 OpenRC 服务
* ✅ 一键版本更新功能
* ✅ **更新配置文件功能**
* ✅ **支持 IPv4 / IPv6 双栈自动检测（IPv6 优先）**

---

## 📥 快速使用

**请使用 `root` 权限运行以下命令：**

### Debian/Ubuntu、RHEL/Fedora 和 Alpine 系统

```bash
curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/refs/heads/beta/sing-box.sh | bash
```
---
## 🌐 IPv4 / IPv6 说明

脚本在安装完成后会自动检测服务器的公网 IP：

* 若检测到 **IPv6 地址**，输出的 VLESS 链接会自动使用方括号 `[]` 包裹 IPv6；
* 若仅有 **IPv4 地址**，则直接使用 IPv4；
* **默认优先使用 IPv6**，如需使用 IPv4 地址，只需将输出链接中的 IPv6 地址改为你的 IPv4 地址即可。

---

### 更新配置文件

安装完成后，如需按照当前模板重写配置但保留关键标识（UUID/端口/PublicKey）不变或者小版本更新后配置不生效，可在脚本主菜单选择：

> 注意：若你的配置结构有自定义改动（如多入站、不同 tag），此操作会根据脚本模板覆盖为单一 VLESS Reality 入站。如需保留自定义项，请先备份或手动合并。

---

### 更新特性

* 🔍 **智能检测** - 自动比较当前版本与最新版本
* 📋 **兼容性强** - 支持 systemd 和 OpenRC 系统
* ✅ **验证完整** - 更新后验证版本和服务状态

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
* **备份目录**：`/etc/sing-box/backup/`（更新时自动创建）
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
