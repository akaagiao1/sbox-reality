# WARP 按规则分流设计

日期：2026-10-21

## 背景

`install.sh` 当前负责安装和合并 sing-box 服务端配置，但没有 Cloudflare WARP endpoint 或按服务分流能力。本改动允许用户输入 `youtube`、`netflix`、`openai` 等服务名，将对应流量交给 WARP，其余流量继续遵循现有路由。

WARP 注册流程和 WireGuard 参数格式参考 [`akaagiao1/sing-box-warp`](https://github.com/akaagiao1/sing-box-warp) 的 `generate-singbox-1.14-warp.sh`。规则集来自 [`MetaCubeX/meta-rules-dat`](https://github.com/MetaCubeX/meta-rules-dat/tree/sing) 的 `sing/geo-lite/geosite` 目录。

## 目标

- 支持一次选择多个 geosite 规则，例如 `youtube,netflix,openai`。
- 支持交互安装和命令行自动化。
- 支持在不重装协议的情况下更新或关闭 WARP 分流。
- 首次注册的 WARP 凭据安全保存并在后续操作中复用。
- 每次更新使用完整列表覆盖脚本之前管理的 WARP 规则。
- 保留现有 inbounds、outbounds、endpoints、路由规则和 `route.final`；仅增删脚本命名空间下的对象。
- 所有配置更新都先校验并可在失败时回滚。

## 非目标

- 不支持 GeoIP 规则或 `geosite:`/`geoip:` 类型前缀。
- 不把所有流量默认路由到 WARP。
- 不在运行时下载并执行 `sing-box-warp` 仓库中的脚本。
- 不单独提供 WARP 本地 SOCKS/HTTP 代理入口。
- 不在测试过程中向 Cloudflare 注册真实设备。

## 用户接口

### 命令行

```bash
# 只更新已有配置的 WARP 分流
bash install.sh --warp-rules youtube,netflix

# 安装协议并同时配置 WARP
bash install.sh --mode anytls --warp-rules youtube,netflix

# 关闭分流，保留凭据
bash install.sh --warp-off

# 重新注册凭据，并沿用已有规则
bash install.sh --warp-reset

# 重新注册凭据，并覆盖规则
bash install.sh --warp-reset --warp-rules youtube,openai
```

`--warp-rules` 是独立动作：未指定安装模式时只修改现有配置；与 `--mode` 同用时纳入本次安装的配置写入流程。独立启用或更新要求 `/etc/sing-box/config.json` 已存在且有效。

`--warp-off` 删除脚本管理的 endpoint、规则集和路由规则，但保留凭据。它在已经关闭时成功退出，保证重复执行安全。

`--warp-reset` 删除复用意图并注册新凭据。单独使用时读取配置中现有的 WARP 规则列表；当前没有 WARP 规则时应报错，提示同时传入 `--warp-rules`。

互相冲突的参数（例如 `--warp-off` 与 `--warp-rules` 或 `--warp-reset`）在修改文件前报错。

### 交互模式

无命令行参数进入协议安装流程时，在现有协议输入结束后询问是否启用 WARP。选择启用后，读取规则列表。列表接受英文逗号、中文逗号、顿号、分号或空白分隔。

规则名统一转为小写并去重，只允许 ASCII 字母、数字、下划线和连字符。空名称、路径字符、URL 和其他符号都拒绝。再次配置时，新列表完整覆盖旧列表。

## 实现组织

所有实现保留在 `install.sh` 中，不新增运行时模块。为控制主脚本复杂度，相关状态和函数集中放置，并统一使用 `WARP_` 变量和 `warp_` 函数前缀。主要职责分为：

1. 参数解析和交互输入。
2. 规则名规范化及远程资源校验。
3. X25519 密钥生成和 Cloudflare 注册响应解析。
4. 凭据加载、校验和临时保存。
5. sing-box endpoint、rule_set 与 route 规则的 JSON 生成和合并。
6. 原子写入、服务重启和失败回滚。

上游 `sing-box-warp` 仅作为实现依据。注册请求的客户端版本、接口和 WireGuard peer 参数在本仓库中显式维护，以便审查和测试。

## sing-box 配置模型

目标 sing-box 版本使用顶层 `endpoints` 中的 WireGuard endpoint：

```json
{
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "sbox-warp-out",
      "mtu": 1280,
      "address": ["<warp-v4>/32", "<warp-v6>/128"],
      "private_key": "<private-key>",
      "peers": [
        {
          "address": "engage.cloudflareclient.com",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": ["0.0.0.0/0", "::/0"],
          "persistent_keepalive_interval": 30,
          "reserved": [0, 0, 0]
        }
      ]
    }
  ]
}
```

脚本增加一个专门用于下载规则的 direct outbound：

```json
{
  "type": "direct",
  "tag": "sbox-warp-direct"
}
```

每个服务对应一个远程二进制规则集：

```json
{
  "type": "remote",
  "tag": "sbox-warp-geosite-youtube",
  "format": "binary",
  "url": "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/youtube.srs",
  "download_detour": "sbox-warp-direct"
}
```

所有所选规则集合并到一条路由规则：

```json
{
  "rule_set": [
    "sbox-warp-geosite-youtube",
    "sbox-warp-geosite-netflix"
  ],
  "action": "route",
  "outbound": "sbox-warp-out"
}
```

配置中还会在该规则前加入 `{ "action": "sniff" }`，帮助从 TLS/HTTP 流量识别域名。脚本管理的 sniff 和分流规则放在现有普通规则之前，使用户显式选择的服务优先走 WARP。`route.final` 保持不变，因此未匹配流量继续使用原配置的最终路由。

## 合并所有权

脚本只拥有以下对象：

- endpoint tag `sbox-warp-out`
- outbound tag `sbox-warp-direct`
- 以 `sbox-warp-geosite-` 开头的 rule_set tag
- outbound 为 `sbox-warp-out` 的 route 规则
- 紧邻上述 route 规则、由脚本加入的 sniff 规则

更新时先删除这些受管对象，再插入由新列表生成的对象。其他配置项按原顺序保留。关闭 WARP 使用相同的识别规则删除受管对象。

为可靠识别 sniff 规则，生成的 sniff 与分流规则作为 route rules 的前两个元素成对管理；更新或关闭时只移除位于受管分流规则之前且内容完全等于 `{ "action": "sniff" }` 的一个规则。已有其他 sniff 规则不删除。

如果现有配置已经占用了任一受管 tag，但结构不符合本功能生成的对象，脚本在修改前报冲突，不覆盖未知配置。

## 凭据生命周期

凭据路径为 `/etc/sing-box/sbox-warp-credentials.json`。`/etc/sing-box` 和凭据文件的权限分别保持为 `700` 和 `600`。凭据至少包含：

- schema 版本
- X25519 私钥和公钥
- Cloudflare 分配的 IPv4 与 IPv6 地址
- 解码后的三个 `reserved` 字节
- WARP peer 主机、端口和公钥
- MTU

首次启用时生成 X25519 密钥，并向 `https://api.cloudflareclient.com/v0a2158/reg` 注册。响应缺少地址、`client_id` 或字段格式无效时注册失败。

普通规则更新只读取并校验现有凭据。`--warp-reset` 生成新凭据到临时文件；正式配置验证并写入成功后才替换旧凭据。`--warp-off` 不删除凭据。彻底卸载 sing-box 时删除凭据；备份和恢复流程包含凭据文件。

## 事务和错误处理

启用、更新或重置按以下顺序执行：

1. 解析参数并拒绝冲突组合。
2. 规范化、去重并校验规则名。
3. 对每个 MetaCubeX raw URL 执行有限超时和重试的可达性检查。
4. 读取已有凭据，或把新注册结果写入临时文件。
5. 读取并验证现有 sing-box 配置。
6. 在临时文件中合并 WARP 对象。
7. 使用 `jq` 校验 JSON，并运行 `sing-box check -c`。
8. 创建包含配置和凭据的备份。
9. 用权限 `600` 原子替换正式文件。
10. 重启 sing-box 并检查服务启动结果。

步骤 1 至 7 失败时不修改正式文件。步骤 9 或 10 失败时恢复配置和凭据的备份，并尝试重新启动原配置。错误信息指出失败阶段和相关规则名或文件。

纯安装流程把协议变更和 WARP 变更合并为同一个临时配置，只执行一次校验和正式替换，避免中间状态。

关闭操作同样通过临时配置、`sing-box check`、备份、原子替换和重启流程完成。

## 测试与验收

自动验证覆盖：

- `bash -n install.sh`
- 分隔符处理、小写转换、稳定去重和非法名称拒绝
- 多个 geosite URL 和 tag 的生成
- Cloudflare 成功响应、缺字段响应及无效 `client_id` 的模拟
- 已有凭据复用，规则更新不触发注册
- 覆盖规则列表会移除旧受管 ruleset
- `--warp-off` 移除受管对象并保留凭据
- WARP 对象插入后只新增 `sbox-warp-direct`，并保留自定义 inbounds、outbounds、endpoints、route rules 和 `route.final`
- 受管 tag 与未知用户配置冲突时拒绝覆盖
- 规则校验、注册、JSON 合并、sing-box check 和服务重启失败时正式文件保持或恢复
- 生成配置通过仓库开发环境中的 sing-box 检查
- MetaCubeX 示例规则 `youtube.srs` 的真实 URL 可访问

验收示例：执行 `bash install.sh --warp-rules youtube` 后，配置包含 `sbox-warp-geosite-youtube` 和指向 `sbox-warp-out` 的路由规则；未匹配 YouTube 的流量仍遵循原有路由。再次执行 `--warp-rules netflix` 后，YouTube 规则被移除且 Netflix 规则生效，不发生新的 Cloudflare 注册。

## 文档变更

README 将增加 WARP 功能说明、交互和命令行示例、支持的规则来源、覆盖更新语义、`--warp-off`/`--warp-reset` 行为，以及凭据文件不可公开分享的提示。
