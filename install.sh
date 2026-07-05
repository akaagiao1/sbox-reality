#!/usr/bin/env bash
set -euo pipefail

INSTALL_MODE="${INSTALL_MODE:-}"
SHARED_PORT="${PORT:-}"
ACTION="install"
UNINSTALL_SCOPE="${UNINSTALL_SCOPE:-}"
CONFIG_POLICY="${CONFIG_POLICY:-ask}"
PURGE_SING_BOX=0
ASSUME_YES=0

REALITY_DOMAIN="${REALITY_DOMAIN:-${DOMAIN:-www.apple.com}}"
ANYTLS_PORT="${ANYTLS_PORT:-auto}"
VLESS_DOMAIN="${VLESS_DOMAIN:-${REALITY_DOMAIN}}"
VLESS_PORT="${VLESS_PORT:-auto}"
SNELL5_PORT="${SNELL5_PORT:-auto}"
SNELL6_PORT="${SNELL6_PORT:-auto}"
SNELL5_OBFS_MODE="${SNELL5_OBFS_MODE:-none}"
SNELL6_MODE="${SNELL6_MODE:-default}"
HIGH_PORT_MIN="${HIGH_PORT_MIN:-20000}"
HIGH_PORT_MAX="${HIGH_PORT_MAX:-65535}"

HY2_SNI="${HY2_SNI:-${SNI:-www.bing.com}}"
HY2_PORT="${HY2_PORT:-auto}"
HOP_PORTS="${HOP_PORTS:-20000-50000}"
HOP_INTERVAL="${HOP_INTERVAL:-30}"
UP_MBPS="${UP_MBPS:-}"
DOWN_MBPS="${DOWN_MBPS:-}"
OBFS="${OBFS:-gecko}"
OBFS_PASSWORD="${OBFS_PASSWORD:-}"
GECKO_MIN_PACKET_SIZE="${GECKO_MIN_PACKET_SIZE:-512}"
GECKO_MAX_PACKET_SIZE="${GECKO_MAX_PACKET_SIZE:-1200}"
PROXY_NAME="${PROXY_NAME:-HY2}"

SERVER_CONF="/etc/sing-box/config.json"
OUTPUT_DIR="/root/sing-box"
ANYTLS_CLIENT_OUT="$OUTPUT_DIR/anytls-sing-box.json"
ANYTLS_URL_FILE="$OUTPUT_DIR/anytls-url.txt"
ANYTLS_SURGE_CONF="$OUTPUT_DIR/anytls-surge.conf"
VLESS_CLIENT_OUT="$OUTPUT_DIR/vless-sing-box.json"
VLESS_URL_FILE="$OUTPUT_DIR/vless-url.txt"
VLESS_SURGE_CONF="$OUTPUT_DIR/vless-surge.conf"
HY2_CLIENT_OUT="$OUTPUT_DIR/hysteria2-sing-box.json"
SURGE_CONF="$OUTPUT_DIR/hysteria2-surge.conf"
HY2_URL_FILE="$OUTPUT_DIR/hysteria2-url.txt"
SNELL5_CLIENT_OUT="$OUTPUT_DIR/snell-v5-sing-box.json"
SNELL5_URL_FILE="$OUTPUT_DIR/snell-v5-url.txt"
SNELL5_SURGE_CONF="$OUTPUT_DIR/snell-v5-surge.conf"
SNELL6_CLIENT_OUT="$OUTPUT_DIR/snell-v6-sing-box.json"
SNELL6_URL_FILE="$OUTPUT_DIR/snell-v6-url.txt"
SNELL6_SURGE_CONF="$OUTPUT_DIR/snell-v6-surge.conf"
ANYTLS_INFO="$OUTPUT_DIR/anytls-info.txt"
VLESS_INFO="$OUTPUT_DIR/vless-info.txt"
HY2_INFO="$OUTPUT_DIR/hysteria2-info.txt"
SNELL5_INFO="$OUTPUT_DIR/snell-v5-info.txt"
SNELL6_INFO="$OUTPUT_DIR/snell-v6-info.txt"
SNELL_SURGE_CONF="$OUTPUT_DIR/snell-surge.conf"
COMBINED_INFO="$OUTPUT_DIR/all-info.txt"
BACKUP_ROOT="/root/sbox-reality-backups"

PORT_ENV="/etc/sing-box/hy2-port-hopping.env"
PORT_HELPER="/usr/local/bin/sing-box-hy2-port-hopping"
SYSTEMD_DROPIN="/etc/systemd/system/sing-box.service.d/10-hy2-port-hopping.conf"
OPENRC_PORT_SERVICE="/etc/init.d/sing-box-hy2-port-hopping"
DEFAULT_CERT_PATH="/etc/sing-box/hysteria2.crt"
DEFAULT_KEY_PATH="/etc/sing-box/hysteria2.key"
CERT_PATH="${CERT_PATH:-$DEFAULT_CERT_PATH}"
KEY_PATH="${KEY_PATH:-$DEFAULT_KEY_PATH}"

INSTALL_ANYTLS=0
INSTALL_VLESS=0
INSTALL_HY2=0
INSTALL_SNELL5=0
INSTALL_SNELL6=0
ANYTLS_PORT_MODE=""
VLESS_PORT_MODE=""
HY2_PORT_MODE=""
SNELL5_PORT_MODE=""
SNELL6_PORT_MODE=""
FIRST_HOP_PORT=""
NORMALIZED_HOP_PORTS=""
SERVER_PORTS_JSON=""
SERVER_IP=""

ANYTLS_PRIVATE_KEY=""
ANYTLS_PUBLIC_KEY=""
ANYTLS_PASSWORD=""
ANYTLS_SHORT_ID=""
ANYTLS_SHARE_URL=""
VLESS_PRIVATE_KEY=""
VLESS_PUBLIC_KEY=""
VLESS_UUID=""
VLESS_SHORT_ID=""
VLESS_SHARE_URL=""
HY2_PASSWORD=""
HY2_SHARE_URL=""
SURGE_PROXY_LINE=""
SNELL5_PSK=""
SNELL6_PSK=""
SNELL5_SURGE_LINE=""
SNELL6_SURGE_LINE=""
SNELL5_SHARE_URL=""
SNELL6_SHARE_URL=""
LAST_BACKUP_DIR=""
LATEST_BACKUP_DIR=""
PLATFORM=""
SERVICE_MANAGER=""

detect_platform() {
  if [[ -f /etc/alpine-release ]] && command -v apk >/dev/null 2>&1; then
    PLATFORM="alpine"
    SERVICE_MANAGER="openrc"
  elif command -v apt >/dev/null 2>&1; then
    PLATFORM="debian"
    SERVICE_MANAGER="systemd"
  else
    echo "错误：本脚本仅支持 Debian、Ubuntu 和 Alpine Linux"
    exit 1
  fi
}

prepare_output_dir() {
  local old new
  mkdir -p "$OUTPUT_DIR"
  chmod 700 "$OUTPUT_DIR"

  while IFS='|' read -r old new; do
    [[ -f "$old" && ! -e "$new" ]] || continue
    mv "$old" "$new"
  done << MIGRATE
/root/client-outbounds-anytls-reality.json|$ANYTLS_CLIENT_OUT
/root/client-outbounds-vless-reality.json|$VLESS_CLIENT_OUT
/root/vless-reality-url.txt|$VLESS_URL_FILE
/root/client-outbounds-hysteria2.json|$HY2_CLIENT_OUT
/root/surge-hysteria2.conf|$SURGE_CONF
/root/hysteria2-url.txt|$HY2_URL_FILE
/root/anytls-reality-info.txt|$ANYTLS_INFO
/root/vless-reality-info.txt|$VLESS_INFO
/root/hysteria2-surge-info.txt|$HY2_INFO
/root/snell-v5-surge-info.txt|$SNELL5_INFO
/root/snell-v6-surge-info.txt|$SNELL6_INFO
/root/surge-snell.conf|$SNELL_SURGE_CONF
/root/sbox-reality-info.txt|$COMBINED_INFO
MIGRATE
}

service_reload() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl daemon-reload
  fi
}

service_enable() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl enable sing-box
  else
    rc-update add sing-box default >/dev/null 2>&1 || true
  fi
}

service_stop() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl stop sing-box >/dev/null 2>&1 || true
  else
    rc-service sing-box stop >/dev/null 2>&1 || true
  fi
}

service_restart() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl restart sing-box
  else
    rc-service sing-box restart >/dev/null 2>&1 || rc-service sing-box start
  fi
}

service_disable() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl disable --now sing-box >/dev/null 2>&1 || true
  else
    rc-service sing-box stop >/dev/null 2>&1 || true
    rc-update del sing-box default >/dev/null 2>&1 || true
  fi
}

install_jq() {
  if [[ "$PLATFORM" == "alpine" ]]; then
    apk add --no-cache jq
  else
    apt update
    apt install -y jq
  fi
}

purge_sing_box_package() {
  if [[ "$PLATFORM" == "alpine" ]]; then
    apk del sing-box
  else
    apt purge -y sing-box
  fi
}

