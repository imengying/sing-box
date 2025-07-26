# 🧊 sing-box 一键安装脚本（VLESS + Reality）

这是一个用于自动部署 [sing-box](https://github.com/SagerNet/sing-box) 服务端的 Shell 脚本，支持：

- ✅ VLESS + Reality + Vision 流量
- ✅ 自动生成配置、端口、UUID、密钥
- ✅ 兼容 Debian/Ubuntu 和 RHEL/Fedora（使用 `apt` 或 `dnf`）
- ✅ 自动配置 systemd 服务

---

## 📥 快速安装

请使用 `root` 权限运行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/null0218/sing-box/main/sing-box.sh | bash
```

### 📂 安装内容

该脚本将自动完成以下工作：

- 安装必要依赖（curl、wget、jq、uuidgen、unzip 等）
- 下载最新版 sing-box
- 生成 Reality 密钥对
- 生成 UUID 和监听端口
- 写入默认配置文件到 `/etc/sing-box/config.json`
- 创建 systemd 服务并启用

### 🔐 VLESS Reality 配置信息

脚本执行完成后会输出一条形如以下格式的 VLESS 链接：

```
vless://<UUID>@<IP或域名>:<PORT>?encryption=none&flow=xtls-rprx-vision&security=reality&sni=updates.cdn-apple.com&fp=chrome&pbk=<PublicKey>#VLESS-REALITY
```

复制该链接到支持 VLESS Reality 的客户端（如 v2rayN、Shadowrocket、SFI 等）即可使用。

### 🧰 管理服务

使用 systemctl 管理 sing-box 服务：

```bash
systemctl status sing-box     # 查看运行状态
systemctl restart sing-box    # 重启服务
systemctl stop sing-box       # 停止服务
```

### ⚙️ 修改配置

脚本默认配置文件路径为：

```
/etc/sing-box/config.json
```

你可以手动编辑配置文件后执行以下命令使其生效：

```bash
systemctl restart sing-box
```
