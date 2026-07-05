# sbox-reality

专业、轻量、可读的 **sing-box** 一键安装脚本。

支持：

- **AnyTLS + REALITY**
- **VLESS + REALITY**
- **Hysteria2 + Surge 端口跳跃**
- **Snell v5（Surge）**
- **Snell v6（Surge Beta）**
- **同时安装多个入站到同一个 sing-box 配置**
- **按协议卸载、保留配置重装或生成全新配置**

本项目支持 Debian、Ubuntu 和 Alpine Linux VPS，默认自动选择一个当前未被占用的随机高端口，完成服务端部署，并生成可直接合并到客户端配置中的 `outbounds` 片段。

脚本会从 sing-box 官方 Releases 自动选择并安装最新 alpha 版本，以支持 Hysteria2 Gecko 等最新功能。

---

## 统一一键安装

推荐使用统一脚本：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh)
```

Alpine Linux 默认没有 Bash，请先安装启动脚本所需的基础工具：

```sh
apk add --no-cache bash curl
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh)
```

不带参数运行时会出现菜单：

```text
1) 安装 AnyTLS + REALITY
2) 安装 Hysteria2 + Surge 端口跳跃
3) 安装 VLESS + REALITY
4) 安装 Snell v5
5) 安装 Snell v6
6) 同时安装全部五种协议
7) 卸载
8) 恢复最新备份
```

选择安装协议后，脚本还会询问端口方式：输入 `1` 或直接回车自动选择未占用的高端口；输入 `2` 可手动填写 NAT 机器映射给你的自定义端口。自定义端口已被占用时会提示改用其他端口；一次安装多个协议时会分别询问各协议端口。

也可以直接指定安装模式：

```bash
# 只安装 AnyTLS + REALITY
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1

# 只安装 Hysteria2 + Surge 端口跳跃
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2

# 只安装 VLESS + REALITY
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode vless

# 只安装 Snell v5
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode snell5

# 只安装 Snell v6
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode snell6

# 同时安装全部五个入站
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode full
```

同时安装时，脚本会生成同一个 `/etc/sing-box/config.json`，其中包含所选协议入站；不会用第二个协议覆盖第一个协议。

---

## 增量安装、重装与恢复

服务器上已经存在 `/etc/sing-box/config.json` 时，脚本默认不再询问“保留旧配置还是生成新配置”，而是直接增量追加本次选择的协议。

例如先安装 `1`，再安装 `2`，之后再安装 `3`，最终会在同一份配置里依次保留 AnyTLS、Hysteria2 和 VLESS，不会覆盖前面已经安装的协议。

- 增量安装：默认行为。保留已有入站，只新增或刷新本次选择的协议入站。
- 保留当前配置：完整保留当前服务端配置和客户端文件，只更新 sing-box；本次输入的新协议参数不会覆盖旧配置。
- 生成新配置：不合并已有入站，直接生成本次选择的协议配置。
- 恢复备份：还原卸载前保存的服务端配置、端口、密码、密钥、客户端文件、证书和 HY2 端口跳跃配置。

也可以直接指定，适合非交互执行：

```bash
# 默认增量安装，不需要额外参数
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode vless

# 沿用旧配置，仅更新 sing-box
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode full --config keep

# 卸载后恢复最近一次有效备份
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --restore

# 生成全新配置，不合并已有入站
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode full --config new
```

---

## 卸载

直接运行统一脚本并选择菜单 `7`，再选择单个协议或全部卸载：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh)
```

也可以用命令直接卸载：

```bash
# 只卸载 AnyTLS + REALITY，保留 HY2
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall anytls

# 只卸载 VLESS + REALITY，保留其他协议
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall vless

# 只卸载 HY2 和端口跳跃规则，保留其他协议
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall hy2

# 只卸载 Snell v5 或 Snell v6
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall snell5
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall snell6

# 卸载全部协议配置，但保留 sing-box 程序
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall all

# 完整卸载全部协议配置并删除 sing-box 软件包
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall all --purge
```