usage() {
  cat << USAGE
用法：
  bash $0
  bash $0 --mode 1
  bash $0 --mode 2
  bash $0 --mode vless
  bash $0 --mode full
  bash $0 --restore
  bash $0 --uninstall anytls|vless|hy2|snell5|snell6|all

安装模式：
  1, anytls     安装 AnyTLS + REALITY
  2, hy2        安装 Hysteria2 + Surge 端口跳跃
  3, vless      安装 VLESS + REALITY
  4, snell5     安装 Snell v5
  5, snell6     安装 Snell v6
  6, full       同时安装全部五种协议
  7, uninstall  卸载一个或全部配置
  8, restore    恢复最新的配置备份

重新安装选项（检测到现有配置时显示）：
      --config merge   增量合并本次协议到现有配置（默认）
      --config keep    保留现有服务端/客户端配置，仅更新 sing-box
      --config restore 从 /root/sbox-reality-backups 恢复最新配置
      --config new     生成全新配置，不合并已有入站

卸载选项：
      --uninstall      卸载范围：anytls、vless、hy2、snell5、snell6 或 all
      --purge          同时移除 sing-box 软件包（仅适用于 --uninstall all）
  -y, --yes            跳过卸载确认

AnyTLS + REALITY 选项：
  -d, --domain        REALITY 握手域名，默认：www.apple.com
      --anytls-port   AnyTLS TCP 监听端口，默认：自动选择

VLESS + REALITY 选项：
      --vless-domain  VLESS REALITY 握手域名，默认：www.apple.com
      --vless-port    VLESS TCP 监听端口，默认：自动选择

Hysteria2 + Surge 选项：
  -s, --sni           TLS SNI 和自签证书通用名称，默认：www.bing.com
      --hy2-port      Hysteria2 UDP 监听端口，默认：自动选择
  -P, --ports         Surge 端口跳跃端口/范围，默认：20000-50000
  -i, --interval      端口跳跃间隔（秒），最小 5，默认：30
      --up            服务端上传带宽（Mbps），可选
      --down          服务端下载带宽（Mbps），可选
      --obfs          启用 Hysteria2 Gecko 混淆（默认）
      --obfs-type     混淆类型：gecko、salamander 或 off
      --obfs-password Gecko/Salamander 混淆密码
      --gecko-min     Gecko 最小包长，默认：512
      --gecko-max     Gecko 最大包长，默认：1200
      --cert          现有 TLS 证书路径
      --key           现有 TLS 私钥路径
      --name          Surge 代理名称，默认：HY2

Snell 选项：
      --snell5-port   Snell v5 TCP 监听端口，默认：自动选择
      --snell6-port   Snell v6 TCP 监听端口，默认：自动选择
      --snell5-obfs   v5 HTTP 混淆：none 或 http，默认：none
      --snell6-mode   v6 流量模式：default、unshaped 或 unsafe-raw，默认：default

通用选项：
  -m, --mode          模式：1-8、anytls、vless、hy2、snell5、snell6、full、uninstall、restore
  -p, --port          当前单协议模式的端口；同时安装时请分别使用各协议端口选项
  -h, --help          显示帮助

环境变量：
  INSTALL_MODE, CONFIG_POLICY, UNINSTALL_SCOPE, PORT,
  REALITY_DOMAIN, DOMAIN, ANYTLS_PORT,
  VLESS_DOMAIN, VLESS_PORT, SNELL5_PORT, SNELL6_PORT,
  SNELL5_OBFS_MODE, SNELL6_MODE,
  HIGH_PORT_MIN, HIGH_PORT_MAX,
  HY2_SNI, SNI, HY2_PORT, HOP_PORTS, HOP_INTERVAL,
  UP_MBPS, DOWN_MBPS, OBFS, OBFS_PASSWORD,
  GECKO_MIN_PACKET_SIZE, GECKO_MAX_PACKET_SIZE,
  CERT_PATH, KEY_PATH, PROXY_NAME
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode|--install)
      INSTALL_MODE="${2:-}"
      shift 2
      ;;
    1|anytls|reality)
      INSTALL_MODE="1"
      shift
      ;;
    2|hy2|hysteria2|surge)
      INSTALL_MODE="2"
      shift
      ;;
    3|vless|vless-reality)
      INSTALL_MODE="3"
      shift
      ;;
    4|snell5|snell-v5)
      INSTALL_MODE="4"
      shift
      ;;
    5|snell6|snell-v6)
      INSTALL_MODE="5"
      shift
      ;;
    6|full|all|all5|all-protocols)
      INSTALL_MODE="6"
      shift
      ;;
    7|uninstall|remove)
      INSTALL_MODE="7"
      shift
      ;;
    8|restore|backup)
      INSTALL_MODE="8"
      shift
      ;;
    --restore)
      ACTION="restore"
      CONFIG_POLICY="restore"
      shift
      ;;
    --uninstall)
      ACTION="uninstall"
      if [[ -n "${2:-}" && "${2:-}" != -* ]]; then
        UNINSTALL_SCOPE="$2"
        shift 2
      else
        shift
      fi
      ;;
    --config)
      CONFIG_POLICY="${2:-}"
      shift 2
      ;;
    --keep-config)
      CONFIG_POLICY="keep"
      shift
      ;;
    --new-config)
      CONFIG_POLICY="new"
      shift
      ;;
    --purge)
      PURGE_SING_BOX=1
      shift
      ;;
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -d|--domain|--reality-domain)
      REALITY_DOMAIN="${2:-}"
      VLESS_DOMAIN="${2:-}"
      shift 2
      ;;
    --anytls-port)
      ANYTLS_PORT="${2:-}"
      shift 2
      ;;
    --vless-domain)
      VLESS_DOMAIN="${2:-}"
      shift 2
      ;;
    --vless-port)
      VLESS_PORT="${2:-}"
      shift 2
      ;;
    --snell5-port)
      SNELL5_PORT="${2:-}"
      shift 2
      ;;
    --snell6-port)
      SNELL6_PORT="${2:-}"
      shift 2
      ;;
    --snell5-obfs)
      SNELL5_OBFS_MODE="${2:-}"
      shift 2
      ;;
    --snell6-mode)
      SNELL6_MODE="${2:-}"
      shift 2
      ;;
    -s|--sni|--hy2-sni)
      HY2_SNI="${2:-}"
      shift 2
      ;;
    --hy2-port)
      HY2_PORT="${2:-}"
      shift 2
      ;;
    -P|--ports)
      HOP_PORTS="${2:-}"
      shift 2
      ;;
    -i|--interval)
      HOP_INTERVAL="${2:-}"
      shift 2
      ;;
    --up)
      UP_MBPS="${2:-}"
      shift 2
      ;;
    --down)
      DOWN_MBPS="${2:-}"
      shift 2
      ;;
    --obfs)
      OBFS="gecko"
      shift
      ;;
    --obfs-type)
      OBFS="${2:-}"
      shift 2
      ;;
    --obfs-password)
      OBFS_PASSWORD="${2:-}"
      shift 2
      ;;
    --gecko-min)
      GECKO_MIN_PACKET_SIZE="${2:-}"
      shift 2
      ;;
    --gecko-max)
      GECKO_MAX_PACKET_SIZE="${2:-}"
      shift 2
      ;;
    --cert)
      CERT_PATH="${2:-}"
      shift 2
      ;;
    --key)
      KEY_PATH="${2:-}"
      shift 2
      ;;
    --name)
      PROXY_NAME="${2:-}"
      shift 2
      ;;
    -p|--port)
      SHARED_PORT="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知选项：$1"
      usage
      exit 1
      ;;
  esac
done

choose_mode() {
  if [[ "$ACTION" != "install" || -n "$INSTALL_MODE" ]]; then
    return 0
  fi

  if [[ -t 0 ]]; then
    echo "请选择操作："
    echo "  1) 安装 AnyTLS + REALITY"
    echo "  2) 安装 Hysteria2 + Surge 端口跳跃"
    echo "  3) 安装 VLESS + REALITY"
    echo "  4) 安装 Snell v5"
    echo "  5) 安装 Snell v6"
    echo "  6) 同时安装全部五种协议"
    echo "  7) 卸载"
    echo "  8) 恢复最新备份"
    echo
    read -rp "请输入选项 [1-8]：" INSTALL_MODE
  else
    echo "错误：非交互模式下必须指定安装模式"
    echo "示例：bash $0 --mode full"
    exit 1
  fi
}

normalize_mode() {
  if [[ "$ACTION" != "install" ]]; then
    return 0
  fi

  case "$INSTALL_MODE" in
    1|anytls|reality)
      INSTALL_ANYTLS=1
      ;;
    2|hy2|hysteria2|surge)
      INSTALL_HY2=1
      ;;
    3|vless|vless-reality)
      INSTALL_VLESS=1
      ;;
    4|snell5|snell-v5)
      INSTALL_SNELL5=1
      ;;
    5|snell6|snell-v6)
      INSTALL_SNELL6=1
      ;;
    6|full|all|all5|all-protocols)
      INSTALL_ANYTLS=1
      INSTALL_VLESS=1
      INSTALL_HY2=1
      INSTALL_SNELL5=1
      INSTALL_SNELL6=1
      ;;
    7|uninstall|remove)
      ACTION="uninstall"
      ;;
    8|restore|backup)
      ACTION="restore"
      CONFIG_POLICY="restore"
      ;;
    *)
      echo "错误：无效的安装模式：$INSTALL_MODE"
      usage
      exit 1
      ;;
  esac
}

choose_uninstall_scope() {
  [[ "$ACTION" == "uninstall" ]] || return 0

  if [[ -z "$UNINSTALL_SCOPE" ]]; then
    if [[ -t 0 ]]; then
      echo "请选择卸载范围："
      echo "  1) 仅 AnyTLS + REALITY"
      echo "  2) 仅 VLESS + REALITY"
      echo "  3) 仅 Hysteria2 + 端口跳跃"
      echo "  4) 仅 Snell v5"
      echo "  5) 仅 Snell v6"
      echo "  6) 全部卸载"
      echo
      read -rp "请输入选项 [1-6]：" UNINSTALL_SCOPE
    else
      echo "错误：非交互模式下必须指定卸载范围"
      echo "示例：bash $0 --uninstall all --yes"
      exit 1
    fi
  fi

  case "$UNINSTALL_SCOPE" in
    1|anytls|reality)
      UNINSTALL_SCOPE="anytls"
      ;;
    2|vless|vless-reality)
      UNINSTALL_SCOPE="vless"
      ;;
    3|hy2|hysteria2|surge)
      UNINSTALL_SCOPE="hy2"
      ;;
    4|snell5|snell-v5)
      UNINSTALL_SCOPE="snell5"
      ;;
    5|snell6|snell-v6)
      UNINSTALL_SCOPE="snell6"
      ;;
    6|full|all)
      UNINSTALL_SCOPE="all"
      ;;
    *)
      echo "错误：无效的卸载范围：$UNINSTALL_SCOPE"
      exit 1
      ;;
  esac

  if (( PURGE_SING_BOX )) && [[ "$UNINSTALL_SCOPE" != "all" ]]; then
    echo "错误：--purge 只能与 --uninstall all 一起使用"
    exit 1
  fi
}

apply_shared_port() {
  [[ -n "$SHARED_PORT" ]] || return 0

  if (( INSTALL_ANYTLS )); then
    ANYTLS_PORT="$SHARED_PORT"
  fi

  if (( INSTALL_VLESS )); then
    VLESS_PORT="$SHARED_PORT"
  fi

  if (( INSTALL_HY2 )); then
    HY2_PORT="$SHARED_PORT"
  fi
  if (( INSTALL_SNELL5 )); then
    SNELL5_PORT="$SHARED_PORT"
  fi
  if (( INSTALL_SNELL6 )); then
    SNELL6_PORT="$SHARED_PORT"
  fi
}

strip_host() {
  local host="$1"
  host="${host#https://}"
  host="${host#http://}"
  host="${host%%/*}"
  printf '%s' "$host"
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

validate_positive_number() {
  local value="$1"
  [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 ))
}

validate_proxy_name() {
  [[ "$PROXY_NAME" =~ ^[A-Za-z0-9_.-]+$ ]]
}

is_tcp_port_in_use() {
  local port="$1"
  ss -H -lntp 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {print}' | grep -q .
}

is_tcp_port_in_use_by_other() {
  local port="$1"
  ss -H -lntp 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {print}' | grep -v "sing-box" | grep -q .
}

is_udp_port_in_use_by_other() {
  local port="$1"
  ss -H -lunp 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {print}' | grep -v "sing-box" | grep -q .
}

random_number() {
  od -An -N4 -tu4 /dev/urandom | tr -d ' '
}

pick_random_free_high_tcp_port() {
  local candidate
  local range=$(( HIGH_PORT_MAX - HIGH_PORT_MIN + 1 ))

  if (( HIGH_PORT_MIN < 1024 || HIGH_PORT_MIN > HIGH_PORT_MAX || HIGH_PORT_MAX > 65535 )); then
    echo "错误：无效的高端口范围：${HIGH_PORT_MIN}-${HIGH_PORT_MAX}" >&2
    exit 1
  fi

  for _ in $(seq 1 100); do
    candidate=$(( HIGH_PORT_MIN + $(random_number) % range ))
    if ! is_tcp_port_in_use "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  echo "错误：在 ${HIGH_PORT_MIN}-${HIGH_PORT_MAX} 范围内未找到可用的 TCP 高端口" >&2
  exit 1
}

