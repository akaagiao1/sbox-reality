# sbox-reality

一个用于 Debian / Ubuntu VPS 的 sing-box AnyTLS + REALITY 安装脚本。

当前仓库脚本是按实际部署需求整理的轻量版：服务端生成完整 sing-box 配置，客户端只输出 `outbounds` 片段，方便合并到已有 sing-box 客户端配置中。

说明：本项目不是 sing-box 官方项目。协议与内核能力来自 sing-box，本仓库只提供自动化安装与配置生成脚本。

## 功能特性

- 安装 / 更新 sing-box
- 自动生成 REALITY 私钥和公钥
- 自动生成 AnyTLS 密码
- 自动生成 short_id
- 默认 REALITY 握手域名：`www.apple.com`
- 默认监听端口：`443`
- 支持自定义握手域名和监听端口
- 自动写入服务端配置：`/etc/sing-box/config.json`
- 自动生成客户端 outbounds 片段：`/root/client-outbounds-anytls-reality.json`
- 自动执行 `sing-box check`
- 自动启用并重启 sing-box 服务

## 系统要求

- Debian / Ubuntu
- root 权限
- 系统使用 apt
- VPS 防火墙或云厂商安全组已放行对应 TCP 端口

## 安装方式

克隆仓库：

```bash
git clone https://github.com/akaagiao1/sbox-reality.git
cd sbox-reality
```

赋予执行权限：

```bash
chmod +x install-anytls-reality.sh
```

默认安装：

```bash
bash install-anytls-reality.sh
```

默认配置：

```text
握手域名：www.apple.com
监听端口：443
```

## 自定义域名和端口

例如使用 `www.microsoft.com` 作为 REALITY 握手域名，监听端口改成 `8443`：

```bash
bash install-anytls-reality.sh -d www.microsoft.com -p 8443
```

也可以使用长参数：

```bash
bash install-anytls-reality.sh --domain www.apple.com --port 443
```

## 文件输出

安装完成后会生成：

```text
服务端配置：/etc/sing-box/config.json
客户端 outbounds：/root/client-outbounds-anytls-reality.json
安装信息：/root/anytls-reality-info.txt
```

查看客户端 outbounds：

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
      "server_port": 443,
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

如果你的客户端已有完整 sing-box 配置，不要重复粘贴第二个 `outbounds`。只需要把里面的 AnyTLS 节点合并进你原来的 `outbounds` 数组。

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

## 常见问题

### 客户端提示 decode config: invalid character

这是 JSON 格式错误，不是协议连接失败。

常见原因：

- 两个 outbound 节点中间少了英文逗号
- 把完整 `outbounds` 对象重复粘进已有配置
- 在 JSON 里粘贴了中文说明、注释或多余字符

正确方式：如果原配置已经有 `outbounds`，只复制脚本生成文件里 `outbounds` 数组内部的 AnyTLS 节点进去。

### 改端口后无法连接

检查 VPS 防火墙、安全组、防火墙面板是否放行对应 TCP 端口。

例如：

```bash
ufw allow 8443/tcp
```

### 重新运行脚本后客户端不能用了

每次重新运行脚本都会重新生成：

```text
password
private_key / public_key
short_id
```

所以客户端必须同步更新为最新生成的：

```bash
/root/client-outbounds-anytls-reality.json
```

### Surge 能不能直接用？

这个脚本生成的是 sing-box AnyTLS + REALITY 配置。客户端需要支持 AnyTLS + REALITY。建议优先使用 sing-box 客户端或基于新版 sing-box core 的客户端测试。

## 项目说明

本仓库脚本面向个人 VPS 快速部署场景，重点是简洁、可读、可改。

- 不是 sing-box 官方脚本
- 不内置订阅面板
- 不生成 Clash/Mihomo 配置
- 不保证所有第三方客户端兼容

## License

MIT
