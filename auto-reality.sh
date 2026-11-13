#!/usr/bin/env bash
# 自动筛选邻居域名, 并用推荐域名安装 sing-box 的 AnyTLS + VLESS REALITY。
#
# 用法 (在 Linux VPS 上, root):
#   bash auto-reality.sh                              # 扫描后装 AnyTLS + VLESS
#   bash auto-reality.sh --mode anytls                 # 只装 AnyTLS + REALITY
#   bash auto-reality.sh --mode vless                  # 只装 VLESS + REALITY
#   bash auto-reality.sh --csv file.csv                # 用已有扫描结果, 跳过扫描
#   bash auto-reality.sh --mode anytls --csv file.csv
#
# 流程: 扫本机公网 IPv4 所在 /23 → RealityChecker 筛选 → 握手最快的合格域名
# 做 AnyTLS 和 VLESS 的 dest/SNI, 再调 install.sh 装好。没有合格域名就停,
# 不退回默认域名 (install.sh 默认是 www.apple.com)。重复运行会按 install.sh
# 的增量规则刷新两个 Reality 入站, 不会覆盖其他已装协议。
#
# 扫描脚本来自 xray-reality-onekey 仓库的固定版本 (单点维护, 不用两边改):
# 扫描器/检测器是 glibc 链接的, Alpine 上跑要装 gcompat, 缺 python3 也会
# 自动装, 这些都在扫描脚本里处理 (Alpine 走 apk, Debian/Ubuntu 走 apt)。
set -Eeuo pipefail

error() { printf '[错误] %s\n' "$*" >&2; exit 1; }
info() { printf '[INFO] %s\n' "$*"; }

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  printf '%s\n' '用法: bash auto-reality.sh [--mode anytls,vless] [--csv 已有扫描结果.csv]' \
    '默认在本机扫描公网 IPv4 所在 /23, 用推荐域名安装 AnyTLS + VLESS REALITY。' \
    '--mode 只接受 anytls / vless (1 = anytls, 3 = vless), 其他协议请直接用 install.sh 装。' \
    '--csv 使用已有扫描结果, 跳过扫描。无合格候选时停止, 不自动安装。'
  exit 0
fi

# ---- 参数: --mode 和 --csv ----
modes="anytls,vless"
csv=""
while (( $# )); do
  case "$1" in
    --mode)
      shift; [[ $# -gt 0 ]] || error '--mode 需要值, 如 --mode anytls 或 --mode anytls,vless'
      modes="$1"
      ;;
    --csv)
      shift; [[ $# -gt 0 ]] || error '--csv 需要文件路径'
      csv="$1"
      ;;
    *) error "未知参数: $1, 请用 --help 查看用法" ;;
  esac
  shift
done

# --mode 只接受 Reality 协议: 名字或菜单编号, 中文逗号也认
modes="${modes//，/,}"
modes="${modes// /}"
normalized_modes=""
IFS=',' read -r -a mode_items <<< "$modes"
for item in "${mode_items[@]}"; do
  case "$item" in
    anytls|1) normalized_modes="${normalized_modes:+$normalized_modes,}anytls" ;;
    vless|3) normalized_modes="${normalized_modes:+$normalized_modes,}vless" ;;
    *) error "扫描只给 Reality 协议挑域名, --mode 里不能有 $item (hy2 / snell / ss2022 请直接用 install.sh 装)" ;;
  esac
done
[[ -n "$normalized_modes" ]] || error '--mode 不能为空'
# 去重 (anytls,anytls 这种写重复了也没事); 这里故意不加引号, 让逗号换空格后按词拆开
deduped_modes="$(printf '%s\n' ${normalized_modes//,/ } | awk '!seen[$0]++' | paste -sd, -)"
modes="$deduped_modes"

if [[ -n "$csv" ]]; then
  [[ -f "$csv" && -r "$csv" ]] || error "CSV 文件不存在或不可读: $csv (先跑扫描生成, 或确认路径)"
  csv="$(cd "$(dirname "$csv")" && pwd)/$(basename "$csv")"
fi

[[ $(uname -s) == Linux ]] || error '需要 Linux (Debian / Ubuntu / Alpine)。'
[[ $(id -u) == 0 ]] || error '请以 root 运行此脚本。'
command -v curl >/dev/null 2>&1 || error '需要 curl；请先安装 curl 和 ca-certificates。'

workdir=$(mktemp -d "${TMPDIR:-/tmp}/sbox-auto-reality.XXXXXXXX") || error '无法创建临时目录。'
trap 'rm -rf -- "$workdir"' EXIT

# 扫描脚本固定版本 (xray-reality-onekey, 含 Alpine 的 python3/gcompat 自动安装)
scan_base='https://raw.githubusercontent.com/akaagiao1/xray-reality-onekey/25f84f02c416e2c0f2bf89702abf2f11465e1dcb'
printf '[1/3] 下载扫描脚本...\n'
curl -fsSL --retry 3 --connect-timeout 15 -o "$workdir/scan-neighbors.sh" "$scan_base/scan-neighbors.sh" || error '扫描脚本下载失败。'

printf '[2/3] 扫描和筛选候选域名...\n'
if [[ -n "$csv" ]]; then
  (cd "$workdir" && bash ./scan-neighbors.sh --csv "$csv" --recommend-file "$workdir/recommended.txt") || error '候选检测失败，已停止安装。'
else
  printf '注意：将从本机扫描公网 IP 所在的 /23；仅扫描获授权的网段。\n'
  (cd "$workdir" && bash ./scan-neighbors.sh --recommend-file "$workdir/recommended.txt") || error '扫描或检测失败，已停止安装。'
fi
[[ -s "$workdir/recommended.txt" ]] || error '没有符合条件的推荐域名，已停止安装。'
IFS= read -r selected < "$workdir/recommended.txt" || error '无法读取推荐域名。'
[[ $selected =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && $selected == *.* && $selected != *..* ]] || error '推荐域名格式无效，已停止安装。'

printf '[3/3] 采用推荐域名 %s，安装 %s ...\n' "$selected" "$modes"
install_ref="${SBOX_REALITY_INSTALL_REF:-main}"
expected_sha256="${SBOX_REALITY_INSTALL_SHA256:-}"
[[ "$install_ref" =~ ^[A-Za-z0-9._/-]+$ ]] || error 'SBOX_REALITY_INSTALL_REF 格式无效'
curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
  --connect-timeout 10 --max-time 60 \
  -o "$workdir/install.sh" \
  "https://raw.githubusercontent.com/akaagiao1/sbox-reality/${install_ref}/install.sh" || error '安装脚本下载失败。'
if [[ -n "$expected_sha256" ]]; then
  printf '%s  %s\n' "$expected_sha256" "$workdir/install.sh" | sha256sum -c - >/dev/null || error 'install.sh SHA-256 校验失败'
fi
# --domain 同时定 AnyTLS 和 VLESS 的 dest/SNI; 端口不指定, install.sh 自动挑未占用高端口;
# -y 跳过确认。已有配置时按 install.sh 的增量规则刷新两个 Reality 入站。
bash "$workdir/install.sh" --mode "$modes" --domain "$selected" -y || error '安装失败，请检查上面的错误。'
printf '安装完成，推荐域名：%s，协议：%s\n' "$selected" "$modes"
