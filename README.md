# 🧊 sing-box 一键安装脚本（VLESS + Reality）

用于自动部署 [sing-box](https://github.com/SagerNet/sing-box) 服务端的 Shell 脚本。

## ✨ 功能特性

* ✅ VLESS + Reality + Vision 协议
* ✅ 自动生成配置、UUID、密钥
* ✅ 自动配置端口（支持自定义）
* ✅ 支持 Debian/Ubuntu、Alpine、RHEL/Fedora/CentOS 8+
* ✅ 支持多种 CPU 架构（x86_64/ARM/ARM64/MIPS/RISC-V 等）
* ✅ 自动配置 systemd / OpenRC 服务
* ✅ 一键版本更新（带自动备份）
* ✅ IPv4 / IPv6 双栈自动检测
* ✅ 查看配置信息和 VLESS 链接
* ✅ 查看服务运行状态
* ✅ 完整卸载功能
* ✅ 网络请求超时和重试机制

---

## 🖥️ 支持的系统

### Linux 发行版
- **Debian 系列**：Debian、Ubuntu、Linux Mint 等
- **红帽系列**：RHEL、CentOS 8+、Fedora、Rocky Linux、AlmaLinux 等
- **其他**：Alpine Linux

### CPU 架构
- x86_64 (amd64)
- i386 / i686
- ARMv5 / ARMv6 / ARMv7 / ARMv8
- ARM64 (aarch64)
- LoongArch64
- MIPS / MIPS64
- PowerPC64LE
- RISC-V 64
- s390x

---

## 📥 快速使用

**需要 root 权限：**

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/main/sing-box.sh)
```

安装完成后会自动输出 VLESS 链接，复制到客户端即可使用

---

## 🔧 功能菜单

1. 安装 sing-box
2. 更新 sing-box（自动备份）
3. 更新配置文件（保留 UUID/端口/密钥）
4. 查看配置信息
5. 查看服务状态
6. 卸载 sing-box

---

## 🔄 版本更新

### 方法一：使用菜单更新（推荐）

运行主脚本，选择菜单选项 2：

```bash
sudo bash <(curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/main/sing-box.sh)
```

### 方法二：独立更新脚本

直接运行更新脚本（需要已通过 sing-box.sh 安装）：

```bash
curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/update.sh | bash
```

### 更新功能特性

* ✅ 自动检测最新版本
* ✅ 更新前自动备份（程序和配置）
* ✅ 版本验证确保更新成功
* ✅ 更新失败自动恢复服务
* ✅ 保留所有配置和密钥
* ✅ 网络请求超时和重试机制（10秒超时，最多重试3次）

## 🧰 服务管理

### systemd 系统（Debian/Ubuntu/RHEL/Fedora）

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

### OpenRC 系统（Alpine）

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
* **公钥文件**：`/etc/sing-box/public.key`
* **备份目录**：`/etc/sing-box/backup/`（更新时自动创建）

### 修改配置

编辑配置文件后需要重启服务：

```bash
nano /etc/sing-box/config.json
systemctl restart sing-box  # 或 rc-service sing-box restart
```

---

## 🌐 IPv4 / IPv6 说明

* 脚本会自动检测服务器的公网 IP 地址
* 如果同时检测到 IPv4 和 IPv6，会提示选择使用哪个
* IPv6 地址会自动用方括号 `[]` 包裹
* 可以在输出的 VLESS 链接中手动更换 IP 地址

---

## 🔐 VLESS 链接格式

```
vless://<UUID>@<IP>:<PORT>?encryption=none&flow=xtls-rprx-vision&security=reality&sni=updates.cdn-apple.com&fp=firefox&pbk=<PublicKey>#VLESS-REALITY
```

**示例**：
```
# IPv4
vless://abc123...@203.0.113.10:443?...

# IPv6
vless://abc123...@[2001:db8::1]:443?...
```

---

## 💾 备份与恢复

* 更新 sing-box 或配置文件时，会自动备份到 `/etc/sing-box/backup/` 目录
* 备份文件格式：`文件名.时间戳.bak`
* 卸载时可选择保留备份文件

---

## 🔒 安全说明

* 服务使用 `nobody` 用户运行（最小权限原则）
* systemd 启用了安全加固选项
* 更新失败时自动回滚
* 网络请求带超时和重试机制

---

## 📝 常见问题

**Q: 如何查看 VLESS 链接？**  
A: 运行脚本选择菜单选项 4「查看配置信息」

**Q: 如何更新到最新版本？**  
A: 两种方法：  
   1. 运行脚本选择菜单选项 2「更新 sing-box」  
   2. 直接运行 `update.sh` 独立更新脚本

**Q: update.sh 和主脚本的更新功能有什么区别？**  
A: 功能完全一致，`update.sh` 适合需要快速更新的场景，主脚本菜单提供更多选项

**Q: 更新会丢失配置吗？**  
A: 不会。更新前会自动备份，且保留所有 UUID、端口和密钥配置

**Q: 小版本更新后服务无法启动？**  
A: 运行脚本选择菜单选项 3「更新配置文件」

**Q: 如何完全卸载？**  
A: 运行脚本选择菜单选项 6「卸载 sing-box」

**Q: 端口被占用怎么办？**  
A: 安装时可以自定义端口，或留空随机分配

**Q: 支持哪些 Linux 发行版？**  
A: 支持 Debian/Ubuntu、Alpine、RHEL/Fedora/CentOS 8+ 及其衍生版
