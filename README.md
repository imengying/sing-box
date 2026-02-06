# sing-box 一键脚本（VLESS + Reality）

用于快速安装、更新、查看和卸载 sing-box 服务端。

## 功能

- 一键安装 sing-box（自动生成 UUID、Reality 密钥、配置文件）
- 一键更新 sing-box
- 一键更新配置（保留 UUID / 端口 / 私钥）
- 查看当前配置和服务状态
- 一键卸载
- 支持 systemd / OpenRC

## 支持环境

- 发行版：Debian/Ubuntu、RHEL/Fedora/CentOS 8+、Alpine
- 架构：x86_64、i386/i686、ARM(v5/v6/v7/v8)、ARM64、LoongArch64、MIPS、PPC64LE、RISC-V64、s390x

## 快速使用

需要 root 权限：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/imengying/sing-box/main/sing-box.sh")
```

## 菜单功能

1. 安装 sing-box
2. 更新 sing-box
3. 更新配置文件
4. 查看配置信息
5. 查看服务状态
6. 卸载 sing-box

## 更新方式

方式一（推荐）：运行主脚本并选菜单 `2`

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/imengying/sing-box/main/sing-box.sh")
```

方式二：直接运行独立更新脚本

```bash
curl -fsSL https://raw.githubusercontent.com/imengying/sing-box/refs/heads/main/update.sh | bash
```

## 常用服务命令

systemd:

```bash
systemctl status sing-box
systemctl restart sing-box
journalctl -u sing-box -f
```

OpenRC:

```bash
rc-service sing-box status
rc-service sing-box restart
```

## 文件路径

- 配置文件：`/etc/sing-box/config.json`
- 执行文件：`/etc/sing-box/sing-box`
- 公钥文件：`/etc/sing-box/public.key`

## VLESS 链接格式

```text
vless://<UUID>@<IP>:<PORT>?encryption=none&flow=xtls-rprx-vision&security=reality&sni=updates.cdn-apple.com&fp=firefox&pbk=<PublicKey>#VLESS-REALITY
```

IPv6 地址请使用 `[]` 包裹，例如：`[2001:db8::1]`。