卸载前会要求确认，并把现有配置备份到 `/root/sbox-reality-backups/`。卸载备份采用单份轮换，只保留最新的一份；如果服务器已经没有配置，则不会创建空备份，也不会删除已有的有效备份。非交互执行时可以增加 `--yes`。

只卸载一个协议时，脚本先备份完整配置，再只删除对应的 `anytls-in`、`vless-in`、`hy2-in`、`snell5-in` 或 `snell6-in`，其他入站会继续运行。选择 `all` 时不再依赖入站 tag，而是备份后直接删除全部 sing-box 配置目录和客户端文件。

使用 `--uninstall all --purge` 时还会清理其他脚本常用的 sing-box 安装位置，包括 `/usr/bin/sing-box`、`/usr/local/bin/sing-box`、`/opt/sing-box`、systemd/OpenRC 服务、配置目录、运行数据、日志、cron 和 logrotate 文件。备份目录 `/root/sbox-reality-backups/` 明确排除，始终保留。脚本不会执行危险的全盘模糊删除，避免误删名称中偶然包含 `sing-box` 的个人文件。

---

## Snell v5 / v6

脚本使用 sing-box 1.14 最新 alpha 版提供 Snell 服务端，两个版本均默认选择未占用的随机 TCP 高端口，并生成 Surge 配置片段：

```bash
# Snell v5
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode snell5

# Snell v6（需要支持 v6 的 Surge Beta）
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode snell6
```

可用参数：`--snell5-port`、`--snell6-port`、`--snell5-obfs none|http`、`--snell6-mode default|unshaped|unsafe-raw`。v6 默认使用安全的 `default` 流量整形模式；不要在公网使用明文的 `unsafe-raw`。

所有客户端文件统一保存在 `/root/sing-box/`。sing-box 的 Snell v5 不包含官方 v5 QUIC Proxy，Surge 中的普通 TCP Snell 可以正常使用。

---

## AnyTLS + REALITY

默认配置：

- REALITY 握手域名：`www.apple.com`
- AnyTLS 监听端口：自动随机未占用高端口，默认范围 `20000-65535`

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1
```

安装完成后，终端会直接输出本次随机生成的端口、密码、公钥和客户端 `outbounds`。

---

## 自定义域名

只换 REALITY 握手域名，端口仍然自动随机：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1 -d www.microsoft.com
```

---

## 手动指定端口

例如将 REALITY 握手域名改为 `www.microsoft.com`，AnyTLS 监听端口固定为 `8443`：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1 -d www.microsoft.com -p 8443
```

长参数写法：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1 --domain www.apple.com --port 8443
```

需要显式使用随机端口时：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1 --port auto
```

---

## 自定义随机端口范围

默认随机范围是 `20000-65535`。

如果想限制在某个高端口区间，例如 `30000-50000`：

```bash
HIGH_PORT_MIN=30000 HIGH_PORT_MAX=50000 bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1
```

---

## VLESS + REALITY

默认配置：

- REALITY 握手域名：`www.apple.com`
- VLESS 监听端口：自动随机未占用高端口，默认范围 `20000-65535`
- Flow：`xtls-rprx-vision`
- 客户端指纹：`chrome`

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode vless
```

自定义 VLESS REALITY 域名和端口：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode vless --vless-domain www.apple.com --vless-port auto
```

安装完成后会输出 sing-box 客户端 `outbounds` 和一条 `vless://...` 分享链接。

---

## Hysteria2 + Surge 端口跳跃

默认配置：

- TLS SNI：`www.bing.com`
- Hysteria2 公开 UDP 跳跃端口：`20000-50000`
- sing-box 实际监听端口：默认使用跳跃范围里的第一个端口
- Surge 端口跳跃间隔：`30` 秒
- Hysteria2 Gecko 混淆：默认开启，包长范围 `512-1200`
- 证书：自动生成自签证书，Surge 片段默认带 `skip-cert-verify=true`

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2
```

自定义 SNI、端口范围和跳跃间隔：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2 --sni example.com --ports "20000-50000;7044;8000-9000" --interval 30
```