normalize_hop_ports() {
  local -a specs
  local raw spec start end normalized sep first

  raw="${HOP_PORTS//[[:space:]]/}"
  raw="${raw//,/;}"

  if [[ -z "$raw" ]]; then
    echo "错误：Hysteria2 端口不能为空"
    exit 1
  fi

  IFS=';' read -r -a specs <<< "$raw"
  normalized=""
  sep=""
  first=""

  for spec in "${specs[@]}"; do
    if [[ -z "$spec" ]]; then
      echo "错误：端口列表中存在空项：$HOP_PORTS"
      exit 1
    fi

    if [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      if ! validate_port "$start" || ! validate_port "$end" || (( start > end )); then
        echo "错误：无效的端口范围：$spec"
        exit 1
      fi
      [[ -z "$first" ]] && first="$start"
    elif validate_port "$spec"; then
      [[ -z "$first" ]] && first="$spec"
    else
      echo "错误：无效的端口：$spec"
      exit 1
    fi

    normalized="${normalized}${sep}${spec}"
    sep=";"
  done

  NORMALIZED_HOP_PORTS="$normalized"
  FIRST_HOP_PORT="$first"
}

build_server_ports_json() {
  local -a specs
  local spec sep json

  IFS=';' read -r -a specs <<< "$NORMALIZED_HOP_PORTS"
  sep=""
  json=""

  for spec in "${specs[@]}"; do
    json="${json}${sep}\"${spec}\""
    sep=", "
  done

  SERVER_PORTS_JSON="[${json}]"
}

json_number_field() {
  local key="$1"
  local value="$2"

  [[ -n "$value" ]] || return 0
  printf '      "%s": %s,\n' "$key" "$value"
}

json_obfs_field() {
  [[ "$OBFS" != "off" ]] || return 0

  if [[ "$OBFS" == "gecko" ]]; then
    cat << JSON
      "obfs": {
        "type": "gecko",
        "password": "${OBFS_PASSWORD}",
        "min_packet_size": ${GECKO_MIN_PACKET_SIZE},
        "max_packet_size": ${GECKO_MAX_PACKET_SIZE}
      },
JSON
  else
    cat << JSON
      "obfs": {
        "type": "salamander",
        "password": "${OBFS_PASSWORD}"
      },
JSON
  fi
}

surge_obfs_param() {
  if [[ "$OBFS" == "gecko" ]]; then
    printf ',gecko-password="%s"' "$OBFS_PASSWORD"
  elif [[ "$OBFS" == "salamander" ]]; then
    printf ',salamander-password="%s"' "$OBFS_PASSWORD"
  fi
}

surge_extra_params() {
  local extra=""

  if [[ "$HOP_INTERVAL" != "30" ]]; then
    extra="${extra},port-hopping-interval=${HOP_INTERVAL}"
  fi

  if [[ -n "$DOWN_MBPS" ]]; then
    extra="${extra},download-bandwidth=${DOWN_MBPS}"
  fi

  printf '%s' "$extra"
}

build_surge_proxy_line() {
  printf '%s=hysteria2,%s,%s,password="%s",port-hopping="%s"%s,sni="%s",skip-cert-verify=true,tfo=false%s' \
    "$PROXY_NAME" "$SERVER_IP" "$HY2_PORT" "$HY2_PASSWORD" \
    "$NORMALIZED_HOP_PORTS" "$(surge_obfs_param)" "$HY2_SNI" "$(surge_extra_params)"
}

url_encode() {
  local LC_ALL=C
  local value="$1"
  local encoded="" c hex i

  for (( i=0; i<${#value}; i++ )); do
    c="${value:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-])
        encoded+="$c"
        ;;
      *)
        printf -v hex '%%%02X' "'$c"
        encoded+="$hex"
        ;;
    esac
  done

  printf '%s' "$encoded"
}

build_hy2_share_url() {
  local uri_ports query

  uri_ports="${NORMALIZED_HOP_PORTS//;/,}"
  query="insecure=1&sni=$(url_encode "$HY2_SNI")"

  if [[ "$OBFS" != "off" ]]; then
    query="${query}&obfs=${OBFS}&obfs-password=$(url_encode "$OBFS_PASSWORD")"
  fi

  HY2_SHARE_URL="hysteria2://$(url_encode "$HY2_PASSWORD")@${SERVER_IP}:${uri_ports}/?${query}#$(url_encode "$PROXY_NAME")"
}

build_vless_share_url() {
  local query

  query="encryption=none&flow=xtls-rprx-vision&security=reality"
  query="${query}&sni=$(url_encode "$VLESS_DOMAIN")&fp=chrome"
  query="${query}&pbk=$(url_encode "$VLESS_PUBLIC_KEY")&sid=$(url_encode "$VLESS_SHORT_ID")"
  query="${query}&type=tcp&headerType=none"

  VLESS_SHARE_URL="vless://${VLESS_UUID}@${SERVER_IP}:${VLESS_PORT}?${query}#VLESS-Reality"
}

build_anytls_share_url() {
  local query
  query="security=reality&sni=$(url_encode "$REALITY_DOMAIN")&fp=chrome"
  query="${query}&pbk=$(url_encode "$ANYTLS_PUBLIC_KEY")&sid=$(url_encode "$ANYTLS_SHORT_ID")"
  ANYTLS_SHARE_URL="anytls://$(url_encode "$ANYTLS_PASSWORD")@${SERVER_IP}:${ANYTLS_PORT}?${query}#AnyTLS-Reality"
}

build_snell_share_urls() {
  if (( INSTALL_SNELL5 )); then
    SNELL5_SHARE_URL="snell://$(url_encode "$SNELL5_PSK")@${SERVER_IP}:${SNELL5_PORT}?version=5&obfs=${SNELL5_OBFS_MODE}#Snell-v5"
  fi
  if (( INSTALL_SNELL6 )); then
    SNELL6_SHARE_URL="snell://$(url_encode "$SNELL6_PSK")@${SERVER_IP}:${SNELL6_PORT}?version=6&mode=${SNELL6_MODE}#Snell-v6"
  fi
}

prepare_certificate() {
  local san_type

  mkdir -p "$(dirname "$CERT_PATH")" "$(dirname "$KEY_PATH")"

  if [[ "$CERT_PATH" != "$DEFAULT_CERT_PATH" || "$KEY_PATH" != "$DEFAULT_KEY_PATH" ]]; then
    if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
      echo "错误：自定义的 --cert 和 --key 文件必须同时存在"
      exit 1
    fi
    return 0
  fi

  san_type="DNS"
  if [[ "$HY2_SNI" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    san_type="IP"
  fi

  openssl req -x509 -nodes \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 \
    -keyout "$KEY_PATH" \
    -out "$CERT_PATH" \
    -subj "/CN=${HY2_SNI}" \
    -addext "subjectAltName=${san_type}:${HY2_SNI}" >/dev/null 2>&1

  chmod 600 "$KEY_PATH"
  chmod 644 "$CERT_PATH"
}

write_port_hopping_helper() {
  mkdir -p /etc/sing-box "$(dirname "$PORT_HELPER")"

  cat > "$PORT_ENV" << ENV
HOP_PORTS="${NORMALIZED_HOP_PORTS}"
LISTEN_PORT="${HY2_PORT}"
ENV

  cat > "$PORT_HELPER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="/etc/sing-box/hy2-port-hopping.env"
TABLE="sing_box_hy2_port_hopping"

[[ -f "$ENV_FILE" ]] || exit 0

# shellcheck disable=SC1090
. "$ENV_FILE"

IFS=';' read -r -a PORT_SPECS <<< "$HOP_PORTS"

iptables_port_spec() {
  printf '%s' "${1/-/:}"
}

clean_nft() {
  command -v nft >/dev/null 2>&1 || return 0
  nft delete table inet "$TABLE" >/dev/null 2>&1 || true
}

apply_nft() {
  local ports_nft

  command -v nft >/dev/null 2>&1 || return 1
  ports_nft="${HOP_PORTS//;/,}"

  clean_nft

  nft -f - << NFT
add table inet ${TABLE}
add chain inet ${TABLE} prerouting { type nat hook prerouting priority dstnat; policy accept; }
add rule inet ${TABLE} prerouting udp dport { ${ports_nft} } redirect to :${LISTEN_PORT}
NFT
}

clean_iptables() {
  local spec ipt_spec

  command -v iptables >/dev/null 2>&1 || return 0

  for spec in "${PORT_SPECS[@]}"; do
    ipt_spec="$(iptables_port_spec "$spec")"
    while iptables -t nat -D PREROUTING -p udp --dport "$ipt_spec" -j REDIRECT --to-ports "$LISTEN_PORT" >/dev/null 2>&1; do
      :
    done

    if command -v ip6tables >/dev/null 2>&1; then
      while ip6tables -t nat -D PREROUTING -p udp --dport "$ipt_spec" -j REDIRECT --to-ports "$LISTEN_PORT" >/dev/null 2>&1; do
        :
      done
    fi
  done
}

apply_iptables() {
  local spec ipt_spec

  command -v iptables >/dev/null 2>&1 || return 1

  for spec in "${PORT_SPECS[@]}"; do
    ipt_spec="$(iptables_port_spec "$spec")"

    if ! iptables -t nat -C PREROUTING -p udp --dport "$ipt_spec" -j REDIRECT --to-ports "$LISTEN_PORT" >/dev/null 2>&1; then
      iptables -t nat -A PREROUTING -p udp --dport "$ipt_spec" -j REDIRECT --to-ports "$LISTEN_PORT"
    fi

    if command -v ip6tables >/dev/null 2>&1; then
      if ! ip6tables -t nat -C PREROUTING -p udp --dport "$ipt_spec" -j REDIRECT --to-ports "$LISTEN_PORT" >/dev/null 2>&1; then
        ip6tables -t nat -A PREROUTING -p udp --dport "$ipt_spec" -j REDIRECT --to-ports "$LISTEN_PORT"
      fi
    fi
  done
}

case "${1:-}" in
  apply)
    clean_nft
    clean_iptables
    if command -v nft >/dev/null 2>&1; then
      if apply_nft; then
        exit 0
      fi
      clean_nft
    fi
    apply_iptables
    ;;
  clean)
    clean_nft
    clean_iptables
    ;;
  *)
    echo "用法：$0 apply|clean" >&2
    exit 1
    ;;
esac
SH

  chmod +x "$PORT_HELPER"

  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    mkdir -p "$(dirname "$SYSTEMD_DROPIN")"
    rm -f "$OPENRC_PORT_SERVICE"
    cat > "$SYSTEMD_DROPIN" << DROPIN
[Service]
ExecStartPre=+${PORT_HELPER} clean
ExecStartPre=+${PORT_HELPER} apply
ExecStopPost=+${PORT_HELPER} clean
DROPIN
  else
    rm -f "$SYSTEMD_DROPIN"
    cat > "$OPENRC_PORT_SERVICE" << OPENRC
#!/sbin/openrc-run

description="sing-box Hysteria2 端口跳跃规则"

depend() {
  need net
  before sing-box
}

start() {
  ebegin "应用 Hysteria2 端口跳跃规则"
  ${PORT_HELPER} apply
  eend \$?
}

stop() {
  ebegin "清理 Hysteria2 端口跳跃规则"
  ${PORT_HELPER} clean
  eend \$?
}
OPENRC
    chmod +x "$OPENRC_PORT_SERVICE"
    rc-update add sing-box-hy2-port-hopping default >/dev/null 2>&1 || true
    rc-service sing-box-hy2-port-hopping restart >/dev/null 2>&1 \
      || rc-service sing-box-hy2-port-hopping start
  fi
}

disable_hy2_port_hopping() {
  if [[ "$SERVICE_MANAGER" == "openrc" ]]; then
    rc-service sing-box-hy2-port-hopping stop >/dev/null 2>&1 || true
    rc-update del sing-box-hy2-port-hopping default >/dev/null 2>&1 || true
  fi

  if [[ -x "$PORT_HELPER" ]]; then
    "$PORT_HELPER" clean >/dev/null 2>&1 || true
  fi

  rm -f "$SYSTEMD_DROPIN" "$OPENRC_PORT_SERVICE" "$PORT_ENV"
}

backup_existing_files() {
  local reason="$1"
  local backup_dir source copied=0
  local -a sources=(
    "$SERVER_CONF"
    "$ANYTLS_CLIENT_OUT"
    "$ANYTLS_URL_FILE"
    "$ANYTLS_SURGE_CONF"
    "$VLESS_CLIENT_OUT"
    "$VLESS_URL_FILE"
    "$VLESS_SURGE_CONF"
    "$HY2_CLIENT_OUT"
    "$SURGE_CONF"
    "$HY2_URL_FILE"
    "$ANYTLS_INFO"
    "$VLESS_INFO"
    "$HY2_INFO"
    "$SNELL5_INFO"
    "$SNELL6_INFO"
    "$SNELL_SURGE_CONF"
    "$SNELL5_CLIENT_OUT"
    "$SNELL5_URL_FILE"
    "$SNELL5_SURGE_CONF"
    "$SNELL6_CLIENT_OUT"
    "$SNELL6_URL_FILE"
    "$SNELL6_SURGE_CONF"
    "$COMBINED_INFO"
    "$PORT_ENV"
    "$PORT_HELPER"
    "$SYSTEMD_DROPIN"
    "$OPENRC_PORT_SERVICE"
    "$DEFAULT_CERT_PATH"
    "$DEFAULT_KEY_PATH"
  )

  backup_dir="${BACKUP_ROOT}/${reason}-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$backup_dir"
  chmod 700 "$BACKUP_ROOT" "$backup_dir"

  for source in "${sources[@]}"; do
    if [[ -f "$source" ]]; then
      cp -p "$source" "$backup_dir/$(basename "$source")"
      copied=$(( copied + 1 ))
    fi
  done

  if (( copied == 0 )); then
    rmdir "$backup_dir" 2>/dev/null || true
    LAST_BACKUP_DIR=""
    echo "未发现现有配置文件，因此没有创建空备份。"
    return 0
  fi

  LAST_BACKUP_DIR="$backup_dir"
  echo "原配置已备份至：$backup_dir"
}

prune_backups_except() {
  local keep_dir="$1"
  local candidate

  [[ -n "$keep_dir" && -d "$keep_dir" && -d "$BACKUP_ROOT" ]] || return 0

  for candidate in "$BACKUP_ROOT"/*; do
    [[ -d "$candidate" && "$candidate" != "$keep_dir" ]] || continue
    rm -rf -- "$candidate"
  done
}

find_latest_backup() {
  local candidate base key latest_key=""

  LATEST_BACKUP_DIR=""
  [[ -d "$BACKUP_ROOT" ]] || return 0

  for candidate in "$BACKUP_ROOT"/*; do
    [[ -d "$candidate" && -s "$candidate/$(basename "$SERVER_CONF")" ]] || continue
    if command -v jq >/dev/null 2>&1 \
      && ! jq -e . "$candidate/$(basename "$SERVER_CONF")" >/dev/null 2>&1; then
      continue
    fi
    base="$(basename "$candidate")"
    if [[ "$base" =~ ([0-9]{8}-[0-9]{6})-([0-9]+)$ ]]; then
      printf -v key '%s-%020d' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
      if [[ -z "$latest_key" || "$key" > "$latest_key" ]]; then
        latest_key="$key"
        LATEST_BACKUP_DIR="$candidate"
      fi
    fi
  done
}

choose_config_policy() {
  case "$CONFIG_POLICY" in
    ask|""|merge|keep|restore|new)
      ;;
    *)
      echo "错误：--config 必须设置为 merge、keep、restore 或 new"
      exit 1
      ;;
  esac

  find_latest_backup

  if [[ "$ACTION" == "install" && ( "$CONFIG_POLICY" == "ask" || -z "$CONFIG_POLICY" ) ]]; then
    CONFIG_POLICY="merge"
  fi

  if [[ ! -s "$SERVER_CONF" ]]; then
    if [[ "$CONFIG_POLICY" == "keep" ]]; then
      echo "错误：指定了 --config keep，但 $SERVER_CONF 不存在"
      exit 1
    fi

    if [[ "$CONFIG_POLICY" == "restore" ]]; then
      if [[ -z "$LATEST_BACKUP_DIR" ]]; then
        echo "错误：在 $BACKUP_ROOT 中未找到可恢复的配置"
        exit 1
      fi
      return 0
    fi

    CONFIG_POLICY="new"
    return 0
  fi

  case "$CONFIG_POLICY" in
    merge|keep|new|restore)
      if [[ "$CONFIG_POLICY" == "restore" && -z "$LATEST_BACKUP_DIR" ]]; then
        echo "错误：在 $BACKUP_ROOT 中未找到可恢复的配置"
        exit 1
      fi
      return 0
      ;;
  esac
}

restore_file_from_backup() {
  local backup_dir="$1"
  local destination="$2"
  local source="${backup_dir}/$(basename "$destination")"

  [[ -f "$source" ]] || return 0
  mkdir -p "$(dirname "$destination")"
  cp -p "$source" "$destination"
}

validate_backup_tls_files() {
  local backup_dir="$1"
  local backup_config="$2"
  local required_path backup_file

  while IFS= read -r required_path; do
    [[ -n "$required_path" ]] || continue
    backup_file="${backup_dir}/$(basename "$required_path")"

    if [[ "$required_path" == "$DEFAULT_CERT_PATH" || "$required_path" == "$DEFAULT_KEY_PATH" ]]; then
      if [[ ! -f "$backup_file" ]]; then
        echo "错误：备份不完整，缺少 $(basename "$required_path")"
        exit 1
      fi
    elif [[ ! -f "$required_path" ]]; then
      echo "错误：备份所需的自定义 TLS 文件不存在：$required_path"
      exit 1
    fi
  done < <(
    jq -r '
      .inbounds[]?
      | .tls?
      | [.certificate_path?, .key_path?][]
      | select(type == "string" and length > 0)
    ' "$backup_config"
  )
}

restore_latest_backup() {
  local backup_config
  local -a destinations=(
    "$SERVER_CONF"
    "$ANYTLS_CLIENT_OUT"
    "$ANYTLS_URL_FILE"
    "$ANYTLS_SURGE_CONF"
    "$VLESS_CLIENT_OUT"
    "$VLESS_URL_FILE"
    "$VLESS_SURGE_CONF"
    "$HY2_CLIENT_OUT"
    "$SURGE_CONF"
    "$HY2_URL_FILE"
    "$ANYTLS_INFO"
    "$VLESS_INFO"
    "$HY2_INFO"
    "$SNELL5_INFO"
    "$SNELL6_INFO"
    "$SNELL_SURGE_CONF"
    "$SNELL5_CLIENT_OUT"
    "$SNELL5_URL_FILE"
    "$SNELL5_SURGE_CONF"
    "$SNELL6_CLIENT_OUT"
    "$SNELL6_URL_FILE"
    "$SNELL6_SURGE_CONF"
    "$COMBINED_INFO"
    "$PORT_ENV"
    "$PORT_HELPER"
    "$SYSTEMD_DROPIN"
    "$OPENRC_PORT_SERVICE"
    "$DEFAULT_CERT_PATH"
    "$DEFAULT_KEY_PATH"
  )
  local destination

  [[ -n "$LATEST_BACKUP_DIR" ]] || {
    echo "错误：在 $BACKUP_ROOT 中未找到可恢复的配置"
    exit 1
  }
  backup_config="${LATEST_BACKUP_DIR}/$(basename "$SERVER_CONF")"

  if [[ -s "$SERVER_CONF" ]]; then
    backup_existing_files "before-restore"
  fi

  echo "正在从以下位置恢复配置：$LATEST_BACKUP_DIR"
  echo "所选安装模式和新协议选项不会生效。"
  install_dependencies

  if ! jq -e . "$backup_config" >/dev/null; then
    echo "错误：备份配置不是有效的 JSON：$backup_config"
    exit 1
  fi
  validate_backup_tls_files "$LATEST_BACKUP_DIR" "$backup_config"

  service_stop
  disable_hy2_port_hopping
  for destination in "${destinations[@]}"; do
    rm -f "$destination"
  done

  for destination in "${destinations[@]}"; do
    restore_file_from_backup "$LATEST_BACKUP_DIR" "$destination"
  done

  if [[ -f "$PORT_HELPER" ]]; then
    chmod +x "$PORT_HELPER"
  fi
  if [[ "$SERVICE_MANAGER" == "openrc" && -f "$OPENRC_PORT_SERVICE" ]]; then
    chmod +x "$OPENRC_PORT_SERVICE"
    rc-update add sing-box-hy2-port-hopping default >/dev/null 2>&1 || true
    rc-service sing-box-hy2-port-hopping restart >/dev/null 2>&1 \
      || rc-service sing-box-hy2-port-hopping start
  fi

  if ! sing-box check -c "$SERVER_CONF"; then
    echo "错误：文件已恢复，但未通过 sing-box 配置验证"
    echo "服务已保持停止状态。备份位置：$LATEST_BACKUP_DIR"
    exit 1
  fi

  service_reload
  service_enable
  service_restart

  echo
  echo "备份恢复完成。"
  echo "  恢复来源：$LATEST_BACKUP_DIR"
  echo "  配置文件：$SERVER_CONF"
  if [[ -f "$COMBINED_INFO" ]]; then
    echo
    cat "$COMBINED_INFO"
  fi
}

reuse_existing_config() {
  echo "保留现有配置；新模式和协议选项不会生效。"
  install_dependencies

  sing-box check -c "$SERVER_CONF"
  service_reload
  service_enable
  service_restart

  echo
  echo "重新安装完成，现有配置和凭据已保留。"
  echo "  配置文件：$SERVER_CONF"

  if [[ -f "$COMBINED_INFO" ]]; then
    echo
    cat "$COMBINED_INFO"
  fi
}

confirm_uninstall() {
  (( ASSUME_YES )) && return 0

  if [[ ! -t 0 ]]; then
    echo "错误：卸载操作需要确认；非交互模式请使用 --yes"
    exit 1
  fi

  echo
  echo "卸载范围：$UNINSTALL_SCOPE"
  if (( PURGE_SING_BOX )); then
    echo "同时会移除 sing-box 软件包。"
  else
    echo "将保留 sing-box 软件包。"
  fi
  read -rp "是否继续？[y/N]：" answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "已取消"; exit 0 ;;
  esac
}

remove_anytls_files() {
  rm -f "$ANYTLS_CLIENT_OUT" "$ANYTLS_URL_FILE" "$ANYTLS_SURGE_CONF" "$ANYTLS_INFO"
}

remove_vless_files() {
  rm -f "$VLESS_CLIENT_OUT" "$VLESS_URL_FILE" "$VLESS_SURGE_CONF" "$VLESS_INFO"
}

remove_hy2_files() {
  disable_hy2_port_hopping
  rm -f "$PORT_HELPER" "$HY2_CLIENT_OUT" "$SURGE_CONF" "$HY2_URL_FILE" "$HY2_INFO"
  if [[ ! -s "$SERVER_CONF" ]] || ! jq -e --arg path "$DEFAULT_CERT_PATH" \
    '.. | strings | select(. == $path)' "$SERVER_CONF" >/dev/null 2>&1; then
    rm -f "$DEFAULT_CERT_PATH"
  fi
  if [[ ! -s "$SERVER_CONF" ]] || ! jq -e --arg path "$DEFAULT_KEY_PATH" \
    '.. | strings | select(. == $path)' "$SERVER_CONF" >/dev/null 2>&1; then
    rm -f "$DEFAULT_KEY_PATH"
  fi
  rmdir "$(dirname "$SYSTEMD_DROPIN")" 2>/dev/null || true
}

remove_snell_files() {
  local version="$1"
  local lines=""
  local members=""
  if [[ "$version" == "5" ]]; then
    rm -f "$SNELL5_INFO" "$SNELL5_CLIENT_OUT" "$SNELL5_URL_FILE" "$SNELL5_SURGE_CONF"
  else
    rm -f "$SNELL6_INFO" "$SNELL6_CLIENT_OUT" "$SNELL6_URL_FILE" "$SNELL6_SURGE_CONF"
  fi
  if [[ -f "$SNELL5_INFO" ]]; then
    lines="$(sed -n '/^SnellV5=snell,/p' "$SNELL5_INFO" | head -n 1)"
    members="SnellV5,"
  fi
  if [[ -f "$SNELL6_INFO" ]]; then
    [[ -n "$lines" ]] && lines="${lines}"$'\n'
    lines="${lines}$(sed -n '/^SnellV6=snell,/p' "$SNELL6_INFO" | head -n 1)"
    members="${members}SnellV6,"
  fi
  if [[ -n "$lines" ]]; then
    printf '[Proxy]\n%s\n\n[Proxy Group]\nSnell=select,%sDIRECT\n' "$lines" "$members" > "$SNELL_SURGE_CONF"
  else
    rm -f "$SNELL_SURGE_CONF"
  fi
}

uninstall_selected() {
  local remove_anytls=false
  local remove_vless=false
  local remove_hy2=false
  local remove_snell5=false
  local remove_snell6=false
  local matched=0
  local remaining=0
  local temp_config=""
  local backup_status="not created"

  case "$UNINSTALL_SCOPE" in
    anytls)
      remove_anytls=true
      ;;
    vless)
      remove_vless=true
      ;;
    hy2)
      remove_hy2=true
      ;;
    snell5)
      remove_snell5=true
      ;;
    snell6)
      remove_snell6=true
      ;;
    all)
      remove_anytls=true
      remove_vless=true
      remove_hy2=true
      remove_snell5=true
      remove_snell6=true
      ;;
  esac

  confirm_uninstall

  if [[ -s "$SERVER_CONF" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
      echo "正在安装 jq，以安全编辑 JSON 配置……"
      install_jq
    fi

    if ! jq -e . "$SERVER_CONF" >/dev/null; then
      echo "错误：$SERVER_CONF 不是有效的 JSON，服务端配置未作更改"
      exit 1
    fi

    backup_existing_files "uninstall-${UNINSTALL_SCOPE}"
    if [[ -n "$LAST_BACKUP_DIR" ]]; then
      prune_backups_except "$LAST_BACKUP_DIR"
      backup_status="$LAST_BACKUP_DIR"
    fi

    matched="$(jq --argjson remove_anytls "$remove_anytls" --argjson remove_vless "$remove_vless" --argjson remove_hy2 "$remove_hy2" --argjson remove_snell5 "$remove_snell5" --argjson remove_snell6 "$remove_snell6" '
      [(.inbounds // [])[]
        | select(
            (($remove_anytls == true) and (.tag == "anytls-in"))
            or (($remove_vless == true) and (.tag == "vless-in"))
            or (($remove_hy2 == true) and (.tag == "hy2-in"))
            or (($remove_snell5 == true) and (.tag == "snell5-in"))
            or (($remove_snell6 == true) and (.tag == "snell6-in"))
          )
      ] | length
    ' "$SERVER_CONF")"

    if (( matched > 0 )); then
      temp_config="$(mktemp)"
      jq --argjson remove_anytls "$remove_anytls" --argjson remove_vless "$remove_vless" --argjson remove_hy2 "$remove_hy2" --argjson remove_snell5 "$remove_snell5" --argjson remove_snell6 "$remove_snell6" '
        .inbounds = [
          (.inbounds // [])[]
          | select(
              (($remove_anytls == false) or (.tag != "anytls-in"))
              and (($remove_vless == false) or (.tag != "vless-in"))
              and (($remove_hy2 == false) or (.tag != "hy2-in"))
              and (($remove_snell5 == false) or (.tag != "snell5-in"))
              and (($remove_snell6 == false) or (.tag != "snell6-in"))
            )
        ]
      ' "$SERVER_CONF" > "$temp_config"
      remaining="$(jq '(.inbounds // []) | length' "$temp_config")"

      if (( remaining > 0 )); then
        sing-box check -c "$temp_config"
        install -m 600 "$temp_config" "$SERVER_CONF"
      else
        service_disable
        rm -f "$SERVER_CONF"
      fi
      rm -f "$temp_config"
    fi
  else
    find_latest_backup
    if [[ -n "$LATEST_BACKUP_DIR" ]]; then
      backup_status="$LATEST_BACKUP_DIR (existing backup retained)"
    fi
  fi

  if [[ "$remove_anytls" == true ]]; then
    remove_anytls_files
  fi
  if [[ "$remove_vless" == true ]]; then
    remove_vless_files
  fi
  if [[ "$remove_hy2" == true ]]; then
    remove_hy2_files
  fi
  if [[ "$remove_snell5" == true ]]; then
    remove_snell_files 5
  fi
  if [[ "$remove_snell6" == true ]]; then
    remove_snell_files 6
  fi
  rm -f "$COMBINED_INFO"

  service_reload

  if (( matched > 0 && remaining > 0 )); then
    service_enable
    service_restart
  fi

  if (( PURGE_SING_BOX )); then
    if [[ -s "$SERVER_CONF" ]] && command -v jq >/dev/null 2>&1 \
      && (( $(jq '(.inbounds // []) | length' "$SERVER_CONF") > 0 )); then
      echo "错误：仍有其他 sing-box 入站，因此未移除软件包"
      echo "配置备份：$backup_status"
      exit 1
    fi
    service_disable
    purge_sing_box_package
  fi

  echo
  echo "卸载完成。"
  echo "  卸载范围：$UNINSTALL_SCOPE"
  echo "  已移除的匹配入站数：$matched"
  echo "  备份位置：$backup_status"
  if (( ! PURGE_SING_BOX )); then
    echo "  sing-box 软件包：已保留"
  fi
}

prepare_inputs() {
  REALITY_DOMAIN="$(strip_host "$REALITY_DOMAIN")"
  VLESS_DOMAIN="$(strip_host "$VLESS_DOMAIN")"
  HY2_SNI="$(strip_host "$HY2_SNI")"

  if (( INSTALL_ANYTLS )); then
    if [[ -z "$REALITY_DOMAIN" || "$REALITY_DOMAIN" =~ [[:space:]] ]]; then
      echo "错误：REALITY 域名不能为空或包含空白字符"
      exit 1
    fi

    if [[ -z "$ANYTLS_PORT" || "$ANYTLS_PORT" == "auto" || "$ANYTLS_PORT" == "random" ]]; then
      ANYTLS_PORT="$(pick_random_free_high_tcp_port)"
      ANYTLS_PORT_MODE="自动随机"
    elif validate_port "$ANYTLS_PORT"; then
      ANYTLS_PORT_MODE="手动指定"
    else
      echo "错误：无效的 AnyTLS 端口：$ANYTLS_PORT"
      exit 1
    fi

    if is_tcp_port_in_use_by_other "$ANYTLS_PORT"; then
      echo "错误：TCP 端口 $ANYTLS_PORT 已被其他进程占用"
      ss -H -lntp 2>/dev/null | awk -v p="$ANYTLS_PORT" '$4 ~ ":" p "$" {print}' || true
      exit 1
    fi
  fi

  if (( INSTALL_VLESS )); then
    if [[ -z "$VLESS_DOMAIN" || "$VLESS_DOMAIN" =~ [[:space:]] ]]; then
      echo "错误：VLESS REALITY 域名不能为空或包含空白字符"
      exit 1
    fi

    if [[ -z "$VLESS_PORT" || "$VLESS_PORT" == "auto" || "$VLESS_PORT" == "random" ]]; then
      VLESS_PORT="$(pick_random_free_high_tcp_port)"
      while (( INSTALL_ANYTLS )) && [[ "$VLESS_PORT" == "$ANYTLS_PORT" ]]; do
        VLESS_PORT="$(pick_random_free_high_tcp_port)"
      done
      VLESS_PORT_MODE="自动随机"
    elif validate_port "$VLESS_PORT"; then
      VLESS_PORT_MODE="手动指定"
    else
      echo "错误：无效的 VLESS 端口：$VLESS_PORT"
      exit 1
    fi

    if (( INSTALL_ANYTLS )) && [[ "$VLESS_PORT" == "$ANYTLS_PORT" ]]; then
      echo "错误：VLESS 端口不能与 AnyTLS 端口相同：$VLESS_PORT"
      exit 1
    fi

    if is_tcp_port_in_use_by_other "$VLESS_PORT"; then
      echo "错误：TCP 端口 $VLESS_PORT 已被其他进程占用"
      ss -H -lntp 2>/dev/null | awk -v p="$VLESS_PORT" '$4 ~ ":" p "$" {print}' || true
      exit 1
    fi
  fi

  if (( INSTALL_SNELL5 )); then
    if [[ -z "$SNELL5_PORT" || "$SNELL5_PORT" == "auto" || "$SNELL5_PORT" == "random" ]]; then
      SNELL5_PORT="$(pick_random_free_high_tcp_port)"
      while { (( INSTALL_ANYTLS )) && [[ "$SNELL5_PORT" == "$ANYTLS_PORT" ]]; } \
        || { (( INSTALL_VLESS )) && [[ "$SNELL5_PORT" == "$VLESS_PORT" ]]; }; do
        SNELL5_PORT="$(pick_random_free_high_tcp_port)"
      done
      SNELL5_PORT_MODE="自动随机"
    elif validate_port "$SNELL5_PORT"; then
      SNELL5_PORT_MODE="手动指定"
    else
      echo "错误：无效的 Snell v5 端口：$SNELL5_PORT"
      exit 1
    fi
    [[ "$SNELL5_OBFS_MODE" == "none" || "$SNELL5_OBFS_MODE" == "http" ]] || {
      echo "错误：Snell v5 混淆只能是 none 或 http"; exit 1;
    }
    if { (( INSTALL_ANYTLS )) && [[ "$SNELL5_PORT" == "$ANYTLS_PORT" ]]; } \
      || { (( INSTALL_VLESS )) && [[ "$SNELL5_PORT" == "$VLESS_PORT" ]]; }; then
      echo "错误：Snell v5 端口与本次安装的其他 TCP 协议重复：$SNELL5_PORT"
      exit 1
    fi
    is_tcp_port_in_use_by_other "$SNELL5_PORT" && { echo "错误：TCP 端口 $SNELL5_PORT 已被其他进程占用"; exit 1; }
  fi

  if (( INSTALL_SNELL6 )); then
    if [[ -z "$SNELL6_PORT" || "$SNELL6_PORT" == "auto" || "$SNELL6_PORT" == "random" ]]; then
      SNELL6_PORT="$(pick_random_free_high_tcp_port)"
      while { (( INSTALL_ANYTLS )) && [[ "$SNELL6_PORT" == "$ANYTLS_PORT" ]]; } \
        || { (( INSTALL_VLESS )) && [[ "$SNELL6_PORT" == "$VLESS_PORT" ]]; } \
        || { (( INSTALL_SNELL5 )) && [[ "$SNELL6_PORT" == "$SNELL5_PORT" ]]; }; do
        SNELL6_PORT="$(pick_random_free_high_tcp_port)"
      done
      SNELL6_PORT_MODE="自动随机"
    elif validate_port "$SNELL6_PORT"; then
      SNELL6_PORT_MODE="手动指定"
    else
      echo "错误：无效的 Snell v6 端口：$SNELL6_PORT"
      exit 1
    fi
    [[ "$SNELL6_MODE" == "default" || "$SNELL6_MODE" == "unshaped" || "$SNELL6_MODE" == "unsafe-raw" ]] || {
      echo "错误：Snell v6 模式只能是 default、unshaped 或 unsafe-raw"; exit 1;
    }
    if { (( INSTALL_ANYTLS )) && [[ "$SNELL6_PORT" == "$ANYTLS_PORT" ]]; } \
      || { (( INSTALL_VLESS )) && [[ "$SNELL6_PORT" == "$VLESS_PORT" ]]; } \
      || { (( INSTALL_SNELL5 )) && [[ "$SNELL6_PORT" == "$SNELL5_PORT" ]]; }; then
      echo "错误：Snell v6 端口与本次安装的其他 TCP 协议重复：$SNELL6_PORT"
      exit 1
    fi
    is_tcp_port_in_use_by_other "$SNELL6_PORT" && { echo "错误：TCP 端口 $SNELL6_PORT 已被其他进程占用"; exit 1; }
  fi

  if (( INSTALL_HY2 )); then
    [[ "$OBFS" == "on" ]] && OBFS="gecko"

    if [[ -z "$HY2_SNI" || "$HY2_SNI" =~ [[:space:]] ]]; then
      echo "错误：Hysteria2 SNI 不能为空或包含空白字符"
      exit 1
    fi

    normalize_hop_ports
    build_server_ports_json

    if [[ -z "$HY2_PORT" || "$HY2_PORT" == "auto" || "$HY2_PORT" == "random" ]]; then
      HY2_PORT="$FIRST_HOP_PORT"
      HY2_PORT_MODE="跳跃范围首端口"
    elif validate_port "$HY2_PORT"; then
      HY2_PORT_MODE="手动指定"
    else
      echo "错误：无效的 Hysteria2 监听端口：$HY2_PORT"
      exit 1
    fi

    if ! validate_positive_number "$HOP_INTERVAL" || (( HOP_INTERVAL < 5 )); then
      echo "错误：Hysteria2 跳跃间隔必须是大于或等于 5 的整数"
      exit 1
    fi

    if [[ -n "$UP_MBPS" ]] && ! validate_positive_number "$UP_MBPS"; then
      echo "错误：--up 必须是正整数"
      exit 1
    fi

    if [[ -n "$DOWN_MBPS" ]] && ! validate_positive_number "$DOWN_MBPS"; then
      echo "错误：--down 必须是正整数"
      exit 1
    fi

    if [[ "$OBFS" != "gecko" && "$OBFS" != "salamander" && "$OBFS" != "off" ]]; then
      echo "错误：OBFS 只能设置为 gecko、salamander 或 off"
      exit 1
    fi

    if [[ "$OBFS" == "gecko" ]]; then
      if ! validate_positive_number "$GECKO_MIN_PACKET_SIZE" \
        || ! validate_positive_number "$GECKO_MAX_PACKET_SIZE" \
        || (( GECKO_MIN_PACKET_SIZE > GECKO_MAX_PACKET_SIZE )); then
        echo "错误：Gecko 包长必须是正整数，且最小值不能大于最大值"
        exit 1
      fi
    fi

    if ! validate_proxy_name; then
      echo "错误：代理名称只能包含字母、数字、点、下划线和连字符"
      exit 1
    fi

    if is_udp_port_in_use_by_other "$HY2_PORT"; then
      echo "错误：UDP 端口 $HY2_PORT 已被其他进程占用"
      ss -H -lunp 2>/dev/null | awk -v p="$HY2_PORT" '$4 ~ ":" p "$" {print}' || true
      exit 1
    fi
  fi
}

fetch_latest_alpha_version() {
  local url payload version
  local -a sources=(
    "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=30"
    "https://api.github.com/repos/SagerNet/sing-box/tags?per_page=100"
    "https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box"
  )

  for url in "${sources[@]}"; do
    if payload="$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      --connect-timeout 10 --max-time 60 "$url")"; then
      version="$(printf '%s' "$payload" | jq -r '
        .. | strings
        | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+-alpha\\.[0-9]+$"))
      ' | sed 's/^v//' | sort -V | tail -n 1)"
      if [[ -n "$version" ]]; then
        printf '%s' "$version"
        return 0
      fi
    fi
    echo "警告：版本源暂时不可用，正在尝试备用源：$url" >&2
  done

  return 1
}

install_dependencies() {
  local alpha_version attempt installed=0

  echo "正在安装依赖……"
  if [[ "$PLATFORM" == "alpine" ]]; then
    apk add --no-cache bash curl openssl ca-certificates iproute2 coreutils jq nftables iptables openrc
  else
    apt update
    apt install -y curl openssl ca-certificates iproute2 coreutils jq nftables iptables
  fi
  if ! alpha_version="$(fetch_latest_alpha_version)"; then
    echo "错误：获取 sing-box 最新 alpha 版本失败"
    exit 1
  fi
  echo "正在安装 sing-box v${alpha_version}……"
  for attempt in 1 2 3; do
    if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      --connect-timeout 10 --max-time 60 https://sing-box.app/install.sh \
      | sh -s -- --version "$alpha_version"; then
      installed=1
      break
    fi
    if (( attempt < 3 )); then
      echo "警告：sing-box 下载失败，正在进行第 $(( attempt + 1 )) 次尝试……" >&2
      sleep 3
    fi
  done
  if (( ! installed )) || ! command -v sing-box >/dev/null 2>&1; then
    echo "错误：sing-box v${alpha_version} 安装失败，请稍后重试"
    exit 1
  fi
  mkdir -p /etc/sing-box
}

generate_anytls_secrets() {
  local keypair

  keypair="$(sing-box generate reality-keypair)"
  ANYTLS_PRIVATE_KEY="$(echo "$keypair" | awk -F': ' '/PrivateKey/ {print $2}')"
  ANYTLS_PUBLIC_KEY="$(echo "$keypair" | awk -F': ' '/PublicKey/ {print $2}')"
  ANYTLS_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
  ANYTLS_SHORT_ID="$(openssl rand -hex 8)"

  if [[ -z "$ANYTLS_PRIVATE_KEY" || -z "$ANYTLS_PUBLIC_KEY" || -z "$ANYTLS_PASSWORD" || -z "$ANYTLS_SHORT_ID" ]]; then
    echo "错误：生成 AnyTLS + REALITY 密钥失败"
    exit 1
  fi
}

generate_vless_secrets() {
  local keypair

  keypair="$(sing-box generate reality-keypair)"
  VLESS_PRIVATE_KEY="$(echo "$keypair" | awk -F': ' '/PrivateKey/ {print $2}')"
  VLESS_PUBLIC_KEY="$(echo "$keypair" | awk -F': ' '/PublicKey/ {print $2}')"
  VLESS_UUID="$(sing-box generate uuid)"
  VLESS_SHORT_ID="$(openssl rand -hex 8)"

  if [[ -z "$VLESS_PRIVATE_KEY" || -z "$VLESS_PUBLIC_KEY" || -z "$VLESS_UUID" || -z "$VLESS_SHORT_ID" ]]; then
    echo "错误：生成 VLESS + REALITY 密钥失败"
    exit 1
  fi
}

generate_hy2_secrets() {
  if [[ "$OBFS" != "off" && -z "$OBFS_PASSWORD" ]]; then
    OBFS_PASSWORD="$(openssl rand -hex 16)"
  fi

  HY2_PASSWORD="$(openssl rand -hex 32)"
}

generate_snell_secrets() {
  if (( INSTALL_SNELL5 )); then
    SNELL5_PSK="$(openssl rand -base64 32 | tr -d '\n')"
  fi
  if (( INSTALL_SNELL6 )); then
    SNELL6_PSK="$(openssl rand -base64 32 | tr -d '\n')"
  fi
}

anytls_inbound_json() {
  cat << JSON
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${ANYTLS_PORT},
      "users": [
        {
          "password": "${ANYTLS_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_DOMAIN}",
            "server_port": 443
          },
          "private_key": "${ANYTLS_PRIVATE_KEY}",
          "short_id": [
            "${ANYTLS_SHORT_ID}"
          ]
        }
      }
    }
JSON
}

vless_inbound_json() {
  cat << JSON
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": ${VLESS_PORT},
      "users": [
        {
          "uuid": "${VLESS_UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${VLESS_DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${VLESS_DOMAIN}",
            "server_port": 443
          },
          "private_key": "${VLESS_PRIVATE_KEY}",
          "short_id": [
            "${VLESS_SHORT_ID}"
          ]
        }
      }
    }
JSON
}

hy2_inbound_json() {
  cat << JSON
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
$(json_number_field "up_mbps" "$UP_MBPS")$(json_number_field "down_mbps" "$DOWN_MBPS")$(json_obfs_field)      "users": [
        {
          "password": "${HY2_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${HY2_SNI}",
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    }
JSON
}

snell5_inbound_json() {
  cat << JSON
    {
      "type": "snell",
      "tag": "snell5-in",
      "listen": "::",
      "listen_port": ${SNELL5_PORT},
      "version": 5,
      "psk": "${SNELL5_PSK}",
      "obfs_mode": "${SNELL5_OBFS_MODE}"
    }
JSON
}

snell6_inbound_json() {
  cat << JSON
    {
      "type": "snell",
      "tag": "snell6-in",
      "listen": "::",
      "listen_port": ${SNELL6_PORT},
      "version": 6,
      "psk": "${SNELL6_PSK}",
      "mode": "${SNELL6_MODE}"
    }
JSON
}

selected_inbounds_json() {
  local inbounds="" sep=""

  if (( INSTALL_ANYTLS )); then
    inbounds="$(anytls_inbound_json)"
    sep=","
  fi

  if (( INSTALL_VLESS )); then
    inbounds="${inbounds}${sep}
$(vless_inbound_json)"
    sep=","
  fi

  if (( INSTALL_HY2 )); then
    inbounds="${inbounds}${sep}
$(hy2_inbound_json)"
    sep=","
  fi

  if (( INSTALL_SNELL5 )); then
    inbounds="${inbounds}${sep}
$(snell5_inbound_json)"
    sep=","
  fi

  if (( INSTALL_SNELL6 )); then
    inbounds="${inbounds}${sep}
$(snell6_inbound_json)"
  fi

  cat << JSON
[
${inbounds}
]
JSON
}

write_fresh_server_config() {
  local inbounds

  inbounds="$(selected_inbounds_json)"
  inbounds="${inbounds#[}"
  inbounds="${inbounds%]}"

  cat > "$SERVER_CONF" << JSON
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON
}

write_server_config() {
  local selected_file temp_config

  if [[ "$CONFIG_POLICY" != "merge" || ! -s "$SERVER_CONF" ]]; then
    write_fresh_server_config
    return 0
  fi

  if ! jq -e . "$SERVER_CONF" >/dev/null; then
    echo "错误：现有 $SERVER_CONF 不是有效 JSON，无法安全追加新协议"
    echo "请修复配置，或使用 --config new 生成全新配置"
    exit 1
  fi

  selected_file="$(mktemp)"
  temp_config="$(mktemp)"
  selected_inbounds_json > "$selected_file"

  jq --slurpfile selected "$selected_file" '
    ($selected[0] | map(.tag)) as $selected_tags
    | .log = (.log // {"level": "info", "timestamp": true})
    | .inbounds = (
        [
          (.inbounds // [])[]
          | select((.tag // "") as $tag | ($selected_tags | index($tag) | not))
        ] + $selected[0]
      )
    | .outbounds = (
        if ((.outbounds // []) | length) > 0 then .outbounds
        else [{"type": "direct", "tag": "direct"}]
        end
      )
  ' "$SERVER_CONF" > "$temp_config"

  install -m 600 "$temp_config" "$SERVER_CONF"
  rm -f "$selected_file" "$temp_config"
}

detect_server_ip() {
  SERVER_IP="$(curl -4 -s --max-time 8 https://api.ipify.org || true)"
  if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="your_vps_ip_or_domain"
  fi
}

write_anytls_client() {
  build_anytls_share_url
  cat > "$ANYTLS_CLIENT_OUT" << JSON
{
  "outbounds": [
    {
      "type": "anytls",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": ${ANYTLS_PORT},
      "password": "${ANYTLS_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_DOMAIN}",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "${ANYTLS_PUBLIC_KEY}",
          "short_id": "${ANYTLS_SHORT_ID}"
        }
      }
    }
  ]
}
JSON

  printf '%s\n' "$ANYTLS_SHARE_URL" > "$ANYTLS_URL_FILE"
  cat > "$ANYTLS_SURGE_CONF" << TXT
# Surge 原生 AnyTLS 不支持 REALITY，不能直接连接此 AnyTLS + REALITY 服务端。
# 请使用同目录的 anytls-sing-box.json 或 anytls-url.txt。
TXT
}

write_vless_client() {
  build_vless_share_url

  cat > "$VLESS_CLIENT_OUT" << JSON
{
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": ${VLESS_PORT},
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${VLESS_DOMAIN}",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "${VLESS_PUBLIC_KEY}",
          "short_id": "${VLESS_SHORT_ID}"
        }
      }
    }
  ]
}
JSON

  printf '%s\n' "$VLESS_SHARE_URL" > "$VLESS_URL_FILE"
  cat > "$VLESS_SURGE_CONF" << TXT
# Surge 当前不支持 VLESS + REALITY，无法生成可用的原生 Surge 代理行。
# 请使用同目录的 vless-sing-box.json 或 vless-url.txt。
TXT
}

write_hy2_clients() {
  build_hy2_share_url
  SURGE_PROXY_LINE="$(build_surge_proxy_line)"

  cat > "$HY2_CLIENT_OUT" << JSON
{
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_ports": ${SERVER_PORTS_JSON},
      "hop_interval": "${HOP_INTERVAL}s",
$(json_number_field "up_mbps" "$UP_MBPS")$(json_number_field "down_mbps" "$DOWN_MBPS")$(json_obfs_field)      "password": "${HY2_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${HY2_SNI}",
        "insecure": true
      }
    }
  ]
}
JSON

  cat > "$SURGE_CONF" << SURGE
[Proxy]
$SURGE_PROXY_LINE

[Proxy Group]
Proxy=select,${PROXY_NAME},DIRECT
SURGE

  printf '%s\n' "$HY2_SHARE_URL" > "$HY2_URL_FILE"
}

write_snell_clients() {
  local lines=""
  local members=""

  build_snell_share_urls

  if (( INSTALL_SNELL5 )); then
    cat > "$SNELL5_CLIENT_OUT" << JSON
{
  "outbounds": [
    {
      "type": "snell",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": ${SNELL5_PORT},
      "version": 4,
      "psk": "${SNELL5_PSK}",
      "network": "tcp",
      "obfs_mode": "${SNELL5_OBFS_MODE}"
    }
  ]
}
JSON
    printf '%s\n' "$SNELL5_SHARE_URL" > "$SNELL5_URL_FILE"
  fi

  if (( INSTALL_SNELL6 )); then
    cat > "$SNELL6_CLIENT_OUT" << JSON
{
  "outbounds": [
    {
      "type": "snell",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": ${SNELL6_PORT},
      "version": 6,
      "psk": "${SNELL6_PSK}",
      "network": "tcp",
      "mode": "${SNELL6_MODE}"
    }
  ]
}
JSON
    printf '%s\n' "$SNELL6_SHARE_URL" > "$SNELL6_URL_FILE"
  fi

  if (( INSTALL_SNELL5 )); then
    SNELL5_SURGE_LINE="SnellV5=snell,${SERVER_IP},${SNELL5_PORT},psk=\"${SNELL5_PSK}\",version=5,tfo=false"
  elif [[ -f "$SNELL5_INFO" ]]; then
    SNELL5_SURGE_LINE="$(sed -n '/^SnellV5=snell,/p' "$SNELL5_INFO" | head -n 1)"
  fi

  if (( INSTALL_SNELL6 )); then
    SNELL6_SURGE_LINE="SnellV6=snell,${SERVER_IP},${SNELL6_PORT},psk=\"${SNELL6_PSK}\",version=6,mode=${SNELL6_MODE},tfo=false"
  elif [[ -f "$SNELL6_INFO" ]]; then
    SNELL6_SURGE_LINE="$(sed -n '/^SnellV6=snell,/p' "$SNELL6_INFO" | head -n 1)"
  fi

  if [[ -n "$SNELL5_SURGE_LINE" ]]; then
    lines="$SNELL5_SURGE_LINE"
    members="SnellV5,"
  fi
  if [[ -n "$SNELL6_SURGE_LINE" ]]; then
    [[ -n "$lines" ]] && lines="${lines}"$'\n'
    lines="${lines}${SNELL6_SURGE_LINE}"
    members="${members}SnellV6,"
  fi

  cat > "$SNELL_SURGE_CONF" << SURGE
[Proxy]
$lines

[Proxy Group]
Snell=select,${members}DIRECT
SURGE

  if (( INSTALL_SNELL5 )); then
    printf '[Proxy]\n%s\n' "$SNELL5_SURGE_LINE" > "$SNELL5_SURGE_CONF"
  fi
  if (( INSTALL_SNELL6 )); then
    printf '[Proxy]\n%s\n' "$SNELL6_SURGE_LINE" > "$SNELL6_SURGE_CONF"
  fi
}

write_info_files() {
  local port_service_config
  local has_anytls=0
  local has_vless=0
  local has_hy2=0
  local has_snell5=0
  local has_snell6=0

  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    port_service_config="$SYSTEMD_DROPIN"
  else
    port_service_config="$OPENRC_PORT_SERVICE"
  fi

  if jq -e '.inbounds[]? | select(.tag == "anytls-in")' "$SERVER_CONF" >/dev/null 2>&1; then
    has_anytls=1
  fi
  if jq -e '.inbounds[]? | select(.tag == "vless-in")' "$SERVER_CONF" >/dev/null 2>&1; then
    has_vless=1
  fi
  if jq -e '.inbounds[]? | select(.tag == "hy2-in")' "$SERVER_CONF" >/dev/null 2>&1; then
    has_hy2=1
  fi
  jq -e '.inbounds[]? | select(.tag == "snell5-in")' "$SERVER_CONF" >/dev/null 2>&1 && has_snell5=1
  jq -e '.inbounds[]? | select(.tag == "snell6-in")' "$SERVER_CONF" >/dev/null 2>&1 && has_snell6=1

  cat > "$COMBINED_INFO" << TXT
sbox-reality 统一安装完成

服务端：
  配置文件：$SERVER_CONF
  已安装 AnyTLS + REALITY：$has_anytls
  已安装 VLESS + REALITY：$has_vless
  已安装 Hysteria2 + Surge：$has_hy2
  已安装 Snell v5：$has_snell5
  已安装 Snell v6：$has_snell6
TXT

  if (( INSTALL_ANYTLS )); then
    cat > "$ANYTLS_INFO" << TXT
AnyTLS + REALITY 安装完成

服务端：
  配置文件：$SERVER_CONF
  监听端口：$ANYTLS_PORT
  端口模式：$ANYTLS_PORT_MODE
  握手域名：$REALITY_DOMAIN

客户端出站配置：
  文件：$ANYTLS_CLIENT_OUT
  URL：$ANYTLS_URL_FILE
  Surge：$ANYTLS_SURGE_CONF（Surge 不支持 REALITY，仅提供兼容性说明）

客户端链接：
$ANYTLS_SHARE_URL

客户端参数：
  服务器：$SERVER_IP
  服务器端口：$ANYTLS_PORT
  密码：$ANYTLS_PASSWORD
  服务器名称：$REALITY_DOMAIN
  公钥：$ANYTLS_PUBLIC_KEY
  Short ID：$ANYTLS_SHORT_ID
TXT
    cat "$ANYTLS_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  elif [[ -f "$ANYTLS_INFO" ]]; then
    cat "$ANYTLS_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  fi

  if (( INSTALL_VLESS )); then
    cat > "$VLESS_INFO" << TXT
VLESS + REALITY 安装完成

服务端：
  配置文件：$SERVER_CONF
  监听端口：$VLESS_PORT
  端口模式：$VLESS_PORT_MODE
  握手域名：$VLESS_DOMAIN

客户端文件：
  sing-box 出站配置：$VLESS_CLIENT_OUT
  VLESS 分享链接：$VLESS_URL_FILE
  Surge：$VLESS_SURGE_CONF（Surge 不支持 VLESS + REALITY，仅提供兼容性说明）

客户端链接：
$VLESS_SHARE_URL

客户端参数：
  服务器：$SERVER_IP
  服务器端口：$VLESS_PORT
  UUID：$VLESS_UUID
  Flow：xtls-rprx-vision
  服务器名称：$VLESS_DOMAIN
  Fingerprint：chrome
  公钥：$VLESS_PUBLIC_KEY
  Short ID：$VLESS_SHORT_ID
TXT
    cat "$VLESS_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  elif [[ -f "$VLESS_INFO" ]]; then
    cat "$VLESS_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  fi

  if (( INSTALL_HY2 )); then
    cat > "$HY2_INFO" << TXT
Hysteria2 + Surge 端口跳跃安装完成

服务端：
  配置文件：$SERVER_CONF
  监听端口：$HY2_PORT
  端口模式：$HY2_PORT_MODE
  SNI：$HY2_SNI
  证书：$CERT_PATH
  私钥：$KEY_PATH

端口跳跃：
  公共 UDP 端口：$NORMALIZED_HOP_PORTS
  跳跃间隔：${HOP_INTERVAL} 秒
  辅助脚本：$PORT_HELPER
  环境文件：$PORT_ENV
  服务配置：$port_service_config

客户端文件：
  sing-box 出站配置：$HY2_CLIENT_OUT
  Surge 配置片段：$SURGE_CONF
  Hysteria2 链接：$HY2_URL_FILE

客户端链接：
  $HY2_SHARE_URL

Surge 代理配置：
$SURGE_PROXY_LINE

客户端参数：
  服务器：$SERVER_IP
  监听端口：$HY2_PORT
  跳跃端口：$NORMALIZED_HOP_PORTS
  跳跃间隔：$HOP_INTERVAL
  密码：$HY2_PASSWORD
  SNI：$HY2_SNI
  跳过证书验证：true
TXT

    if [[ "$OBFS" != "off" ]]; then
      cat >> "$HY2_INFO" << TXT
  混淆类型：$OBFS
  混淆密码：$OBFS_PASSWORD
TXT
      if [[ "$OBFS" == "gecko" ]]; then
        cat >> "$HY2_INFO" << TXT
  Gecko 包长：${GECKO_MIN_PACKET_SIZE}-${GECKO_MAX_PACKET_SIZE}
TXT
      fi
    fi

    cat >> "$HY2_INFO" << TXT

防火墙：
  请放行公共 UDP 端口：$NORMALIZED_HOP_PORTS
  如果本机防火墙在重定向后过滤流量，还需放行 UDP 监听端口：$HY2_PORT
TXT
    cat "$HY2_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  elif [[ -f "$HY2_INFO" ]]; then
    cat "$HY2_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  fi

  if (( INSTALL_SNELL5 )); then
    cat > "$SNELL5_INFO" << TXT
Snell v5 安装完成

服务端：
  配置文件：$SERVER_CONF
  监听端口：$SNELL5_PORT
  端口模式：$SNELL5_PORT_MODE
  PSK：$SNELL5_PSK
  HTTP 混淆：$SNELL5_OBFS_MODE

Surge 代理配置：
$SNELL5_SURGE_LINE

客户端文件：
  sing-box：$SNELL5_CLIENT_OUT
  URL：$SNELL5_URL_FILE
  Surge：$SNELL5_SURGE_CONF

客户端链接（约定格式，Snell 无官方统一 URI 标准）：
$SNELL5_SHARE_URL

说明：sing-box 出站按官方要求使用 version 4 连接 v5 TCP 服务端；v5 不支持 QUIC Proxy。
TXT
    cat "$SNELL5_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  elif [[ -f "$SNELL5_INFO" ]]; then
    cat "$SNELL5_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  fi

  if (( INSTALL_SNELL6 )); then
    cat > "$SNELL6_INFO" << TXT
Snell v6 安装完成

服务端：
  配置文件：$SERVER_CONF
  监听端口：$SNELL6_PORT
  端口模式：$SNELL6_PORT_MODE
  PSK：$SNELL6_PSK
  流量模式：$SNELL6_MODE

Surge 代理配置：
$SNELL6_SURGE_LINE

客户端文件：
  sing-box：$SNELL6_CLIENT_OUT
  URL：$SNELL6_URL_FILE
  Surge：$SNELL6_SURGE_CONF

客户端链接（约定格式，Snell 无官方统一 URI 标准）：
$SNELL6_SHARE_URL
TXT
    cat "$SNELL6_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  elif [[ -f "$SNELL6_INFO" ]]; then
    cat "$SNELL6_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  fi

  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    cat >> "$COMBINED_INFO" << TXT
常用命令：
  systemctl status sing-box --no-pager
  journalctl -u sing-box -f
  systemctl restart sing-box
TXT
  else
    cat >> "$COMBINED_INFO" << TXT
常用命令：
  rc-service sing-box status
  rc-service sing-box restart
  tail -f /var/log/messages
TXT
  fi

  if (( INSTALL_HY2 )); then
    cat >> "$COMBINED_INFO" << TXT
  $PORT_HELPER clean
  $PORT_HELPER apply
TXT
  fi

}

print_summary() {
  echo
  cat "$COMBINED_INFO"

  if (( INSTALL_ANYTLS )); then
    echo
    echo "AnyTLS + REALITY 客户端出站配置："
    cat "$ANYTLS_CLIENT_OUT"
  fi

  if (( INSTALL_VLESS )); then
    echo
    echo "VLESS + REALITY 分享链接："
    cat "$VLESS_URL_FILE"
    echo
    echo "VLESS + REALITY 客户端出站配置："
    cat "$VLESS_CLIENT_OUT"
  fi

  if (( INSTALL_HY2 )); then
    echo
    echo "Surge 配置片段："
    cat "$SURGE_CONF"
    echo
    echo "Hysteria2 链接："
    cat "$HY2_URL_FILE"
    echo
    echo "Hysteria2 sing-box 客户端出站配置："
    cat "$HY2_CLIENT_OUT"
  fi

  if (( INSTALL_SNELL5 || INSTALL_SNELL6 )); then
    echo
    echo "Snell Surge 配置片段："
    cat "$SNELL_SURGE_CONF"
  fi
}

main() {
  choose_mode
  normalize_mode
  choose_uninstall_scope

  if (( PURGE_SING_BOX )) && [[ "$ACTION" != "uninstall" ]]; then
    echo "错误：--purge 只能与 --uninstall all 一起使用"
    exit 1
  fi

  if [[ $EUID -ne 0 ]]; then
    echo "错误：请使用 root 用户运行脚本"
    echo "示例：sudo bash $0 --mode full"
    exit 1
  fi

  detect_platform
  prepare_output_dir

  if [[ "$ACTION" == "uninstall" ]]; then
    uninstall_selected
    return 0
  fi

  if [[ "$ACTION" == "restore" ]]; then
    choose_config_policy
    restore_latest_backup
    return 0
  fi

  apply_shared_port
  choose_config_policy

  if [[ "$CONFIG_POLICY" == "restore" ]]; then
    restore_latest_backup
    return 0
  fi

  if [[ "$CONFIG_POLICY" == "keep" ]]; then
    reuse_existing_config
    return 0
  fi

  prepare_inputs

  echo "sbox-reality 统一安装脚本"
  echo "  安装 AnyTLS + REALITY：$INSTALL_ANYTLS"
  echo "  安装 VLESS + REALITY：$INSTALL_VLESS"
  echo "  安装 Hysteria2 + Surge：$INSTALL_HY2"
  echo "  安装 Snell v5：$INSTALL_SNELL5"
  echo "  安装 Snell v6：$INSTALL_SNELL6"
  if (( INSTALL_ANYTLS )); then
    echo "  AnyTLS 域名：$REALITY_DOMAIN"
    echo "  AnyTLS 端口：$ANYTLS_PORT ($ANYTLS_PORT_MODE)"
  fi
  if (( INSTALL_VLESS )); then
    echo "  VLESS 域名：$VLESS_DOMAIN"
    echo "  VLESS 端口：$VLESS_PORT ($VLESS_PORT_MODE)"
  fi
  if (( INSTALL_HY2 )); then
    echo "  Hysteria2 SNI：$HY2_SNI"
    echo "  Hysteria2 端口：$HY2_PORT ($HY2_PORT_MODE)"
    echo "  Hysteria2 跳跃端口：$NORMALIZED_HOP_PORTS"
    echo "  Hysteria2 跳跃间隔：${HOP_INTERVAL} 秒"
    echo "  Hysteria2 混淆：$OBFS"
  fi
  if (( INSTALL_SNELL5 )); then
    echo "  Snell v5 端口：$SNELL5_PORT ($SNELL5_PORT_MODE)"
    echo "  Snell v5 混淆：$SNELL5_OBFS_MODE"
  fi
  if (( INSTALL_SNELL6 )); then
    echo "  Snell v6 端口：$SNELL6_PORT ($SNELL6_PORT_MODE)"
    echo "  Snell v6 模式：$SNELL6_MODE"
  fi
  echo

  install_dependencies

  if (( INSTALL_ANYTLS )); then
    generate_anytls_secrets
  fi

  if (( INSTALL_VLESS )); then
    generate_vless_secrets
  fi

  generate_snell_secrets

  if (( INSTALL_HY2 )); then
    prepare_certificate
    generate_hy2_secrets
    write_port_hopping_helper
  elif [[ "$CONFIG_POLICY" == "new" ]]; then
    disable_hy2_port_hopping
  fi

  write_server_config
  detect_server_ip

  if (( INSTALL_ANYTLS )); then
    write_anytls_client
  fi

  if (( INSTALL_VLESS )); then
    write_vless_client
  fi

  if (( INSTALL_HY2 )); then
    write_hy2_clients
  fi

  if (( INSTALL_SNELL5 || INSTALL_SNELL6 )); then
    write_snell_clients
  fi

  sing-box check -c "$SERVER_CONF"
  service_reload
  service_enable
  service_restart

  write_info_files
  print_summary
}

main "$@"
