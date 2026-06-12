# sbox-reality

专业、轻量、可读的 **sing-box AnyTLS + REALITY** 一键安装脚本。

本项目专为 Debian / Ubuntu VPS 编写，默认自动选择一个当前未被占用的随机高端口，完成服务端部署，并生成可直接合并到客户端配置中的 `outbounds` 片段。

---

## 一键安装

默认配置：

- REALITY 握手域名：`www.apple.com`
- AnyTLS 监听端口：自动随机未占用高端口，默认范围 `20000-65535`

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh)
```

安装完成后，终端会直接输出本次随机生成的端口、密码、公钥和客户端 `outbounds`。

---

## 自定义域名

只换 REALITY 握手域名，端口仍然自动随机：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh) -d www.microsoft.com
```

---

## 手动指定端口

例如将 REALITY 握手域名改为 `www.microsoft.com`，AnyTLS 监听端口固定为 `8443`：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh) -d www.microsoft.com -p 8443
```

长参数写法：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh) --domain www.apple.com --port 8443
```

需要显式使用随机端口时：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh) --port auto
```

---

## 自定义随机端口范围

默认随机范围是 `20000-65535`。

如果想限制在某个高端口区间，例如 `30000-50000`：

```bash
HIGH_PORT_MIN=30000 HIGH_PORT_MAX=50000 bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh)
```

---

## 安全执行方式

如果你希望先查看脚本内容，再执行：

```bash
curl -fsSL -o install-anytls-reality.sh https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh
chmod +x install-anytls-reality.sh
bash install-anytls-reality.sh
```

带参数执行：

```bash
bash install-anytls-reality.sh -d www.microsoft.com -p 8443
```

---

## 功能特性

- 自动安装 / 更新 sing-box
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

- Debian / Ubuntu
- root 权限
- 系统使用 `apt`
- VPS 防火墙或云厂商安全组已放行脚本最终输出的 TCP 端口

---

## 参数说明

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `-d`, `--domain` | REALITY 握手域名 | `www.apple.com` |
| `-p`, `--port` | AnyTLS 监听端口；可填具体端口或 `auto` | `auto` |
| `-h`, `--help` | 查看帮助 | - |

环境变量：

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `HIGH_PORT_MIN` | 随机端口最小值 | `20000` |
| `HIGH_PORT_MAX` | 随机端口最大值 | `65535` |

示例：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh) -d www.apple.com
bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh) -d www.microsoft.com -p 8443
HIGH_PORT_MIN=30000 HIGH_PORT_MAX=50000 bash <(curl -fsSL https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install-anytls-reality.sh)
```

---

## 文件输出

安装完成后会生成：

```text
服务端配置：/etc/sing-box/config.json
客户端 outbounds：/root/client-outbounds-anytls-reality.json
安装信息：/root/anytls-reality-info.txt
```

查看客户端 `outbounds`：

```bash
cat /root/client-outbounds-anytls-reality.json
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
```

查看日志：

```bash
journalctl -u sing-box -f
```

重启：

```bash
systemctl restart sing-box
```

检查配置：

```bash
sing-box check -c /etc/sing-box/config.json
```

查看生成的信息：

```bash
cat /root/anytls-reality-info.txt
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