如果你希望 sing-box 只监听一个固定后端端口，并把公开跳跃端口全部重定向过去：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2 --port 8443 --ports 20000-50000
```

Gecko 默认开启；也可以显式指定，或切换回 Salamander/关闭混淆：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2 --ports 20000-50000 --obfs
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2 --obfs-type salamander
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2 --obfs-type off
```

安装完成后会输出 Hysteria2 URL、Surge 片段和 sing-box 客户端 `outbounds`。Hysteria2 URL 可直接复制到支持 `hysteria2://` 分享链接的客户端，例如：

```text
hysteria2://auto-generated-password@1.2.3.4:20000-50000/?insecure=1&sni=www.bing.com&obfs=gecko&obfs-password=自动生成#HY2
```

Surge 片段示例：

```ini
[Proxy]
HY2=hysteria2,你的VPS_IP,20000,password="自动生成",port-hopping="20000-50000",gecko-password="自动生成",sni="www.bing.com",skip-cert-verify=true,tfo=false

[Proxy Group]
Proxy=select,HY2,DIRECT
```

脚本会为 sing-box 创建 Hysteria2 入站，并通过 nftables 或 iptables 给 UDP 跳跃端口做本机重定向。VPS 防火墙或云厂商安全组需要放行脚本输出的 UDP 跳跃端口范围；如果本机防火墙按重定向后的端口过滤，也要放行 sing-box 实际监听端口。

---

## 安全执行方式

如果你希望先查看脚本内容，再执行：

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh
chmod +x install.sh
bash install.sh
```

带参数执行：

```bash
bash install.sh --mode full -d www.microsoft.com --anytls-port 8443 --vless-port auto --hy2-port 20000 --ports 20000-50000
```

旧的单协议脚本仍然保留，方便兼容已有命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-hysteria2-surge.sh)
```

---

## 功能特性

- 自动安装 / 更新 sing-box
- 菜单选择安装、重装或卸载
- 重装时可沿用旧配置，或自动备份后生成新配置
- 可单独卸载 AnyTLS、VLESS、HY2，或完整卸载
- 默认随机选择当前未被占用的高端口
- 支持手动指定 AnyTLS / VLESS / Hysteria2 监听端口
- 支持自定义随机端口范围
- 自动生成 REALITY 私钥和公钥
- 自动生成 AnyTLS 密码
- 自动生成 VLESS UUID
- 自动生成 `short_id`
- 自动写入服务端配置
- 自动生成客户端 `outbounds` 片段
- 支持自定义 REALITY 握手域名
- 自动执行 `sing-box check`
- 自动启用并重启 sing-box 服务
- 配置简洁，便于二次修改

---

## 系统要求

- Debian / Ubuntu（systemd）或 Alpine Linux（OpenRC）
- root 权限
- 系统使用 `apt` 或 `apk`
- VPS 防火墙或云厂商安全组已放行脚本最终输出的 TCP 端口
- 使用 Hysteria2 端口跳跃时，需要放行脚本最终输出的 UDP 跳跃端口范围

---

## 参数说明

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `-m`, `--mode` | 操作模式：`1`/`anytls`、`2`/`hy2`、`3`/`vless`、`4`/`full`、`5`/`uninstall`、`6`/`restore` | 交互菜单 |
| `--restore` | 直接恢复最近一次有效备份 | 关闭 |
| `--config` | 选择 `merge` 增量合并、`keep` 沿用当前配置、`restore` 恢复最近备份或 `new` 生成新配置 | `merge` |
| `--uninstall` | 卸载范围：`anytls`、`vless`、`hy2` 或 `all` | 卸载子菜单 |
| `--purge` | 卸载全部配置时同时删除 sing-box 软件包 | 关闭 |
| `-y`, `--yes` | 跳过卸载确认，适合非交互执行 | 关闭 |
| `-d`, `--domain` | REALITY 握手域名 | `www.apple.com` |
| `-p`, `--port` | 当前单协议模式的监听端口；同时安装时建议使用各协议端口选项 | `auto` |
| `--anytls-port` | AnyTLS TCP 监听端口 | `auto` |
| `--vless-domain` | VLESS REALITY 握手域名 | `www.apple.com` |
| `--vless-port` | VLESS TCP 监听端口 | `auto` |
| `--hy2-port` | Hysteria2 UDP 实际监听端口；同时安装时推荐使用 | `auto` |
| `-h`, `--help` | 查看帮助 | - |

