# sbox-reality

专业、轻量、可读的 **sing-box** 一键安装脚本。

支持：

- **AnyTLS + REALITY**
- **Hysteria2 + Surge 端口跳跃**
- **同时安装两个入站到同一个 sing-box 配置**
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
3) 同时安装两者
4) 卸载
5) 恢复最新备份
```

也可以直接指定安装模式：

```bash
# 只安装 AnyTLS + REALITY
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1

# 只安装 Hysteria2 + Surge 端口跳跃
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 2

# 同时安装两个入站
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode both
```

同时安装时，脚本会生成同一个 `/etc/sing-box/config.json`，其中包含 `anytls-in` 和 `hy2-in` 两个入站；不会用第二个协议覆盖第一个协议。

---

## 重新安装与保留配置

服务器上已经存在 `/etc/sing-box/config.json` 时，脚本会询问保留旧配置还是生成新配置。卸载后即使当前配置已经删除，只要 `/root/sbox-reality-backups/` 中存在有效备份，脚本也会询问：

```text
1) 恢复此备份
2) 忽略备份并生成新配置
3) 取消
```

- 恢复备份：还原服务端配置、端口、密码、密钥、客户端文件、证书和 HY2 端口跳跃配置，然后重新安装或更新 sing-box。
- 保留当前配置：完整保留当前服务端配置和客户端文件，只更新 sing-box；本次输入的新协议参数不会覆盖旧配置。
- 生成新配置：忽略旧备份，或者先备份当前配置，再生成全新配置。

也可以直接指定，适合非交互执行：

```bash
# 沿用旧配置，仅更新 sing-box
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode both --config keep

# 卸载后恢复最近一次有效备份
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --restore

# 备份旧配置后生成全新配置
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode both --config new
```

---

## 卸载

直接运行统一脚本并选择菜单 `4`，再选择只卸载 AnyTLS、只卸载 Hysteria2，或同时卸载两者：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh)
```

也可以用命令直接卸载：

```bash
# 只卸载 AnyTLS + REALITY，保留 HY2
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall anytls

# 只卸载 HY2 和端口跳跃规则，保留 AnyTLS
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall hy2

# 卸载两个配置，但保留 sing-box 程序
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall all

# 完整卸载两个配置并删除 sing-box 软件包
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --uninstall all --purge
```

卸载前会要求确认，并把现有配置备份到 `/root/sbox-reality-backups/`。卸载备份采用单份轮换，只保留最新的一份；如果服务器已经没有配置，则不会创建空备份，也不会删除已有的有效备份。非交互执行时可以增加 `--yes`。只卸载一个协议时，脚本只删除对应的 `anytls-in` 或 `hy2-in`，另一个协议会继续运行；卸载 HY2 还会清理端口跳跃规则以及 systemd/OpenRC 服务配置。

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
HY2 = hysteria2, 你的VPS_IP, 20000, password=自动生成, skip-cert-verify=true, sni=www.bing.com, port-hopping="20000-50000", port-hopping-interval=30, gecko-password=自动生成

[Proxy Group]
Proxy = select, HY2, DIRECT
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
bash install.sh --mode both -d www.microsoft.com --anytls-port 8443 --hy2-port 20000 --ports 20000-50000
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
- 可单独卸载 AnyTLS、HY2，或完整卸载
- 默认随机选择当前未被占用的高端口
- 支持手动指定 AnyTLS 监听端口
- 支持自定义随机端口范围
- 自动生成 REALITY 私钥和公钥
- 自动生成 AnyTLS 密码
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
| `-m`, `--mode` | 操作模式：`1`/`anytls`、`2`/`hy2`、`3`/`both`、`4`/`uninstall`、`5`/`restore` | 交互菜单 |
| `--restore` | 直接恢复最近一次有效备份 | 关闭 |
| `--config` | 选择 `keep` 沿用当前配置、`restore` 恢复最近备份或 `new` 生成新配置 | 交互询问 |
| `--uninstall` | 卸载范围：`anytls`、`hy2` 或 `all` | 卸载子菜单 |
| `--purge` | 卸载全部配置时同时删除 sing-box 软件包 | 关闭 |
| `-y`, `--yes` | 跳过卸载确认，适合非交互执行 | 关闭 |
| `-d`, `--domain` | REALITY 握手域名 | `www.apple.com` |
| `-p`, `--port` | 当前模式的监听端口；`--mode 1` 时对应 AnyTLS，`--mode 2` 时对应 Hysteria2 | `auto` |
| `--anytls-port` | AnyTLS TCP 监听端口 | `auto` |
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
| `HY2_PORT` | Hysteria2 UDP 实际监听端口 | `auto` |

示例：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1 -d www.apple.com
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1 -d www.microsoft.com -p 8443
HIGH_PORT_MIN=30000 HIGH_PORT_MAX=50000 bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode 1
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh) --mode both --anytls-port 8443 --hy2-port 20000 --ports 20000-50000
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

安装完成后会生成：

```text
服务端配置：/etc/sing-box/config.json
统一安装信息：/root/sbox-reality-info.txt
客户端 outbounds：/root/client-outbounds-anytls-reality.json
安装信息：/root/anytls-reality-info.txt
```

Hysteria2 + Surge 脚本会生成：

```text
服务端配置：/etc/sing-box/config.json
sing-box 客户端 outbounds：/root/client-outbounds-hysteria2.json
Hysteria2 URL：/root/hysteria2-url.txt
Surge 配置片段：/root/surge-hysteria2.conf
安装信息：/root/hysteria2-surge-info.txt
端口跳跃 helper：/usr/local/bin/sing-box-hy2-port-hopping
端口跳跃 systemd drop-in（Debian/Ubuntu）：/etc/systemd/system/sing-box.service.d/10-hy2-port-hopping.conf
端口跳跃 OpenRC 服务（Alpine）：/etc/init.d/sing-box-hy2-port-hopping
```

查看客户端 `outbounds`：

```bash
cat /root/client-outbounds-anytls-reality.json
```

查看 Surge 片段：

```bash
cat /root/surge-hysteria2.conf
```

查看 Hysteria2 URL：

```bash
cat /root/hysteria2-url.txt
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
cat /root/sbox-reality-info.txt
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
/root/client-outbounds-anytls-reality.json
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