环境变量：

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `HIGH_PORT_MIN` | 随机端口最小值 | `20000` |
| `HIGH_PORT_MAX` | 随机端口最大值 | `65535` |
| `INSTALL_MODE` | 安装模式 | 交互菜单 |
| `PORT` | 兼容旧脚本的监听端口；会按当前模式分配给对应协议 | 空 |
| `ANYTLS_PORT` | AnyTLS TCP 监听端口 | `auto` |
| `VLESS_DOMAIN` | VLESS REALITY 握手域名 | `www.apple.com` |
| `VLESS_PORT` | VLESS TCP 监听端口 | `auto` |
| `HY2_PORT` | Hysteria2 UDP 实际监听端口 | `auto` |

示例：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1 -d www.apple.com
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1 -d www.microsoft.com -p 8443
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode vless --vless-domain www.apple.com --vless-port auto
HIGH_PORT_MIN=30000 HIGH_PORT_MAX=50000 bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode full --anytls-port 8443 --vless-port auto --hy2-port 20000 --ports 20000-50000
```

Hysteria2 + Surge 参数：

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `-s`, `--sni` | TLS SNI 和自签证书 CN | `www.bing.com` |
| `-p`, `--port` | sing-box Hysteria2 实际监听端口；可填具体端口或 `auto` | `auto` |
| `-P`, `--ports` | Surge `port-hopping` 端口或端口范围，多个值用 `;` 或 `,` 分隔 | `20000-50000` |
| `-i`, `--interval` | 端口跳跃间隔秒数，最小 `5` | `30` |
| `--up` | 服务端上传带宽 Mbps，可选 | 不限制 |
| `--down` | 服务端下载带宽 Mbps，可选 | 不限制 |
| `--obfs` | 开启 Gecko 混淆 | 已开启 |
| `--obfs-type` | 混淆类型：`gecko`、`salamander` 或 `off` | `gecko` |
| `--obfs-password` | 指定 Gecko/Salamander 混淆密码 | 自动生成 |
| `--gecko-min`, `--gecko-max` | Gecko 最小/最大包长 | `512` / `1200` |
| `--cert`, `--key` | 使用已有 TLS 证书和私钥 | 自动生成自签证书 |
| `--name` | Surge 代理名称 | `HY2` |

---

## 文件输出

所有客户端输出统一保存在权限为 `700` 的 `/root/sing-box/` 目录。每种协议都会生成 sing-box JSON、URL 文件、Surge 文件和安装信息：

```text
服务端配置：/etc/sing-box/config.json
统一安装信息：/root/sing-box/all-info.txt
sing-box：/root/sing-box/anytls-sing-box.json
URL：/root/sing-box/anytls-url.txt
Surge 兼容性说明：/root/sing-box/anytls-surge.conf
安装信息：/root/sing-box/anytls-info.txt
```

VLESS + REALITY 会生成：

```text
服务端配置：/etc/sing-box/config.json
sing-box：/root/sing-box/vless-sing-box.json
URL：/root/sing-box/vless-url.txt
Surge 兼容性说明：/root/sing-box/vless-surge.conf
安装信息：/root/sing-box/vless-info.txt
```

Hysteria2 + Surge 脚本会生成：

```text
服务端配置：/etc/sing-box/config.json
sing-box：/root/sing-box/hysteria2-sing-box.json
URL：/root/sing-box/hysteria2-url.txt
Surge：/root/sing-box/hysteria2-surge.conf
安装信息：/root/sing-box/hysteria2-info.txt
端口跳跃 helper：/usr/local/bin/sing-box-hy2-port-hopping
端口跳跃 systemd drop-in（Debian/Ubuntu）：/etc/systemd/system/sing-box.service.d/10-hy2-port-hopping.conf
端口跳跃 OpenRC 服务（Alpine）：/etc/init.d/sing-box-hy2-port-hopping
```

Snell v5/v6 分别生成 `snell-v5-*` 和 `snell-v6-*` 文件；其中 `*-sing-box.json`、`*-url.txt`、`*-surge.conf` 对应三种格式。Snell 没有官方统一 URL 标准，因此 URL 文件使用常见约定格式。

Surge 官方不支持 VLESS + REALITY，也不支持 AnyTLS 的 REALITY 扩展，所以这两种协议的 `*-surge.conf` 会保存明确的兼容性说明，不会生成无法连接的假配置。

查看客户端 `outbounds`：

```bash
cat /root/sing-box/anytls-sing-box.json
```

查看 VLESS 分享链接：

```bash
cat /root/sing-box/vless-url.txt
```

查看 Surge 片段：

```bash
cat /root/sing-box/hysteria2-surge.conf
```

查看 Hysteria2 URL：

```bash
cat /root/sing-box/hysteria2-url.txt
```

客户端输出只包含：

```json
{
  "outbounds": [
    {
      "type": "anytls",
      "tag": "proxy",
      "server": "你的VPS_IP",
      "server_port": "脚本最终输出的端口",
      "password": "自动生成",
      "tls": {
        "enabled": true,
        "server_name": "www.apple.com",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "自动生成",
          "short_id": "自动生成"
        }
      }
    }
  ]
}
```

如果你的客户端已经有完整 sing-box 配置，不要重复粘贴第二个 `outbounds`。只需要把里面的 AnyTLS 节点合并进你原来的 `outbounds` 数组。

---

## 常用命令

查看状态：

```bash
systemctl status sing-box --no-pager
# Alpine
rc-service sing-box status
```

查看日志：

```bash
journalctl -u sing-box -f
# Alpine
tail -f /var/log/messages
```

重启：

```bash
systemctl restart sing-box
# Alpine
rc-service sing-box restart
```

检查配置：

```bash
sing-box check -c /etc/sing-box/config.json
```

查看生成的信息：

```bash
cat /root/sing-box/all-info.txt
```

---

## 常见问题

### 客户端提示 `decode config: invalid character`

这是 JSON 格式错误，不是协议连接失败。

常见原因：

- 两个 outbound 节点中间少了英文逗号
- 把完整 `outbounds` 对象重复粘进已有配置
- 在 JSON 里粘贴了中文说明、注释或多余字符

正确方式：如果原配置已经有 `outbounds`，只复制脚本生成文件里 `outbounds` 数组内部的 AnyTLS 节点进去。

---

### 随机端口无法连接

脚本只会检查 VPS 本机当前是否监听该端口，不会自动修改云厂商安全组。

如果无法连接，优先检查：

- VPS 系统防火墙
- 云厂商安全组
- 面板防火墙
- 客户端是否使用了最新生成的端口

例如：

```bash
ufw allow 端口/tcp
```

---

### 重新运行脚本后客户端不能用了

每次重新运行脚本都会重新生成：

```text
port
password
private_key / public_key
short_id
```

所以客户端必须同步更新为最新生成的：

```bash
/root/sing-box/anytls-sing-box.json
```

---

### Surge 能不能直接用？

这个脚本生成的是 sing-box AnyTLS + REALITY 配置。客户端需要支持 AnyTLS + REALITY。建议优先使用 sing-box 客户端或基于新版 sing-box core 的客户端测试。

如果要给 Surge 使用，请运行统一脚本的 Hysteria2 模式：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2
```

它会部署 sing-box Hysteria2，并生成 Surge 的 Hysteria2 `port-hopping` 配置片段。

---

## 项目定位

`sbox-reality` 是一个面向个人 VPS 快速部署场景的 Bash 自动化脚本，重点是：

- 少步骤
- 易阅读
- 易修改
- 服务端配置完整
- 客户端片段干净
- 默认避开常见 80 / 443 端口冲突

---

## License

MIT
