#!/usr/bin/env bash
set -euo pipefail

INSTALL_MODE="${INSTALL_MODE:-}"
SHARED_PORT="${PORT:-}"
CUSTOMER_ID="${CUSTOMER_ID:-}"
CUSTOMER_QUOTA="${CUSTOMER_QUOTA:-0}"
CUSTOMER_RESET_DAY="${CUSTOMER_RESET_DAY:-1}"
CUSTOMER_EXPIRES="${CUSTOMER_EXPIRES:-}"
TG_TOKEN="${SBOX_TG_BOT_TOKEN:-}"
TG_CHAT_ID="${SBOX_TG_CHAT_ID:-}"
INIT_MANAGER="${INIT_MANAGER:-0}"
ACTION="install"
ACTION_RESTORE_EXPLICIT=0
ACTION_UNINSTALL_EXPLICIT=0
UNINSTALL_SCOPE="${UNINSTALL_SCOPE:-}"
CONFIG_POLICY="${CONFIG_POLICY:-ask}"
PURGE_SING_BOX=0
ASSUME_YES=0
HY2_PORT_HOPPING_EXPLICIT=0
HOP_PORTS_EXPLICIT=0
WARP_RULES_INPUT="${WARP_RULES:-}"
WARP_RULES_JSON="[]"
WARP_RULES_EXPLICIT=0
WARP_OFF=0
WARP_RESET=0
WARP_INSTALL_ACTIVE=0
WARP_INSTALL_RULES_JSON="[]"
WARP_STAGED_CREDENTIALS=""
WARP_INSTALL_STAGE_DIR=""
WARP_INSTALL_SNAPSHOT_DIR=""
WARP_INSTALL_CONFIG_EXISTED=0
WARP_INSTALL_CREDENTIALS_EXISTED=0
INSTALL_TRANSACTION_ACTIVE=0
INSTALL_TRANSACTION_DIR=""
INSTALL_SERVICE_WAS_ACTIVE=0
INSTALL_SERVICE_WAS_ENABLED=0

[[ -n "${HY2_PORT_HOPPING+x}" ]] && HY2_PORT_HOPPING_EXPLICIT=1
[[ -n "${HOP_PORTS+x}" ]] && HOP_PORTS_EXPLICIT=1

REALITY_DOMAIN="${REALITY_DOMAIN:-${DOMAIN:-www.apple.com}}"
ANYTLS_PORT="${ANYTLS_PORT:-auto}"
VLESS_DOMAIN="${VLESS_DOMAIN:-${REALITY_DOMAIN}}"
VLESS_PORT="${VLESS_PORT:-auto}"
SNELL5_PORT="${SNELL5_PORT:-auto}"
SNELL6_PORT="${SNELL6_PORT:-auto}"
SNELL5_OBFS_MODE="${SNELL5_OBFS_MODE:-none}"
SNELL6_MODE="${SNELL6_MODE:-default}"
DIRECT_PORT="${DIRECT_PORT:-auto}"
DIRECT_TARGET_ADDRESS="${DIRECT_TARGET_ADDRESS:-}"
DIRECT_TARGET_PORT="${DIRECT_TARGET_PORT:-}"
SERVER_HOST="${SERVER_HOST:-}"
HIGH_PORT_MIN="${HIGH_PORT_MIN:-20000}"
HIGH_PORT_MAX="${HIGH_PORT_MAX:-65535}"

HY2_SNI="${HY2_SNI:-${SNI:-www.bing.com}}"
HY2_PORT="${HY2_PORT:-auto}"
HY2_PORT_HOPPING="${HY2_PORT_HOPPING:-off}"
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
WARP_CREDENTIALS_FILE="/etc/sing-box/sbox-warp-credentials.credentials"
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
DIRECT_INFO="$OUTPUT_DIR/direct-info.txt"
SNELL_SURGE_CONF="$OUTPUT_DIR/snell-surge.conf"
COMBINED_INFO="$OUTPUT_DIR/all-info.txt"
BACKUP_ROOT="/root/sbox-reality-backups"
BACKUP_MARKER=".sbox-reality-backup"
BBR_SYSCTL_CONF="/etc/sysctl.d/99-sbox-reality-bbr.conf"
SBOX_STATE_DIR="/etc/sbox-reality"
NODES_FILE="$SBOX_STATE_DIR/nodes.json"
TRAFFIC_STATE="$SBOX_STATE_DIR/traffic/state.json"
CLIENTS_ROOT="/root/sbox-reality/clients"
TRAFFIC_SERVICE="/etc/systemd/system/sbox-traffic.service"
TRAFFIC_TIMER="/etc/systemd/system/sbox-traffic.timer"
OPENRC_TRAFFIC_SCRIPT="/etc/init.d/sbox-traffic"
NOTIFY_ENV="$SBOX_STATE_DIR/notify.env"
SERVER_HOST_FILE="$SBOX_STATE_DIR/server-host"
MANAGER_NODE_BIN="/usr/local/sbin/sbox-node"
MANAGER_TRAFFIC_BIN="/usr/local/sbin/sbox-traffic"
MANAGEMENT_MODE=""
MANAGEMENT_ARGS=()

# Path overrides are accepted only by the isolated test harness. Production
# runs always use the fixed system locations above.
if [[ "${SBOX_REALITY_TEST_MODE:-0}" == "1" ]]; then
  SERVER_CONF="${SERVER_CONF_OVERRIDE:-$SERVER_CONF}"
  WARP_CREDENTIALS_FILE="${WARP_CREDENTIALS_FILE_OVERRIDE:-$WARP_CREDENTIALS_FILE}"
  BACKUP_ROOT="${BACKUP_ROOT_OVERRIDE:-$BACKUP_ROOT}"
  OUTPUT_DIR="${OUTPUT_DIR_OVERRIDE:-$OUTPUT_DIR}"
  SBOX_STATE_DIR="${SBOX_STATE_DIR_OVERRIDE:-$SBOX_STATE_DIR}"
  NODES_FILE="$SBOX_STATE_DIR/nodes.json"
  TRAFFIC_STATE="$SBOX_STATE_DIR/traffic/state.json"
  NOTIFY_ENV="$SBOX_STATE_DIR/notify.env"
  SERVER_HOST_FILE="$SBOX_STATE_DIR/server-host"
  CLIENTS_ROOT="${CLIENTS_ROOT_OVERRIDE:-$CLIENTS_ROOT}"
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
  DIRECT_INFO="$OUTPUT_DIR/direct-info.txt"
  SNELL_SURGE_CONF="$OUTPUT_DIR/snell-surge.conf"
  COMBINED_INFO="$OUTPUT_DIR/all-info.txt"
fi

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
INSTALL_DIRECT=0
ANYTLS_PORT_MODE=""
VLESS_PORT_MODE=""
HY2_PORT_MODE=""
SNELL5_PORT_MODE=""
SNELL6_PORT_MODE=""
DIRECT_PORT_MODE=""
FIRST_HOP_PORT=""
NORMALIZED_HOP_PORTS=""
SERVER_PORTS_JSON=""
SERVER_IP=""
SERVER_URL_HOST=""

case "$(basename -- "$0")" in
  sbox-node)
    MANAGEMENT_MODE="node"
    MANAGEMENT_ARGS=("$@")
    set --
    ;;
  sbox-traffic)
    MANAGEMENT_MODE="traffic"
    MANAGEMENT_ARGS=("$@")
    set --
    ;;
esac
if [[ -z "$MANAGEMENT_MODE" && $# -gt 0 && ( "$1" == "node" || "$1" == "traffic" ) ]]; then
  MANAGEMENT_MODE="$1"
  shift
  MANAGEMENT_ARGS=("$@")
  set --
fi

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
SING_BOX_BIN=""

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

resolve_sing_box_binary() {
  local candidate resolved=""
  local -a candidates=("/usr/bin/sing-box" "/usr/local/bin/sing-box")

  if command -v sing-box >/dev/null 2>&1; then
    candidates+=("$(command -v sing-box)")
  fi

  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    resolved="$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")"
    if "$resolved" version >/dev/null 2>&1; then
      SING_BOX_BIN="$resolved"
      return 0
    fi
  done

  SING_BOX_BIN=""
  return 1
}

run_sing_box() {
  [[ -n "$SING_BOX_BIN" ]] || resolve_sing_box_binary || {
    echo "错误：找不到可用的 sing-box 二进制" >&2
    return 127
  }
  "$SING_BOX_BIN" "$@"
}

verify_snell_support() {
  local test_config test_output
  (( INSTALL_SNELL5 || INSTALL_SNELL6 )) || return 0

  test_config="$(mktemp)"
  cat > "$test_config" << JSON
{
  "inbounds": [
    {
      "type": "snell",
      "tag": "snell-capability-test",
      "listen": "127.0.0.1",
      "listen_port": 1,
      "version": 6,
      "psk": "snell-test-password"
    }
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
JSON

  if ! test_output="$(run_sing_box check -c "$test_config" 2>&1)"; then
    rm -f "$test_config"
    echo "错误：当前实际调用的 sing-box 不支持 Snell：$SING_BOX_BIN"
    run_sing_box version || true
    echo "$test_output"
    echo "请检查是否存在覆盖 /usr/bin/sing-box 的旧版 /usr/local/bin/sing-box。"
    exit 1
  fi
  rm -f "$test_config"
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
/root/sing-box/direct-udp-info.txt|$DIRECT_INFO
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

service_is_active() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl is-active --quiet sing-box >/dev/null 2>&1
  else
    rc-service sing-box status >/dev/null 2>&1
  fi
}

service_is_enabled() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl is-enabled --quiet sing-box >/dev/null 2>&1
  else
    rc-update show default 2>/dev/null | grep -q '^[[:space:]]*sing-box[[:space:]]'
  fi
}

wait_for_service_active() {
  local attempt

  for attempt in {1..10}; do
    service_is_active && return 0
    sleep 1
  done
  echo "错误：sing-box 服务启动后未进入运行状态" >&2
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl status sing-box --no-pager >&2 || true
  else
    rc-service sing-box status >&2 || true
  fi
  return 1
}

service_restart() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl restart sing-box || return 1
  else
    rc-service sing-box restart >/dev/null 2>&1 || rc-service sing-box start || return 1
  fi
  wait_for_service_active
}

service_disable() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    systemctl disable --now sing-box >/dev/null 2>&1 || true
  else
    rc-service sing-box stop >/dev/null 2>&1 || true
    rc-update del sing-box default >/dev/null 2>&1 || true
  fi
}

restore_install_service_state() {
  if (( INSTALL_SERVICE_WAS_ENABLED )); then
    service_enable || true
  else
    service_disable || true
  fi
  if (( INSTALL_SERVICE_WAS_ACTIVE )); then
    service_restart || true
  else
    service_stop
  fi
}

restore_manager_services() {
  if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
    [[ -f "$TRAFFIC_SERVICE" && -f "$TRAFFIC_TIMER" ]] || return 0
    systemctl daemon-reload
    systemctl enable --now sbox-traffic.timer
  else
    [[ -f "$OPENRC_TRAFFIC_SCRIPT" ]] || return 0
    chmod 0755 "$OPENRC_TRAFFIC_SCRIPT"
    rc-update add sbox-traffic default >/dev/null 2>&1 || true
    rc-service sbox-traffic restart >/dev/null 2>&1 \
      || rc-service sbox-traffic start >/dev/null 2>&1 || true
  fi
}

install_jq() {
  if [[ "$PLATFORM" == "alpine" ]]; then
    apk add --no-cache jq
  else
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      jq
  fi
}

purge_sing_box_package() {
  if [[ "$PLATFORM" == "alpine" ]]; then
    apk del sing-box >/dev/null 2>&1 || true
  else
    apt purge -y sing-box >/dev/null 2>&1 || true
  fi
}

cleanup_all_sing_box_configs() {
  if [[ -x "$MANAGER_NODE_BIN" ]]; then
    "$MANAGER_NODE_BIN" cleanup --purge >/dev/null 2>&1 || true
  fi
  disable_hy2_port_hopping
  service_disable
  rm -f "$WARP_CREDENTIALS_FILE"
  rm -rf \
    /etc/sing-box \
    /usr/local/etc/sing-box \
    /var/lib/sing-box \
    /var/log/sing-box \
    "$OUTPUT_DIR"
  rm -rf "$SBOX_STATE_DIR" "$CLIENTS_ROOT"
  rm -f "$TRAFFIC_SERVICE" "$TRAFFIC_TIMER" "$OPENRC_TRAFFIC_SCRIPT" \
    "$MANAGER_NODE_BIN" "$MANAGER_TRAFFIC_BIN"
  rm -f "$BBR_SYSCTL_CONF"
}

cleanup_all_sing_box_installations() {
  local detected_binary="$SING_BOX_BIN"
  cleanup_all_sing_box_configs
  purge_sing_box_package

  pkill -x sing-box >/dev/null 2>&1 || true
  rm -rf /opt/sing-box
  rm -f \
    /usr/bin/sing-box \
    /usr/local/bin/sing-box \
    /etc/init.d/sing-box \
    /etc/cron.d/sing-box \
    /etc/logrotate.d/sing-box \
    /etc/systemd/system/sing-box.service \
    /usr/lib/systemd/system/sing-box.service \
    /lib/systemd/system/sing-box.service

  case "$detected_binary" in
    /usr/bin/sing-box|/usr/local/bin/sing-box|/opt/sing-box/*)
      rm -f -- "$detected_binary"
      ;;
  esac

  if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed sing-box.service >/dev/null 2>&1 || true
  fi
  SING_BOX_BIN=""
}

usage() {
  cat << USAGE
用法：
  bash $0
  bash $0 --mode 1
  bash $0 --mode 1,2,3
  bash $0 --mode 2
  bash $0 --mode vless
  bash $0 anytls hy2 vless
  bash $0 --mode full
  bash $0 --restore
  bash $0 --setup [--tg-token TOKEN --tg-chat-id CHAT]
  bash $0 --uninstall anytls|vless|hy2|snell5|snell6|direct|all

安装模式：
  1, anytls     安装 AnyTLS + REALITY
  2, hy2        安装 Hysteria2 + Surge（可选端口跳跃）
  3, vless      安装 VLESS + REALITY
  4, snell5     安装 Snell v5
  5, snell6     安装 Snell v6
  6, full       同时安装全部五种协议
  7, uninstall  彻底卸载全部配置和 sing-box
  8, restore    恢复最新的配置备份
  9, direct     安装 Direct 固定目标中转

可自由多选协议，例如：--mode 1,2 或 --mode 1,2,3。
也支持中文逗号、空格分隔和协议名混用，例如：--mode anytls,hy2,vless。

重新安装选项（检测到现有配置时显示）：
      --config merge   增量合并本次协议到现有配置（默认）
      --config keep    保留现有服务端/客户端配置，仅更新 sing-box
      --config restore 从 /root/sbox-reality-backups 恢复最新配置
      --config new     生成全新配置，不合并已有入站

卸载选项：
      --uninstall      卸载范围：anytls、vless、hy2、snell5、snell6、direct 或 all
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
      --port-hopping  端口跳跃：on 或 off，默认：off
  -P, --ports         开启端口跳跃并指定范围，默认：20000-50000
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

Direct 固定目标中转选项：
      --direct-port        TCP/UDP 监听端口，默认：自动选择
      --direct-address     中转目标地址，必须指定
      --direct-target-port 中转目标端口，必须指定

WARP 分流选项：
      --warp-rules    MetaCubeX geosite 规则名，可用逗号或空格分隔
      --warp-off      关闭 WARP 分流并保留已注册凭据
      --warp-reset    重新注册 WARP 凭据；未指定规则时沿用现有列表

通用选项：
  -m, --mode          模式：1-9、anytls、vless、hy2、snell5、snell6、direct、full、uninstall、restore；协议可逗号多选
  -p, --port          当前单协议模式的端口；同时安装时请分别使用各协议端口选项
      --server-host   写入客户端配置的公网 IP 或域名；无法自动检测时必填
      --customer      一键创建多客户节点时使用的客户 ID
      --quota         客户节点每月流量额度，例如 100G
      --reset-day     客户节点月度流量重置日，1-28
      --expires       客户节点到期时间，YYYY-MM-DD 或 YYYY-MM-DD HH:MM:SS
      --tg-token      Telegram Bot Token（也可用 SBOX_TG_BOT_TOKEN）
      --tg-chat-id    Telegram Chat ID（也可用 SBOX_TG_CHAT_ID）
      --setup         首次安装节点管理器并配置 Telegram，不创建客户节点
  -h, --help          显示帮助

环境变量：
  INSTALL_MODE, CONFIG_POLICY, UNINSTALL_SCOPE, PORT,
  SERVER_HOST, CUSTOMER_ID, CUSTOMER_QUOTA, CUSTOMER_RESET_DAY, CUSTOMER_EXPIRES,
  SBOX_TG_BOT_TOKEN, SBOX_TG_CHAT_ID,
  REALITY_DOMAIN, DOMAIN, ANYTLS_PORT,
  VLESS_DOMAIN, VLESS_PORT, SNELL5_PORT, SNELL6_PORT,
  DIRECT_PORT, DIRECT_TARGET_ADDRESS, DIRECT_TARGET_PORT,
  SNELL5_OBFS_MODE, SNELL6_MODE,
  HIGH_PORT_MIN, HIGH_PORT_MAX,
  HY2_SNI, SNI, HY2_PORT, HY2_PORT_HOPPING, HOP_PORTS, HOP_INTERVAL,
  UP_MBPS, DOWN_MBPS, OBFS, OBFS_PASSWORD,
  GECKO_MIN_PACKET_SIZE, GECKO_MAX_PACKET_SIZE,
  CERT_PATH, KEY_PATH, PROXY_NAME
USAGE
}

append_install_mode() {
  local mode="$1"
  if [[ -z "$INSTALL_MODE" ]]; then
    INSTALL_MODE="$mode"
  else
    INSTALL_MODE="${INSTALL_MODE},${mode}"
  fi
}

warp_normalize_rules() {
  local raw token normalized json="" separator=""
  local -a items normalized_items=()
  local existing duplicate

  raw="$1"
  raw="${raw//，/,}"
  raw="${raw//、/,}"
  raw="${raw//;/,}"
  raw="${raw//$'\t'/,}"
  raw="${raw//$'\n'/,}"
  raw="${raw// /,}"

  IFS=',' read -r -a items <<< "$raw"
  for token in "${items[@]}"; do
    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"
    [[ -n "$token" ]] || continue

    normalized="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
    if [[ ! "$normalized" =~ ^[a-z0-9_-]+$ ]]; then
      echo "错误：无效的 WARP 规则名：$token" >&2
      return 1
    fi

    duplicate=0
    for existing in "${normalized_items[@]}"; do
      if [[ "$existing" == "$normalized" ]]; then
        duplicate=1
        break
      fi
    done
    (( duplicate )) || normalized_items+=("$normalized")
  done

  if (( ${#normalized_items[@]} == 0 )); then
    echo "错误：WARP 规则列表不能为空" >&2
    return 1
  fi

  for normalized in "${normalized_items[@]}"; do
    json="${json}${separator}\"${normalized}\""
    separator=","
  done
  printf '[%s]\n' "$json"
}

normalize_mode_input() {
  local raw="$1"

  raw="${raw//，/,}"
  raw="${raw//、/,}"
  raw="${raw//;/,}"
  raw="${raw// /,}"
  raw="${raw//$'\t'/,}"
  raw="${raw//$'\n'/,}"
  raw="${raw//$'\r'/,}"
  printf '%s\n' "$raw"
}

warp_validate_cli() {
  local has_warp_action=0 raw_mode mode_token
  local -a mode_items

  (( WARP_RULES_EXPLICIT || WARP_OFF || WARP_RESET )) && has_warp_action=1
  if (( WARP_OFF && (WARP_RULES_EXPLICIT || WARP_RESET) )); then
    echo "错误：--warp-off 不能与 --warp-rules 或 --warp-reset 同时使用" >&2
    return 1
  fi
  if (( has_warp_action )) && [[ "$ACTION" != "install" ]]; then
    echo "错误：WARP 参数不能与恢复或卸载操作同时使用" >&2
    return 1
  fi
  if (( has_warp_action )) && [[ -n "$INSTALL_MODE" ]]; then
    raw_mode="$(normalize_mode_input "$INSTALL_MODE")"
    IFS=',' read -r -a mode_items <<< "$raw_mode"
    for mode_token in "${mode_items[@]}"; do
      mode_token="$(printf '%s' "$mode_token" | tr '[:upper:]' '[:lower:]')"
      case "$mode_token" in
        7|uninstall|remove|8|restore|backup)
          echo "错误：WARP 参数不能与恢复或卸载模式同时使用" >&2
          return 1
          ;;
      esac
    done
  fi
  if (( WARP_OFF )) && [[ -n "$INSTALL_MODE" ]]; then
    echo "错误：--warp-off 是独立操作，不能与协议安装模式同时使用" >&2
    return 1
  fi
  if (( has_warp_action )) && [[ "$CONFIG_POLICY" == "keep" || "$CONFIG_POLICY" == "restore" ]]; then
    echo "错误：WARP 参数不能与 --config $CONFIG_POLICY 同时使用" >&2
    return 1
  fi

  if (( WARP_RULES_EXPLICIT )); then
    WARP_RULES_JSON="$(warp_normalize_rules "$WARP_RULES_INPUT")" || return 1
  fi

  if (( has_warp_action )) && [[ -z "$INSTALL_MODE" ]]; then
    ACTION="warp"
  fi
}

warp_decode_base64() {
  local value="$1"
  local destination="$2"

  if printf '%s' "$value" | base64 -d > "$destination" 2>/dev/null; then
    return 0
  fi
  printf '%s' "$value" | base64 -D > "$destination" 2>/dev/null
}

warp_validate_key() {
  local key="$1"
  local decoded

  [[ ${#key} -eq 44 ]] || return 1
  decoded="$(mktemp)"
  if ! warp_decode_base64 "$key" "$decoded" \
    || [[ "$(wc -c < "$decoded" | tr -d ' ')" != "32" ]]; then
    rm -f "$decoded"
    return 1
  fi
  rm -f "$decoded"
}

warp_validate_credentials() {
  local credential_file="$1"
  local private_key public_key

  [[ -s "$credential_file" ]] || return 1
  if ! jq -e '
    .schema == 1
    and (.private_key | type == "string")
    and (.public_key | type == "string")
    and (.address | type == "array" and length == 2)
    and (.address[0] | type == "string" and endswith("/32"))
    and (.address[1] | type == "string" and endswith("/128"))
    and (.reserved | type == "array" and length == 3)
    and all(.reserved[]; type == "number" and floor == . and . >= 0 and . <= 255)
    and .mtu == 1280
    and .peer.address == "engage.cloudflareclient.com"
    and .peer.port == 2408
    and .peer.public_key == "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
    and .peer.allowed_ips == ["0.0.0.0/0", "::/0"]
    and .peer.persistent_keepalive_interval == 30
  ' "$credential_file" >/dev/null 2>&1; then
    return 1
  fi

  private_key="$(jq -r '.private_key' "$credential_file")"
  public_key="$(jq -r '.public_key' "$credential_file")"
  warp_validate_key "$private_key" && warp_validate_key "$public_key"
}

warp_parse_registration_response() {
  local response_file="$1"
  local private_key="$2"
  local public_key="$3"
  local destination="$4"
  local v4 v6 client_id decoded reserved temporary

  warp_validate_key "$private_key" || {
    echo "错误：WARP X25519 私钥格式无效" >&2
    return 1
  }
  warp_validate_key "$public_key" || {
    echo "错误：WARP X25519 公钥格式无效" >&2
    return 1
  }

  v4="$(jq -er '.config.interface.addresses.v4 | select(type == "string" and length > 0)' "$response_file" 2>/dev/null)" || {
    echo "错误：Cloudflare 注册响应缺少 IPv4 地址" >&2
    return 1
  }
  v6="$(jq -er '.config.interface.addresses.v6 | select(type == "string" and length > 0)' "$response_file" 2>/dev/null)" || {
    echo "错误：Cloudflare 注册响应缺少 IPv6 地址" >&2
    return 1
  }
  client_id="$(jq -er '.config.client_id | select(type == "string" and length > 0)' "$response_file" 2>/dev/null)" || {
    echo "错误：Cloudflare 注册响应缺少 client_id" >&2
    return 1
  }

  decoded="$(mktemp)"
  if ! warp_decode_base64 "$client_id" "$decoded" \
    || [[ "$(wc -c < "$decoded" | tr -d ' ')" != "3" ]]; then
    rm -f "$decoded"
    echo "错误：Cloudflare client_id 必须解码为三个 reserved 字节" >&2
    return 1
  fi
  reserved="$(od -An -tu1 "$decoded" | awk 'NF {$1=$1; gsub(/ /,","); print "["$0"]"}')"
  rm -f "$decoded"

  temporary="$(mktemp "${destination}.tmp.XXXXXX")"
  if ! jq -n \
    --arg private_key "$private_key" \
    --arg public_key "$public_key" \
    --arg v4 "${v4%/*}/32" \
    --arg v6 "${v6%/*}/128" \
    --argjson reserved "$reserved" '
      {
        schema: 1,
        private_key: $private_key,
        public_key: $public_key,
        address: [$v4, $v6],
        reserved: $reserved,
        mtu: 1280,
        peer: {
          address: "engage.cloudflareclient.com",
          port: 2408,
          public_key: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          allowed_ips: ["0.0.0.0/0", "::/0"],
          persistent_keepalive_interval: 30
        }
      }
    ' > "$temporary"; then
    rm -f "$temporary"
    return 1
  fi

  if ! warp_validate_credentials "$temporary"; then
    rm -f "$temporary"
    echo "错误：生成的 WARP 凭据未通过校验" >&2
    return 1
  fi
  mv -f "$temporary" "$destination"
}

warp_generate_keypair() {
  local temporary private_pem private_der public_der private_key public_key

  temporary="$(mktemp -d)"
  private_pem="$temporary/private.pem"
  private_der="$temporary/private.der"
  public_der="$temporary/public.der"

  if ! openssl genpkey -algorithm X25519 -out "$private_pem" 2>/dev/null \
    || ! openssl pkey -in "$private_pem" -outform DER -out "$private_der" 2>/dev/null \
    || ! openssl pkey -in "$private_pem" -pubout -outform DER -out "$public_der" 2>/dev/null; then
    rm -rf "$temporary"
    echo "错误：当前 OpenSSL 无法生成 X25519 密钥" >&2
    return 1
  fi

  private_key="$(tail -c 32 "$private_der" | base64 | tr -d '\n')"
  public_key="$(tail -c 32 "$public_der" | base64 | tr -d '\n')"
  rm -rf "$temporary"

  warp_validate_key "$private_key" && warp_validate_key "$public_key" || return 1
  jq -nc --arg private_key "$private_key" --arg public_key "$public_key" \
    '{private_key: $private_key, public_key: $public_key}'
}

warp_post_registration() {
  local public_key="$1"
  local response_file="$2"
  local random_hex serial_number payload http_code

  random_hex="$(openssl rand -hex 16)"
  serial_number="${random_hex:0:8}-${random_hex:8:4}-${random_hex:12:4}-${random_hex:16:4}-${random_hex:20:12}"
  payload="$(jq -nc \
    --arg key "$public_key" \
    --arg tos "$(date -u +'%Y-%m-%dT%H:%M:%S.000Z')" \
    --arg serial "$serial_number" \
    '{key: $key, install_id: "", fcm_token: "", tos: $tos, model: "Linux", serial_number: $serial}')"

  if ! http_code="$(curl --silent --show-error --location \
    --connect-timeout 10 --max-time 30 --retry 2 --retry-delay 2 \
    --output "$response_file" --write-out '%{http_code}' \
    --request POST 'https://api.cloudflareclient.com/v0a2158/reg' \
    --header 'CF-Client-Version: a-6.11-2223' \
    --header 'Content-Type: application/json' \
    --data "$payload")"; then
    echo "错误：无法连接 Cloudflare WARP 注册接口" >&2
    return 1
  fi

  if [[ "$http_code" != 2* ]]; then
    echo "错误：Cloudflare WARP 注册失败（HTTP $http_code）" >&2
    return 1
  fi
}

warp_register_credentials() {
  local destination="$1"
  local temporary keypair response_file private_key public_key

  temporary="$(mktemp -d)"
  response_file="$temporary/response.json"
  if ! keypair="$(warp_generate_keypair)"; then
    rm -rf "$temporary"
    return 1
  fi
  private_key="$(jq -er '.private_key' <<< "$keypair")" || {
    rm -rf "$temporary"
    return 1
  }
  public_key="$(jq -er '.public_key' <<< "$keypair")" || {
    rm -rf "$temporary"
    return 1
  }

  if ! warp_post_registration "$public_key" "$response_file" \
    || ! warp_parse_registration_response \
      "$response_file" "$private_key" "$public_key" "$destination"; then
    rm -rf "$temporary"
    return 1
  fi
  rm -rf "$temporary"
}

warp_rule_url() {
  printf 'https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/%s.srs\n' "$1"
}

warp_probe_url() {
  curl -fsSIL --retry 2 --retry-delay 2 \
    --connect-timeout 10 --max-time 30 "$1" >/dev/null
}

warp_validate_rule_urls() {
  local rules_json="$1"
  local name url failed=0

  if ! jq -e 'type == "array" and length > 0 and all(.[]; type == "string")' \
    <<< "$rules_json" >/dev/null 2>&1; then
    echo "错误：WARP 规则列表不是有效的 JSON 数组" >&2
    return 1
  fi

  while IFS= read -r name; do
    url="$(warp_rule_url "$name")"
    if ! warp_probe_url "$url"; then
      echo "错误：MetaCubeX geosite 规则不存在或无法访问：$name" >&2
      failed=1
    fi
  done < <(jq -r '.[]' <<< "$rules_json")
  (( failed == 0 ))
}

warp_current_rules() {
  local config_file="$1"

  jq -c '
    [
      .route.rule_set[]?
      | select(
          .type == "remote"
          and .format == "binary"
          and (.http_client == {detour: "sbox-warp-direct"}
            or .download_detour == "sbox-warp-direct")
          and (.tag | type == "string" and test("^sbox-warp-geosite-[a-z0-9_-]+$"))
        )
      | (.tag | sub("^sbox-warp-geosite-"; "")) as $name
      | select(.url == ("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/" + $name + ".srs"))
      | $name
    ]
  ' "$config_file"
}

warp_validate_managed_ownership() {
  local config_file="$1"

  jq -e '
    def managed_rule_set_tag:
      type == "string" and test("^sbox-warp-geosite-[a-z0-9_-]+$");
    def valid_managed_route:
      .action == "route"
      and .outbound == "sbox-warp-out"
      and (.rule_set | type == "array" and length > 0 and all(.[]; managed_rule_set_tag))
      and ((keys | sort) == ["action", "outbound", "rule_set"]);
    def valid_managed_endpoint:
      .type == "wireguard"
      and .tag == "sbox-warp-out"
      and .mtu == 1280
      and (.address | type == "array" and length == 2)
      and (.address[0] | type == "string" and endswith("/32"))
      and (.address[1] | type == "string" and endswith("/128"))
      and (.private_key | type == "string" and length == 44)
      and (.peers | type == "array" and length == 1)
      and .peers[0].address == "engage.cloudflareclient.com"
      and .peers[0].port == 2408
      and .peers[0].public_key == "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
      and .peers[0].allowed_ips == ["0.0.0.0/0", "::/0"]
      and .peers[0].persistent_keepalive_interval == 30
      and (.peers[0].reserved | type == "array" and length == 3
        and all(.[]; type == "number" and floor == . and . >= 0 and . <= 255))
      and ((.peers[0] | keys | sort) == ["address", "allowed_ips", "persistent_keepalive_interval", "port", "public_key", "reserved"])
      and ((keys | sort) == ["address", "mtu", "peers", "private_key", "tag", "type"]);
    def valid_managed_rule_set:
      (.tag | sub("^sbox-warp-geosite-"; "")) as $name
      | .type == "remote"
        and .format == "binary"
        and (
          (.http_client == {detour: "sbox-warp-direct"}
            and ((keys | sort) == ["format", "http_client", "tag", "type", "url"]))
          or (.download_detour == "sbox-warp-direct"
            and ((keys | sort) == ["download_detour", "format", "tag", "type", "url"]))
        )
        and .url == ("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/" + $name + ".srs");

    ([.outbounds[]? | select(.tag == "sbox-warp-direct")] | length) <= 1
    and all(.outbounds[]? | select(.tag == "sbox-warp-direct");
      (. == {type: "direct", tag: "sbox-warp-direct"}
        or . == {type: "direct", tag: "sbox-warp-direct", connect_timeout: "15s"}))
    and ([.endpoints[]? | select(.tag == "sbox-warp-out")] | length) <= 1
    and all(.endpoints[]? | select(.tag == "sbox-warp-out"); valid_managed_endpoint)
    and all(.route.rule_set[]? | select((.tag // "") | startswith("sbox-warp-geosite-"));
      (.tag | managed_rule_set_tag) and valid_managed_rule_set)
    and ([.route.rules[]? | select(.outbound == "sbox-warp-out")] | length) <= 1
    and all(.route.rules[]? | select(.outbound == "sbox-warp-out"); valid_managed_route)
  ' "$config_file" >/dev/null 2>&1
}

warp_remove_config() {
  local input_file="$1"
  local output_file="$2"
  local temporary

  if ! jq -e . "$input_file" >/dev/null 2>&1; then
    echo "错误：无法从无效 JSON 中移除 WARP 配置" >&2
    return 1
  fi
  if ! warp_validate_managed_ownership "$input_file"; then
    echo "错误：现有配置占用了 sbox-warp 受管 tag，且结构无法识别" >&2
    return 1
  fi

  temporary="$(mktemp "${output_file}.tmp.XXXXXX")"
  if ! jq '
    def managed_route:
      .action == "route" and .outbound == "sbox-warp-out"
      and (.rule_set | type == "array" and length > 0
        and all(.[]; type == "string" and startswith("sbox-warp-geosite-")));
    .outbounds = [(.outbounds // [])[] | select((.tag // "") != "sbox-warp-direct")]
    | .endpoints = [(.endpoints // [])[] | select((.tag // "") != "sbox-warp-out")]
    | .route = (.route // {})
    | .route.rule_set = [(.route.rule_set // [])[]
        | select(((.tag // "") | startswith("sbox-warp-geosite-")) | not)]
    | (.route.rules // []) as $rules
    | .route.rules = [
        range(0; ($rules | length)) as $index
        | $rules[$index]
        | select(
            (managed_route | not)
            and (
              (. == {action: "sniff"})
              and ($index + 1 < ($rules | length))
              and ($rules[$index + 1] | managed_route)
            | not)
          )
      ]
  ' "$input_file" > "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  mv -f "$temporary" "$output_file"
}

warp_merge_config() {
  local input_file="$1"
  local credentials_file="$2"
  local rules_json="$3"
  local output_file="$4"
  local stripped temporary

  warp_validate_credentials "$credentials_file" || {
    echo "错误：WARP 凭据文件无效" >&2
    return 1
  }
  if ! jq -e 'type == "array" and length > 0 and all(.[]; type == "string" and test("^[a-z0-9_-]+$"))' \
    <<< "$rules_json" >/dev/null 2>&1; then
    echo "错误：WARP 规则列表无效" >&2
    return 1
  fi

  stripped="$(mktemp)"
  temporary="$(mktemp "${output_file}.tmp.XXXXXX")"
  if ! warp_remove_config "$input_file" "$stripped"; then
    rm -f "$stripped" "$temporary"
    return 1
  fi

  # An explicit timeout also makes the direct outbound a valid HTTP client detour.
  if ! jq --slurpfile credentials "$credentials_file" --argjson rules "$rules_json" '
    $credentials[0] as $credential
    | ($rules | map("sbox-warp-geosite-" + .)) as $rule_tags
    | .outbounds = ((.outbounds // []) + [{type: "direct", tag: "sbox-warp-direct", connect_timeout: "15s"}])
    | .endpoints = ((.endpoints // []) + [{
        type: "wireguard",
        tag: "sbox-warp-out",
        mtu: $credential.mtu,
        address: $credential.address,
        private_key: $credential.private_key,
        peers: [{
          address: $credential.peer.address,
          port: $credential.peer.port,
          public_key: $credential.peer.public_key,
          allowed_ips: $credential.peer.allowed_ips,
          persistent_keepalive_interval: $credential.peer.persistent_keepalive_interval,
          reserved: $credential.reserved
        }]
      }])
    | .route = (.route // {})
    | .route.rule_set = ((.route.rule_set // []) + [
        $rules[] as $name
        | {
            type: "remote",
            tag: ("sbox-warp-geosite-" + $name),
            format: "binary",
            url: ("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/" + $name + ".srs"),
            http_client: {detour: "sbox-warp-direct"}
          }
      ])
    | .route.rules = ([
        {action: "sniff"},
        {rule_set: $rule_tags, action: "route", outbound: "sbox-warp-out"}
      ] + (.route.rules // []))
  ' "$stripped" > "$temporary"; then
    rm -f "$stripped" "$temporary"
    return 1
  fi
  rm -f "$stripped"

  if ! jq -e . "$temporary" >/dev/null 2>&1; then
    rm -f "$temporary"
    return 1
  fi
  mv -f "$temporary" "$output_file"
}

warp_migrate_legacy_credentials() {
  local legacy_file
  legacy_file="$(dirname "$WARP_CREDENTIALS_FILE")/sbox-warp-credentials.json"

  [[ "$legacy_file" != "$WARP_CREDENTIALS_FILE" && -e "$legacy_file" ]] || return 0
  if [[ -e "$WARP_CREDENTIALS_FILE" ]]; then
    if ! cmp -s "$legacy_file" "$WARP_CREDENTIALS_FILE"; then
      echo "错误：新旧 WARP 凭据不同，请先手动确认后移走旧 JSON 凭据文件" >&2
      return 1
    fi
    chmod 600 "$WARP_CREDENTIALS_FILE" || return 1
    rm -f "$legacy_file" || return 1
  else
    chmod 600 "$legacy_file" || return 1
    mv "$legacy_file" "$WARP_CREDENTIALS_FILE" || return 1
  fi
  echo "已迁移 WARP 凭据，避免被 sing-box 当作配置加载。"
}

warp_prepare_credentials() {
  local staged_file="$1"

  if [[ -e "$WARP_CREDENTIALS_FILE" ]] && (( ! WARP_RESET )); then
    if ! warp_validate_credentials "$WARP_CREDENTIALS_FILE"; then
      echo "错误：现有 WARP 凭据无效；请使用 --warp-reset 重新注册" >&2
      return 1
    fi
    if ! cp "$WARP_CREDENTIALS_FILE" "$staged_file"; then
      echo "错误：无法暂存现有 WARP 凭据" >&2
      return 1
    fi
  else
    echo "正在向 Cloudflare 注册 WARP 凭据……"
    if ! warp_register_credentials "$staged_file"; then
      echo "错误：WARP 凭据注册失败" >&2
      rm -f "$staged_file"
      return 1
    fi
  fi

  if ! warp_validate_credentials "$staged_file"; then
    echo "错误：暂存的 WARP 凭据无效" >&2
    rm -f "$staged_file"
    return 1
  fi
  if ! chmod 600 "$staged_file"; then
    echo "错误：无法设置暂存 WARP 凭据权限" >&2
    rm -f "$staged_file"
    return 1
  fi
}

warp_restore_file() {
  local snapshot_file="$1"
  local destination="$2"
  local existed="$3"
  local temporary

  if (( existed )); then
    if [[ ! -f "$snapshot_file" ]]; then
      echo "错误：缺少 WARP 恢复快照：$snapshot_file" >&2
      return 1
    fi
    if ! temporary="$(mktemp "$(dirname "$destination")/.sbox-warp-restore.XXXXXX")"; then
      echo "错误：无法创建 WARP 恢复临时文件" >&2
      return 1
    fi
    if ! cp -p "$snapshot_file" "$temporary"; then
      rm -f "$temporary"
      echo "错误：无法复制 WARP 恢复快照" >&2
      return 1
    fi
    if ! chmod 600 "$temporary"; then
      rm -f "$temporary"
      echo "错误：无法设置 WARP 恢复文件权限" >&2
      return 1
    fi
    if ! mv -f "$temporary" "$destination"; then
      rm -f "$temporary"
      echo "错误：无法恢复 WARP 文件：$destination" >&2
      return 1
    fi
  else
    if ! rm -f "$destination"; then
      echo "错误：无法移除回滚前不存在的 WARP 文件：$destination" >&2
      return 1
    fi
  fi
}

warp_restore_snapshot_pair() {
  local snapshot_dir="$1"
  local config_existed="$2"
  local credentials_existed="$3"
  local failed=0

  warp_restore_file "$snapshot_dir/config.json" \
    "$SERVER_CONF" "$config_existed" || failed=1
  warp_restore_file "$snapshot_dir/credentials.json" \
    "$WARP_CREDENTIALS_FILE" "$credentials_existed" || failed=1
  (( failed == 0 ))
}

warp_commit_staged_files() {
  local staged_config="$1"
  local staged_credentials="${2:-}"
  local snapshot_dir config_existed=0 credentials_existed=0

  if ! snapshot_dir="$(mktemp -d "$(dirname "$SERVER_CONF")/.sbox-warp-snapshot.XXXXXX")"; then
    echo "错误：无法创建 WARP 快照目录" >&2
    return 1
  fi
  if [[ -e "$SERVER_CONF" ]]; then
    config_existed=1
    if ! cp -p "$SERVER_CONF" "$snapshot_dir/config.json"; then
      echo "错误：无法快照现有 sing-box 配置" >&2
      rm -rf "$snapshot_dir"
      return 1
    fi
  fi
  if [[ -e "$WARP_CREDENTIALS_FILE" ]]; then
    credentials_existed=1
    if ! cp -p "$WARP_CREDENTIALS_FILE" "$snapshot_dir/credentials.json"; then
      echo "错误：无法快照现有 WARP 凭据" >&2
      rm -rf "$snapshot_dir"
      return 1
    fi
  fi

  if ! backup_existing_files "before-warp-update"; then
    rm -rf "$snapshot_dir"
    return 1
  fi

  if ! chmod 600 "$staged_config"; then
    rm -rf "$snapshot_dir"
    return 1
  fi
  if [[ -n "$staged_credentials" ]] && ! chmod 600 "$staged_credentials"; then
    rm -rf "$snapshot_dir"
    return 1
  fi
  if ! mv -f "$staged_config" "$SERVER_CONF"; then
    rm -rf "$snapshot_dir"
    return 1
  fi
  if [[ -n "$staged_credentials" ]]; then
    if ! mv -f "$staged_credentials" "$WARP_CREDENTIALS_FILE"; then
      if warp_restore_snapshot_pair "$snapshot_dir" "$config_existed" "$credentials_existed"; then
        rm -rf "$snapshot_dir"
      else
        echo "错误：WARP 回滚不完整，恢复快照保留在 $snapshot_dir" >&2
      fi
      return 1
    fi
  fi

  if ! service_restart; then
    echo "错误：sing-box 重启失败，正在恢复 WARP 修改前的文件" >&2
    if warp_restore_snapshot_pair "$snapshot_dir" "$config_existed" "$credentials_existed"; then
      service_restart || true
      rm -rf "$snapshot_dir"
    else
      echo "错误：WARP 回滚不完整，恢复快照保留在 $snapshot_dir" >&2
    fi
    return 1
  fi

  rm -rf "$snapshot_dir"
}

warp_apply_existing() {
  local rules_json stage_dir staged_config staged_credentials

  if [[ ! -s "$SERVER_CONF" ]] || ! jq -e . "$SERVER_CONF" >/dev/null 2>&1; then
    echo "错误：独立配置 WARP 前需要有效的 $SERVER_CONF" >&2
    return 1
  fi

  if (( WARP_RULES_EXPLICIT )); then
    rules_json="$WARP_RULES_JSON"
  else
    rules_json="$(warp_current_rules "$SERVER_CONF")" || return 1
    if ! jq -e 'type == "array" and length > 0' <<< "$rules_json" >/dev/null 2>&1; then
      echo "错误：当前没有可沿用的 WARP 规则，请同时指定 --warp-rules" >&2
      return 1
    fi
  fi

  warp_validate_rule_urls "$rules_json" || return 1
  if ! stage_dir="$(mktemp -d "$(dirname "$SERVER_CONF")/.sbox-warp-stage.XXXXXX")"; then
    echo "错误：无法创建 WARP 暂存目录" >&2
    return 1
  fi
  staged_config="$stage_dir/config.json"
  staged_credentials="$stage_dir/credentials.json"

  if ! warp_prepare_credentials "$staged_credentials" \
    || ! warp_merge_config "$SERVER_CONF" "$staged_credentials" "$rules_json" "$staged_config"; then
    rm -rf "$stage_dir"
    return 1
  fi
  if ! run_sing_box check -c "$staged_config"; then
    echo "错误：WARP 配置未通过 sing-box 检查，现有文件保持不变" >&2
    rm -rf "$stage_dir"
    return 1
  fi
  if ! warp_commit_staged_files "$staged_config" "$staged_credentials"; then
    rm -rf "$stage_dir"
    return 1
  fi
  rm -rf "$stage_dir"
  echo "WARP 分流已更新：$(jq -r 'join(",")' <<< "$rules_json")"
}

warp_disable_existing() {
  local stage_dir staged_config

  if [[ ! -s "$SERVER_CONF" ]] || ! jq -e . "$SERVER_CONF" >/dev/null 2>&1; then
    echo "错误：关闭 WARP 前需要有效的 $SERVER_CONF" >&2
    return 1
  fi

  if ! stage_dir="$(mktemp -d "$(dirname "$SERVER_CONF")/.sbox-warp-stage.XXXXXX")"; then
    echo "错误：无法创建 WARP 暂存目录" >&2
    return 1
  fi
  staged_config="$stage_dir/config.json"
  if ! warp_remove_config "$SERVER_CONF" "$staged_config"; then
    rm -rf "$stage_dir"
    return 1
  fi
  if ! run_sing_box check -c "$staged_config"; then
    echo "错误：关闭 WARP 后的配置未通过 sing-box 检查" >&2
    rm -rf "$stage_dir"
    return 1
  fi
  if ! warp_commit_staged_files "$staged_config"; then
    rm -rf "$stage_dir"
    return 1
  fi
  rm -rf "$stage_dir"
  echo "WARP 分流已关闭；凭据已保留在 $WARP_CREDENTIALS_FILE"
}

warp_run_standalone() {
  warp_migrate_legacy_credentials || return 1
  if (( WARP_OFF )); then
    warp_disable_existing
  else
    warp_apply_existing
  fi
}

warp_prompt_rules() {
  local answer rules

  printf '是否启用 Cloudflare WARP 按规则分流？[y/N]：' >&2
  read -r answer
  case "$answer" in
    y|Y|yes|YES) ;;
    *) return 0 ;;
  esac

  printf '请输入 geosite 规则名（例如 youtube,netflix,openai）：' >&2
  read -r rules
  WARP_RULES_JSON="$(warp_normalize_rules "$rules")" || return 1
  WARP_RULES_INPUT="$rules"
  WARP_RULES_EXPLICIT=1
}

warp_prepare_install_state() {
  local rules_json

  (( WARP_RULES_EXPLICIT || WARP_RESET )) || return 0
  warp_migrate_legacy_credentials || return 1

  if (( WARP_RULES_EXPLICIT )); then
    rules_json="$WARP_RULES_JSON"
  elif [[ -s "$SERVER_CONF" ]]; then
    rules_json="$(warp_current_rules "$SERVER_CONF")" || return 1
  else
    rules_json="[]"
  fi
  if ! jq -e 'type == "array" and length > 0' <<< "$rules_json" >/dev/null 2>&1; then
    echo "错误：没有可用于安装的 WARP 规则，请指定 --warp-rules" >&2
    return 1
  fi
  warp_validate_rule_urls "$rules_json" || return 1
  backup_existing_files "before-warp-install" || return 1

  if ! mkdir -p "$(dirname "$SERVER_CONF")" \
    || ! chmod 700 "$(dirname "$SERVER_CONF")"; then
    echo "错误：无法准备安全的 sing-box 配置目录" >&2
    return 1
  fi
  if ! WARP_INSTALL_STAGE_DIR="$(mktemp -d "$(dirname "$SERVER_CONF")/.sbox-warp-install.XXXXXX")"; then
    echo "错误：无法创建 WARP 安装暂存目录" >&2
    WARP_INSTALL_STAGE_DIR=""
    return 1
  fi
  WARP_STAGED_CREDENTIALS="$WARP_INSTALL_STAGE_DIR/credentials.json"
  if ! warp_prepare_credentials "$WARP_STAGED_CREDENTIALS"; then
    rm -rf "$WARP_INSTALL_STAGE_DIR"
    WARP_INSTALL_STAGE_DIR=""
    WARP_STAGED_CREDENTIALS=""
    return 1
  fi
  WARP_INSTALL_RULES_JSON="$rules_json"
  WARP_INSTALL_ACTIVE=1
}

warp_begin_install_transaction() {
  local snapshot_dir

  (( WARP_INSTALL_ACTIVE )) || return 0

  WARP_INSTALL_CONFIG_EXISTED=0
  WARP_INSTALL_CREDENTIALS_EXISTED=0
  if ! snapshot_dir="$(mktemp -d "$(dirname "$SERVER_CONF")/.sbox-warp-install-snapshot.XXXXXX")"; then
    echo "错误：无法创建安装事务快照目录" >&2
    return 1
  fi
  WARP_INSTALL_SNAPSHOT_DIR="$snapshot_dir"
  if [[ -e "$SERVER_CONF" ]]; then
    WARP_INSTALL_CONFIG_EXISTED=1
    if ! cp -p "$SERVER_CONF" "$WARP_INSTALL_SNAPSHOT_DIR/config.json"; then
      echo "错误：无法快照安装前的 sing-box 配置" >&2
      rm -rf "$WARP_INSTALL_SNAPSHOT_DIR"
      WARP_INSTALL_SNAPSHOT_DIR=""
      return 1
    fi
  fi
  if [[ -e "$WARP_CREDENTIALS_FILE" ]]; then
    WARP_INSTALL_CREDENTIALS_EXISTED=1
    if ! cp -p "$WARP_CREDENTIALS_FILE" "$WARP_INSTALL_SNAPSHOT_DIR/credentials.json"; then
      echo "错误：无法快照安装前的 WARP 凭据" >&2
      rm -rf "$WARP_INSTALL_SNAPSHOT_DIR"
      WARP_INSTALL_SNAPSHOT_DIR=""
      return 1
    fi
  fi
}

warp_rollback_install_transaction() {
  (( WARP_INSTALL_ACTIVE )) || return 0
  [[ -n "$WARP_INSTALL_SNAPSHOT_DIR" && -d "$WARP_INSTALL_SNAPSHOT_DIR" ]] || return 0

  if ! warp_restore_snapshot_pair "$WARP_INSTALL_SNAPSHOT_DIR" \
    "$WARP_INSTALL_CONFIG_EXISTED" "$WARP_INSTALL_CREDENTIALS_EXISTED"; then
    echo "错误：安装回滚不完整，恢复快照保留在 $WARP_INSTALL_SNAPSHOT_DIR" >&2
    return 1
  fi
  if ! rm -rf "$WARP_INSTALL_SNAPSHOT_DIR" "$WARP_INSTALL_STAGE_DIR"; then
    echo "错误：无法清理已完成的安装事务文件" >&2
    return 1
  fi
  WARP_INSTALL_SNAPSHOT_DIR=""
  WARP_INSTALL_STAGE_DIR=""
}

warp_finalize_install_transaction() {
  (( WARP_INSTALL_ACTIVE )) || return 0
  if ! rm -rf "$WARP_INSTALL_SNAPSHOT_DIR" "$WARP_INSTALL_STAGE_DIR"; then
    echo "错误：无法清理 WARP 安装事务文件" >&2
    return 1
  fi
  WARP_INSTALL_SNAPSHOT_DIR=""
  WARP_INSTALL_STAGE_DIR=""
  WARP_STAGED_CREDENTIALS=""
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--mode|--install|--config|\
    --customer|--customer-id|--quota|--reset-day|--expires|\
    --tg-token|--tg-chat-id|\
    -d|--domain|--reality-domain|--anytls-port|--vless-domain|--vless-port|\
    --snell5-port|--snell6-port|--snell5-obfs|--snell6-mode|\
    --direct-port|--direct-address|--direct-target-port|--server-host|\
    -s|--sni|--hy2-sni|--hy2-port|-P|--ports|--port-hopping|\
    -i|--interval|--up|--down|--obfs-type|--obfs-password|\
    --gecko-min|--gecko-max|--cert|--key|--name|-p|--port)
      if (( $# < 2 )) || [[ -z "${2:-}" ]]; then
        echo "错误：选项 $1 缺少参数值" >&2
        exit 1
      fi
      ;;
  esac

  case "$1" in
    -m|--mode|--install)
      INSTALL_MODE="${2:-}"
      shift 2
      ;;
    --customer|--customer-id)
      CUSTOMER_ID="${2:-}"
      shift 2
      ;;
    --quota)
      CUSTOMER_QUOTA="${2:-}"
      shift 2
      ;;
    --reset-day)
      CUSTOMER_RESET_DAY="${2:-}"
      shift 2
      ;;
    --expires)
      CUSTOMER_EXPIRES="${2:-}"
      shift 2
      ;;
    --tg-token)
      TG_TOKEN="${2:-}"
      shift 2
      ;;
    --tg-chat-id)
      TG_CHAT_ID="${2:-}"
      shift 2
      ;;
    --setup|--init-manager)
      INIT_MANAGER=1
      shift
      ;;
    1|anytls|reality)
      append_install_mode "1"
      shift
      ;;
    2|hy2|hysteria2|surge)
      append_install_mode "2"
      shift
      ;;
    3|vless|vless-reality)
      append_install_mode "3"
      shift
      ;;
    4|snell5|snell-v5)
      append_install_mode "4"
      shift
      ;;
    5|snell6|snell-v6)
      append_install_mode "5"
      shift
      ;;
    9|direct|direct-udp|udp-forward)
      append_install_mode "9"
      shift
      ;;
    6|full|all|all5|all-protocols)
      append_install_mode "6"
      shift
      ;;
    7|uninstall|remove)
      append_install_mode "7"
      shift
      ;;
    8|restore|backup)
      append_install_mode "8"
      shift
      ;;
    --restore)
      ACTION="restore"
      ACTION_RESTORE_EXPLICIT=1
      CONFIG_POLICY="restore"
      shift
      ;;
    --uninstall)
      ACTION="uninstall"
      ACTION_UNINSTALL_EXPLICIT=1
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
    --direct-port)
      DIRECT_PORT="${2:-}"
      shift 2
      ;;
    --direct-address)
      DIRECT_TARGET_ADDRESS="${2:-}"
      shift 2
      ;;
    --direct-target-port)
      DIRECT_TARGET_PORT="${2:-}"
      shift 2
      ;;
    --server-host)
      SERVER_HOST="${2:-}"
      shift 2
      ;;
    --warp-rules)
      if (( $# < 2 )) || [[ -z "${2:-}" || "${2:-}" == -* ]]; then
        echo "错误：--warp-rules 缺少规则列表" >&2
        exit 1
      fi
      WARP_RULES_INPUT="$2"
      WARP_RULES_EXPLICIT=1
      shift 2
      ;;
    --warp-off)
      WARP_OFF=1
      shift
      ;;
    --warp-reset)
      WARP_RESET=1
      shift
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
      HY2_PORT_HOPPING="on"
      HY2_PORT_HOPPING_EXPLICIT=1
      HOP_PORTS_EXPLICIT=1
      shift 2
      ;;
    --port-hopping)
      HY2_PORT_HOPPING="${2:-}"
      HY2_PORT_HOPPING_EXPLICIT=1
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
      if [[ "$1" == *","* || "$1" == *"，"* || "$1" == *"、"* ]]; then
        append_install_mode "$1"
        shift
      else
        echo "未知选项：$1"
        usage
        exit 1
      fi
      ;;
  esac
done

if (( ACTION_RESTORE_EXPLICIT && ACTION_UNINSTALL_EXPLICIT )); then
  echo "错误：--restore 不能与 --uninstall 同时使用" >&2
  exit 1
fi
if [[ "$ACTION" != "install" && -n "$INSTALL_MODE" ]]; then
  echo "错误：--mode 不能与恢复或卸载参数同时使用" >&2
  exit 1
fi
if [[ "$ACTION" == "uninstall" && "$CONFIG_POLICY" != "ask" && "$CONFIG_POLICY" != "merge" ]]; then
  echo "错误：--config $CONFIG_POLICY 不能与 --uninstall 同时使用" >&2
  exit 1
fi
if [[ "$ACTION" == "restore" && "$CONFIG_POLICY" != "ask" && "$CONFIG_POLICY" != "restore" ]]; then
  echo "错误：--config $CONFIG_POLICY 不能与 --restore 同时使用" >&2
  exit 1
fi

warp_validate_cli || exit 1

choose_mode() {
  if [[ "$ACTION" != "install" || -n "$INSTALL_MODE" ]]; then
    return 0
  fi

  if [[ -t 0 ]]; then
    echo "请选择操作："
    echo "  1) 安装 AnyTLS + REALITY"
    echo "  2) 安装 Hysteria2 + Surge（可选端口跳跃）"
    echo "  3) 安装 VLESS + REALITY"
    echo "  4) 安装 Snell v5"
    echo "  5) 安装 Snell v6"
    echo "  6) 同时安装全部五种协议"
    echo "  7) 彻底卸载全部配置和 sing-box（保留备份）"
    echo "  8) 恢复最新备份"
    echo "  9) 安装 Direct 固定目标中转"
    echo
    echo "提示：可多选协议，例如 1,2 或 1,2,3"
    read -rp "请输入选项 [1-9]：" INSTALL_MODE
  else
    echo "错误：非交互模式下必须指定安装模式"
    echo "示例：bash $0 --mode 1,2,3"
    exit 1
  fi
}

normalize_mode() {
  local raw token normalized has_install=0 has_action=0
  local -a mode_items

  if [[ "$ACTION" != "install" ]]; then
    return 0
  fi

  raw="$(normalize_mode_input "${INSTALL_MODE:-}")"

  IFS=',' read -r -a mode_items <<< "$raw"
  for token in "${mode_items[@]}"; do
    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"
    [[ -n "$token" ]] || continue
    normalized="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"

    case "$normalized" in
      1|anytls|reality)
        INSTALL_ANYTLS=1
        has_install=1
        ;;
      2|hy2|hysteria2|surge)
        INSTALL_HY2=1
        has_install=1
        ;;
      3|vless|vless-reality)
        INSTALL_VLESS=1
        has_install=1
        ;;
      4|snell5|snell-v5)
        INSTALL_SNELL5=1
        has_install=1
        ;;
      5|snell6|snell-v6)
        INSTALL_SNELL6=1
        has_install=1
        ;;
      9|direct|direct-udp|udp-forward)
        INSTALL_DIRECT=1
        has_install=1
        ;;
      6|full|all|all5|all-protocols)
        INSTALL_ANYTLS=1
        INSTALL_VLESS=1
        INSTALL_HY2=1
        INSTALL_SNELL5=1
        INSTALL_SNELL6=1
        has_install=1
        ;;
      7|uninstall|remove)
        ACTION="uninstall"
        UNINSTALL_SCOPE="all"
        PURGE_SING_BOX=1
        has_action=1
        ;;
      8|restore|backup)
        ACTION="restore"
        CONFIG_POLICY="restore"
        has_action=1
        ;;
      *)
        echo "错误：无效的安装模式：$token"
        usage
        exit 1
        ;;
    esac
  done

  if (( has_install && has_action )); then
    echo "错误：安装协议不能和卸载/恢复选项同时选择：$INSTALL_MODE"
    exit 1
  fi

  if (( ! has_install && ! has_action )); then
      echo "错误：无效的安装模式：$INSTALL_MODE"
      usage
      exit 1
  fi
}

choose_protocol_port() {
  local label="$1"
  local variable_name="$2"
  local transport="$3"
  local current_value choice custom_port

  [[ -t 0 ]] || return 0
  current_value="${!variable_name}"
  if [[ -n "$current_value" && "$current_value" != "auto" && "$current_value" != "random" ]]; then
    return 0
  fi

  echo
  echo "$label 端口设置："
  echo "  1) 自动选择高端口（默认）"
  echo "  2) 自定义端口"
  read -rp "请选择 [1]：" choice
  choice="${choice:-1}"

  case "$choice" in
    1)
      printf -v "$variable_name" '%s' "auto"
      ;;
    2)
      while true; do
        read -rp "请输入 $label 端口 [1-65535]：" custom_port
        if validate_port "$custom_port"; then
          if [[ "$transport" == "udp" ]] && is_udp_port_in_use_by_other "$custom_port"; then
            echo "端口 $custom_port/UDP 已被占用，请使用其他端口"
            continue
          fi
          if [[ "$transport" == "tcp" ]] && is_tcp_port_in_use_by_other "$custom_port"; then
            echo "端口 $custom_port/TCP 已被占用，请使用其他端口"
            continue
          fi
          printf -v "$variable_name" '%s' "$custom_port"
          break
        fi
        echo "错误：端口必须是 1-65535 之间的整数"
      done
      ;;
    *)
      echo "错误：无效的端口选项：$choice"
      exit 1
      ;;
  esac
}

choose_hy2_port_hopping() {
  local choice range_choice start_port end_port

  (( INSTALL_HY2 )) || return 0
  [[ -t 0 ]] || return 0

  if (( ! HY2_PORT_HOPPING_EXPLICIT )); then
    echo
    echo "是否开启 Hysteria2 端口跳跃："
    echo "  1) 不开启（默认）"
    echo "  2) 开启"
    read -rp "请选择 [1]：" choice
    choice="${choice:-1}"
    case "$choice" in
      1) HY2_PORT_HOPPING="off" ;;
      2) HY2_PORT_HOPPING="on" ;;
      *) echo "错误：无效的端口跳跃选项：$choice"; exit 1 ;;
    esac
  fi

  [[ "$HY2_PORT_HOPPING" == "on" ]] || return 0
  (( HOP_PORTS_EXPLICIT )) && return 0

  echo
  echo "请选择端口跳跃区间："
  echo "  1) 默认区间 20000-50000"
  echo "  2) 自定义起始和结束端口"
  read -rp "请选择 [1]：" range_choice
  range_choice="${range_choice:-1}"

  case "$range_choice" in
    1)
      HOP_PORTS="20000-50000"
      ;;
    2)
      while true; do
        read -rp "请输入跳跃起始端口 [1-65535]：" start_port
        read -rp "请输入跳跃结束端口 [1-65535]：" end_port
        if validate_port "$start_port" && validate_port "$end_port" && (( start_port <= end_port )); then
          HOP_PORTS="${start_port}-${end_port}"
          break
        fi
        echo "错误：端口必须在 1-65535 之间，且起始端口不能大于结束端口"
      done
      ;;
    *)
      echo "错误：无效的跳跃区间选项：$range_choice"
      exit 1
      ;;
  esac
}

choose_install_ports() {
  [[ "$ACTION" == "install" ]] || return 0

  choose_hy2_port_hopping
  (( INSTALL_ANYTLS )) && choose_protocol_port "AnyTLS" "ANYTLS_PORT" "tcp"
  if (( INSTALL_HY2 )) && [[ "$HY2_PORT_HOPPING" != "on" ]]; then
    choose_protocol_port "Hysteria2" "HY2_PORT" "udp"
  fi
  (( INSTALL_VLESS )) && choose_protocol_port "VLESS" "VLESS_PORT" "tcp"
  (( INSTALL_SNELL5 )) && choose_protocol_port "Snell v5" "SNELL5_PORT" "tcp"
  (( INSTALL_SNELL6 )) && choose_protocol_port "Snell v6" "SNELL6_PORT" "tcp"
  (( INSTALL_DIRECT )) && choose_protocol_port "Direct 固定目标中转" "DIRECT_PORT" "udp"

  if (( INSTALL_DIRECT )) && [[ -t 0 ]]; then
    local input
    echo
    while [[ -z "$DIRECT_TARGET_ADDRESS" || ! "$DIRECT_TARGET_ADDRESS" =~ ^[A-Za-z0-9._:-]+$ ]]; do
      read -rp "请输入中转目标地址：" input
      DIRECT_TARGET_ADDRESS="$input"
      [[ -n "$DIRECT_TARGET_ADDRESS" && "$DIRECT_TARGET_ADDRESS" =~ ^[A-Za-z0-9._:-]+$ ]] \
        || echo "错误：请输入有效的 IP 地址或域名"
    done
    while ! validate_port "$DIRECT_TARGET_PORT"; do
      read -rp "请输入中转目标端口 [1-65535]：" input
      DIRECT_TARGET_PORT="$input"
      validate_port "$DIRECT_TARGET_PORT" || echo "错误：端口必须在 1-65535 之间"
    done
  fi
  return 0
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
      echo "  6) 仅 Direct 固定目标中转"
      echo "  7) 全部卸载"
      echo
      read -rp "请输入选项 [1-7]：" UNINSTALL_SCOPE
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
    6|direct|direct-udp|udp-forward)
      UNINSTALL_SCOPE="direct"
      ;;
    7|full|all)
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
  if (( INSTALL_DIRECT )); then
    DIRECT_PORT="$SHARED_PORT"
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

validate_hostname() {
  local hostname="$1"
  local label
  local -a labels

  (( ${#hostname} >= 1 && ${#hostname} <= 253 )) || return 1
  [[ "$hostname" != .* && "$hostname" != *. && "$hostname" != *..* ]] || return 1
  IFS='.' read -r -a labels <<< "$hostname"
  for label in "${labels[@]}"; do
    (( ${#label} >= 1 && ${#label} <= 63 )) || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
  done
}

validate_ipv4() {
  local address="$1"
  local octet
  local -a octets

  [[ "$address" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS='.' read -r -a octets <<< "$address"
  for octet in "${octets[@]}"; do
    (( 10#$octet <= 255 )) || return 1
  done
}

validate_ipv6() {
  local address="$1"
  local compressed=0 group
  local -a groups

  [[ "$address" == *:* && "$address" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "$address" != *":::"* ]] || return 1
  [[ "$address" == *::* ]] && compressed=1
  if (( compressed )); then
    [[ "$address" != *"::"*"::"* ]] || return 1
  fi

  address="${address#::}"
  address="${address%::}"
  if [[ -n "$address" ]]; then
    IFS=':' read -r -a groups <<< "$address"
    for group in "${groups[@]}"; do
      [[ -z "$group" && "$compressed" == "1" ]] && continue
      [[ "$group" =~ ^[0-9A-Fa-f]{1,4}$ ]] || return 1
    done
    if (( compressed )); then
      (( ${#groups[@]} < 8 )) || return 1
    else
      (( ${#groups[@]} == 8 )) || return 1
    fi
  elif (( ! compressed )); then
    return 1
  fi
}

validate_server_host() {
  local host="$1"
  host="${host#[}"
  host="${host%]}"
  validate_ipv4 "$host" || validate_ipv6 "$host" || validate_hostname "$host"
}

url_host() {
  local host="$1"
  if [[ "$host" == *:* ]]; then
    printf '[%s]' "$host"
  else
    printf '%s' "$host"
  fi
}

is_tcp_port_in_use() {
  local port="$1"
  ss -H -lntp 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {print}' | grep -q .
}

is_udp_port_in_use() {
  local port="$1"
  ss -H -lunp 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {print}' | grep -q .
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

pick_random_free_high_udp_port() {
  local candidate
  local range=$(( HIGH_PORT_MAX - HIGH_PORT_MIN + 1 ))

  if (( HIGH_PORT_MIN < 1024 || HIGH_PORT_MIN > HIGH_PORT_MAX || HIGH_PORT_MAX > 65535 )); then
    echo "错误：无效的高端口范围：${HIGH_PORT_MIN}-${HIGH_PORT_MAX}" >&2
    exit 1
  fi

  for _ in $(seq 1 100); do
    candidate=$(( HIGH_PORT_MIN + $(random_number) % range ))
    if ! is_udp_port_in_use "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  echo "错误：在 ${HIGH_PORT_MIN}-${HIGH_PORT_MAX} 范围内未找到可用的 UDP 高端口" >&2
  exit 1
}

pick_random_free_high_direct_port() {
  local candidate
  local range=$(( HIGH_PORT_MAX - HIGH_PORT_MIN + 1 ))

  if (( HIGH_PORT_MIN < 1024 || HIGH_PORT_MIN > HIGH_PORT_MAX || HIGH_PORT_MAX > 65535 )); then
    echo "错误：无效的高端口范围：${HIGH_PORT_MIN}-${HIGH_PORT_MAX}" >&2
    exit 1
  fi

  for _ in $(seq 1 100); do
    candidate=$(( HIGH_PORT_MIN + $(random_number) % range ))
    if ! is_tcp_port_in_use "$candidate" && ! is_udp_port_in_use "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  echo "错误：在 ${HIGH_PORT_MIN}-${HIGH_PORT_MAX} 范围内未找到 TCP/UDP 均可用的高端口" >&2
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

port_in_hop_specs() {
  local port="$1"
  local raw="$2"
  local spec start end
  local -a specs

  IFS=';' read -r -a specs <<< "$raw"
  for spec in "${specs[@]}"; do
    if [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      (( port >= start && port <= end )) && return 0
    elif [[ "$spec" == "$port" ]]; then
      return 0
    fi
  done
  return 1
}

json_escape() {
  local encoded
  encoded="$(jq -Rn --arg value "$1" '$value')" || return 1
  printf '%s' "${encoded:1:${#encoded}-2}"
}

build_server_ports_json() {
  local -a specs
  local spec sep json

  IFS=';' read -r -a specs <<< "$NORMALIZED_HOP_PORTS"
  sep=""
  json=""

  for spec in "${specs[@]}"; do
    if [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      spec="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    fi
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
        "password": "$(json_escape "$OBFS_PASSWORD")"$(if [[ "$GECKO_MIN_PACKET_SIZE" != "512" ]]; then printf ',\n        "min_packet_size": %s' "$GECKO_MIN_PACKET_SIZE"; fi)$(if [[ "$GECKO_MAX_PACKET_SIZE" != "1200" ]]; then printf ',\n        "max_packet_size": %s' "$GECKO_MAX_PACKET_SIZE"; fi)
      },
JSON
  else
    cat << JSON
      "obfs": {
        "type": "salamander",
        "password": "$(json_escape "$OBFS_PASSWORD")"
      },
JSON
  fi
}

json_hop_interval_field() {
  [[ "$HOP_INTERVAL" != "30" ]] || return 0
  printf '      "hop_interval": "%ss",\n' "$HOP_INTERVAL"
}

json_hy2_server_port_field() {
  if [[ "$NORMALIZED_HOP_PORTS" =~ ^[0-9]+$ ]]; then
    printf '      "server_port": %s,\n' "$NORMALIZED_HOP_PORTS"
  else
    printf '      "server_ports": %s,\n' "$SERVER_PORTS_JSON"
  fi
}

json_snell5_obfs_field() {
  [[ "$SNELL5_OBFS_MODE" != "none" ]] || return 0
  printf ',\n      "obfs_mode": "%s"' "$SNELL5_OBFS_MODE"
}

json_snell6_mode_field() {
  [[ "$SNELL6_MODE" != "default" ]] || return 0
  printf ',\n      "mode": "%s"' "$SNELL6_MODE"
}

surge_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/}"
  value="${value//$'\n'/}"
  printf '%s' "$value"
}

surge_obfs_param() {
  if [[ "$OBFS" == "gecko" ]]; then
    printf ',gecko-password="%s"' "$(surge_escape "$OBFS_PASSWORD")"
  elif [[ "$OBFS" == "salamander" ]]; then
    printf ',salamander-password="%s"' "$(surge_escape "$OBFS_PASSWORD")"
  fi
}

surge_extra_params() {
  local extra=""

  if [[ "$HY2_PORT_HOPPING" == "on" && "$HOP_INTERVAL" != "30" ]]; then
    extra="${extra},port-hopping-interval=${HOP_INTERVAL}"
  fi

  if [[ -n "$DOWN_MBPS" ]]; then
    extra="${extra},download-bandwidth=${DOWN_MBPS}"
  fi

  printf '%s' "$extra"
}

build_surge_proxy_line() {
  if [[ "$HY2_PORT_HOPPING" == "on" ]]; then
    printf '%s=hysteria2,%s,%s,password="%s",port-hopping="%s"%s,sni="%s",skip-cert-verify=true,tfo=false%s' \
      "$PROXY_NAME" "$SERVER_URL_HOST" "$HY2_PORT" "$HY2_PASSWORD" \
      "$NORMALIZED_HOP_PORTS" "$(surge_obfs_param)" "$HY2_SNI" "$(surge_extra_params)"
  else
    printf '%s=hysteria2,%s,%s,password="%s"%s,sni="%s",skip-cert-verify=true,tfo=false%s' \
      "$PROXY_NAME" "$SERVER_URL_HOST" "$HY2_PORT" "$HY2_PASSWORD" \
      "$(surge_obfs_param)" "$HY2_SNI" "$(surge_extra_params)"
  fi
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

  HY2_SHARE_URL="hysteria2://$(url_encode "$HY2_PASSWORD")@${SERVER_URL_HOST}:${uri_ports}/?${query}#$(url_encode "$PROXY_NAME")"
}

build_vless_share_url() {
  local query

  query="encryption=none&flow=xtls-rprx-vision&security=reality"
  query="${query}&sni=$(url_encode "$VLESS_DOMAIN")&fp=chrome"
  query="${query}&pbk=$(url_encode "$VLESS_PUBLIC_KEY")&sid=$(url_encode "$VLESS_SHORT_ID")"
  query="${query}&type=tcp&headerType=none"

  VLESS_SHARE_URL="vless://${VLESS_UUID}@${SERVER_URL_HOST}:${VLESS_PORT}?${query}#VLESS-Reality"
}

build_anytls_share_url() {
  local query
  query="security=reality&sni=$(url_encode "$REALITY_DOMAIN")&fp=chrome"
  query="${query}&pbk=$(url_encode "$ANYTLS_PUBLIC_KEY")&sid=$(url_encode "$ANYTLS_SHORT_ID")"
  ANYTLS_SHARE_URL="anytls://$(url_encode "$ANYTLS_PASSWORD")@${SERVER_URL_HOST}:${ANYTLS_PORT}?${query}#AnyTLS-Reality"
}

build_snell_share_urls() {
  if (( INSTALL_SNELL5 )); then
    SNELL5_SHARE_URL="snell://$(url_encode "$SNELL5_PSK")@${SERVER_URL_HOST}:${SNELL5_PORT}?version=5&obfs=${SNELL5_OBFS_MODE}&tfo=true&reuse=true#Snell-v5"
  fi
  if (( INSTALL_SNELL6 )); then
    SNELL6_SHARE_URL="snell://$(url_encode "$SNELL6_PSK")@${SERVER_URL_HOST}:${SNELL6_PORT}?version=6&mode=${SNELL6_MODE}&tfo=true&reuse=true#Snell-v6"
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

begin_install_transaction() {
  local path exists kind index snapshot_dir
  local -a paths=(
    "$SERVER_CONF"
    "$WARP_CREDENTIALS_FILE"
    "$PORT_ENV"
    "$PORT_HELPER"
    "$SYSTEMD_DROPIN"
    "$OPENRC_PORT_SERVICE"
    "$CERT_PATH"
    "$KEY_PATH"
    "$OUTPUT_DIR"
  )

  (( INSTALL_TRANSACTION_ACTIVE )) && return 0
  [[ -d "$(dirname "$SERVER_CONF")" ]] || mkdir -p "$(dirname "$SERVER_CONF")"
  snapshot_dir="$(mktemp -d "$(dirname "$SERVER_CONF")/.sbox-install-tx.XXXXXX")" || {
    echo "错误：无法创建安装事务快照目录" >&2
    return 1
  }
  mkdir -p "$snapshot_dir/data" || return 1

  INSTALL_SERVICE_WAS_ACTIVE=0
  INSTALL_SERVICE_WAS_ENABLED=0
  service_is_active && INSTALL_SERVICE_WAS_ACTIVE=1
  service_is_enabled && INSTALL_SERVICE_WAS_ENABLED=1

  for index in "${!paths[@]}"; do
    path="${paths[$index]}"
    printf '%s' "$path" > "$snapshot_dir/path.$index" || return 1
    exists=0
    if [[ -e "$path" || -L "$path" ]]; then
      exists=1
      if [[ -L "$path" ]]; then
        kind="symlink"
      elif [[ -d "$path" ]]; then
        kind="directory"
      else
        kind="file"
      fi
      cp -a -- "$path" "$snapshot_dir/data/$index" || return 1
    else
      kind="missing"
    fi
    printf '%s' "$exists" > "$snapshot_dir/existed.$index" || return 1
    printf '%s' "$kind" > "$snapshot_dir/kind.$index" || return 1
  done

  INSTALL_TRANSACTION_DIR="$snapshot_dir"
  INSTALL_TRANSACTION_ACTIVE=1
  trap 'install_transaction_on_exit' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
}

restore_install_transaction_entry() {
  local snapshot_dir="$1"
  local index="$2"
  local path existed kind

  path="$(cat "$snapshot_dir/path.$index")" || return 1
  existed="$(cat "$snapshot_dir/existed.$index")" || return 1
  kind="$(cat "$snapshot_dir/kind.$index")" || return 1
  [[ -n "$path" ]] || return 1

  if [[ -L "$path" || -f "$path" ]]; then
    rm -f -- "$path" || return 1
  elif [[ -d "$path" ]]; then
    rm -rf -- "$path" || return 1
  fi

  if [[ "$existed" == "1" ]]; then
    mkdir -p "$(dirname "$path")" || return 1
    cp -a -- "$snapshot_dir/data/$index" "$path" || return 1
  elif [[ "$kind" != "missing" ]]; then
    return 1
  fi
}

rollback_install_transaction() {
  local index

  (( INSTALL_TRANSACTION_ACTIVE )) || return 0
  [[ -n "$INSTALL_TRANSACTION_DIR" && -d "$INSTALL_TRANSACTION_DIR" ]] || return 1
  trap - EXIT INT TERM

  for index in {0..8}; do
    if ! restore_install_transaction_entry "$INSTALL_TRANSACTION_DIR" "$index"; then
      echo "错误：安装回滚不完整，恢复快照保留在 $INSTALL_TRANSACTION_DIR" >&2
      return 1
    fi
  done

  if ! rm -rf -- "$INSTALL_TRANSACTION_DIR"; then
    echo "错误：已恢复文件，但无法删除安装事务目录：$INSTALL_TRANSACTION_DIR" >&2
    return 1
  fi
  INSTALL_TRANSACTION_DIR=""
  INSTALL_TRANSACTION_ACTIVE=0
}

finalize_install_transaction() {
  (( INSTALL_TRANSACTION_ACTIVE )) || return 0
  trap - EXIT INT TERM
  if ! rm -rf -- "$INSTALL_TRANSACTION_DIR"; then
    echo "错误：无法清理安装事务目录：$INSTALL_TRANSACTION_DIR" >&2
    return 1
  fi
  INSTALL_TRANSACTION_DIR=""
  INSTALL_TRANSACTION_ACTIVE=0
}

install_transaction_on_exit() {
  local status="$?"
  trap - EXIT INT TERM
  if (( INSTALL_TRANSACTION_ACTIVE )); then
    echo "安装未完成，正在恢复安装前状态……" >&2
    if rollback_install_transaction; then
      service_reload || true
      restore_install_service_state
    fi
    if (( WARP_INSTALL_ACTIVE )); then
      warp_finalize_install_transaction || true
    fi
  fi
  exit "$status"
}

backup_existing_files() {
  local reason="$1"
  local backup_dir source copied=0
  local -a sources=(
    "$SERVER_CONF"
    "$WARP_CREDENTIALS_FILE"
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
    "$DIRECT_INFO"
    "$COMBINED_INFO"
    "$PORT_ENV"
    "$PORT_HELPER"
    "$SYSTEMD_DROPIN"
    "$OPENRC_PORT_SERVICE"
    "$DEFAULT_CERT_PATH"
    "$DEFAULT_KEY_PATH"
    "/etc/sing-box"
    "/usr/local/etc/sing-box"
    "/opt/sing-box"
    "$OUTPUT_DIR"
    "$NODES_FILE"
    "$TRAFFIC_STATE"
    "$NOTIFY_ENV"
    "$SERVER_HOST_FILE"
    "$CLIENTS_ROOT"
    "$TRAFFIC_SERVICE"
    "$TRAFFIC_TIMER"
    "$OPENRC_TRAFFIC_SCRIPT"
  )

  backup_dir="${BACKUP_ROOT}/${reason}-$(date +%Y%m%d-%H%M%S)-$$"
  if ! mkdir -p "$backup_dir" || ! chmod 700 "$BACKUP_ROOT" "$backup_dir"; then
    echo "错误：无法创建安全的备份目录：$backup_dir" >&2
    return 1
  fi
  if ! : > "$backup_dir/$BACKUP_MARKER" || ! chmod 600 "$backup_dir/$BACKUP_MARKER"; then
    echo "错误：无法写入备份目录安全标记：$backup_dir" >&2
    rmdir "$backup_dir" 2>/dev/null || true
    return 1
  fi

  for source in "${sources[@]}"; do
    if [[ -f "$source" ]]; then
      if ! cp -p "$source" "$backup_dir/$(basename "$source")"; then
        echo "错误：备份文件失败：$source" >&2
        rm -rf "$backup_dir"
        return 1
      fi
      copied=$(( copied + 1 ))
    elif [[ -d "$source" ]]; then
      local directory_name="external-${source#/}"
      directory_name="${directory_name//\//__}"
      if ! cp -a "$source" "$backup_dir/$directory_name"; then
        echo "错误：备份目录失败：$source" >&2
        rm -rf "$backup_dir"
        return 1
      fi
      copied=$(( copied + 1 ))
    fi
  done

  if (( copied == 0 )); then
    rm -f "$backup_dir/$BACKUP_MARKER"
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
  local candidate backup_root_real expected_root

  [[ -n "$keep_dir" && -d "$keep_dir" && -d "$BACKUP_ROOT" ]] || return 0
  backup_root_real="$(cd "$BACKUP_ROOT" && pwd -P)" || return 1
  expected_root="/root/sbox-reality-backups"

  if [[ "$backup_root_real" != "$expected_root" ]] \
    && [[ "${SBOX_REALITY_TEST_MODE:-0}" != "1" ]]; then
    echo "错误：拒绝清理非默认备份目录：$backup_root_real" >&2
    return 1
  fi

  for candidate in "$BACKUP_ROOT"/*; do
    [[ -d "$candidate" && ! -L "$candidate" && "$candidate" != "$keep_dir" ]] || continue
    [[ "$candidate" == "$BACKUP_ROOT"/* ]] || continue
    # Never delete directories that were not created by this installer.
    [[ -f "$candidate/$BACKUP_MARKER" ]] || continue
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
  local source

  source="${backup_dir}/$(basename "$destination")"

  # Old backups stored credentials with a JSON suffix, which -C would load.
  if [[ "$destination" == "$WARP_CREDENTIALS_FILE" && ! -f "$source" \
    && -f "$backup_dir/sbox-warp-credentials.json" ]]; then
    source="$backup_dir/sbox-warp-credentials.json"
  fi

  [[ -f "$source" ]] || return 0
  mkdir -p "$(dirname "$destination")"
  cp -p "$source" "$destination"
}

restore_directory_from_backup() {
  local backup_dir="$1"
  local destination="$2"
  local directory_name source

  directory_name="external-${destination#/}"
  directory_name="${directory_name//\//__}"
  source="${backup_dir}/${directory_name}"
  [[ -d "$source" ]] || return 0
  rm -rf -- "$destination"
  mkdir -p "$(dirname "$destination")"
  cp -a "$source" "$destination"
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
    "$WARP_CREDENTIALS_FILE"
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
    "$DIRECT_INFO"
    "$COMBINED_INFO"
    "$PORT_ENV"
    "$PORT_HELPER"
    "$SYSTEMD_DROPIN"
    "$OPENRC_PORT_SERVICE"
    "$DEFAULT_CERT_PATH"
    "$DEFAULT_KEY_PATH"
    "$NODES_FILE"
    "$TRAFFIC_STATE"
    "$NOTIFY_ENV"
    "$SERVER_HOST_FILE"
    "$TRAFFIC_SERVICE"
    "$TRAFFIC_TIMER"
    "$OPENRC_TRAFFIC_SCRIPT"
  )
  local destination

  [[ -n "$LATEST_BACKUP_DIR" ]] || {
    echo "错误：在 $BACKUP_ROOT 中未找到可恢复的配置"
    exit 1
  }
  backup_config="${LATEST_BACKUP_DIR}/$(basename "$SERVER_CONF")"

  echo "正在从以下位置恢复配置：$LATEST_BACKUP_DIR"
  echo "所选安装模式和新协议选项不会生效。"
  install_base_dependencies

  if ! jq -e . "$backup_config" >/dev/null; then
    echo "错误：备份配置不是有效的 JSON：$backup_config"
    exit 1
  fi
  validate_backup_tls_files "$LATEST_BACKUP_DIR" "$backup_config"

  if [[ -s "$SERVER_CONF" ]]; then
    backup_existing_files "before-restore"
  fi
  if ! begin_install_transaction; then
    echo "错误：无法建立恢复事务"
    exit 1
  fi
  install_sing_box
  install_manager_tool

  service_stop
  disable_hy2_port_hopping
  for destination in "${destinations[@]}"; do
    rm -f "$destination"
  done

  for destination in "${destinations[@]}"; do
    restore_file_from_backup "$LATEST_BACKUP_DIR" "$destination"
  done
  restore_directory_from_backup "$LATEST_BACKUP_DIR" "$CLIENTS_ROOT"
  restore_manager_services

  if [[ -f "$PORT_HELPER" ]]; then
    chmod +x "$PORT_HELPER"
  fi
  if [[ "$SERVICE_MANAGER" == "openrc" && -f "$OPENRC_PORT_SERVICE" ]]; then
    chmod +x "$OPENRC_PORT_SERVICE"
    rc-update add sing-box-hy2-port-hopping default >/dev/null 2>&1 || true
    rc-service sing-box-hy2-port-hopping restart >/dev/null 2>&1 \
      || rc-service sing-box-hy2-port-hopping start
  fi

  if ! run_sing_box check -c "$SERVER_CONF"; then
    echo "错误：文件已恢复，但未通过 sing-box 配置验证"
    echo "正在回滚到恢复前状态。备份位置：$LATEST_BACKUP_DIR"
    exit 1
  fi

  service_reload
  service_enable
  service_restart
  finalize_install_transaction

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
  install_manager_tool

  run_sing_box check -c "$SERVER_CONF"
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
    echo "将彻底移除 sing-box 软件包、常见二进制、服务、配置、日志和定时任务。"
    echo "备份目录 $BACKUP_ROOT 会保留。"
  elif [[ "$UNINSTALL_SCOPE" == "all" ]]; then
    echo "将删除全部 sing-box 配置和客户端文件，但保留 sing-box 程序。"
    echo "备份目录 $BACKUP_ROOT 会保留。"
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

remove_direct_files() {
  rm -f "$DIRECT_INFO"
}

remove_managed_nodes_for_scope() {
  local scope="$1" id
  [[ -x "$MANAGER_NODE_BIN" && -s "$NODES_FILE" ]] || return 0
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    "$MANAGER_NODE_BIN" node remove "$id" >/dev/null
  done < <(
    jq -r --arg scope "$scope" '
      .nodes[] |
      select(
        ($scope == "anytls" and .protocol == "anytls") or
        ($scope == "vless" and .protocol == "vless") or
        ($scope == "hy2" and .protocol == "hy2") or
        ($scope == "snell5" and .protocol == "snell5") or
        ($scope == "snell6" and .protocol == "snell6") or
        ($scope == "direct" and .protocol == "direct")
      ) | .id
    ' "$NODES_FILE"
  )
}

uninstall_selected() {
  local remove_anytls=false
  local remove_vless=false
  local remove_hy2=false
  local remove_snell5=false
  local remove_snell6=false
  local remove_direct=false
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
    direct)
      remove_direct=true
      ;;
    all)
      remove_anytls=true
      remove_vless=true
      remove_hy2=true
      remove_snell5=true
      remove_snell6=true
      remove_direct=true
      ;;
  esac

  confirm_uninstall

  backup_existing_files "uninstall-${UNINSTALL_SCOPE}"
  if [[ -n "$LAST_BACKUP_DIR" ]]; then
    prune_backups_except "$LAST_BACKUP_DIR"
    backup_status="$LAST_BACKUP_DIR"
  fi

  if [[ "$UNINSTALL_SCOPE" != "all" ]]; then
    remove_managed_nodes_for_scope "$UNINSTALL_SCOPE"
  fi

  if [[ -s "$SERVER_CONF" ]]; then
    if ! command -v jq >/dev/null 2>&1; then
      echo "正在安装 jq，以安全编辑 JSON 配置……"
      install_jq
    fi

    if [[ "$UNINSTALL_SCOPE" == "all" ]]; then
      if jq -e . "$SERVER_CONF" >/dev/null 2>&1; then
        matched="$(jq '(.inbounds // []) | length' "$SERVER_CONF")"
      fi
      service_disable
      rm -f "$SERVER_CONF"
    elif ! jq -e . "$SERVER_CONF" >/dev/null; then
      echo "错误：$SERVER_CONF 不是有效的 JSON，服务端配置未作更改"
      exit 1
    else
      matched="$(jq --argjson remove_anytls "$remove_anytls" --argjson remove_vless "$remove_vless" --argjson remove_hy2 "$remove_hy2" --argjson remove_snell5 "$remove_snell5" --argjson remove_snell6 "$remove_snell6" --argjson remove_direct "$remove_direct" '
        [(.inbounds // [])[]
          | select(
              (($remove_anytls == true) and (.tag == "anytls-in"))
              or (($remove_vless == true) and (.tag == "vless-in"))
              or (($remove_hy2 == true) and (.tag == "hy2-in"))
              or (($remove_snell5 == true) and (.tag == "snell5-in"))
              or (($remove_snell6 == true) and (.tag == "snell6-in"))
              or (($remove_direct == true) and (.tag == "direct-in"))
            )
        ] | length
      ' "$SERVER_CONF")"

      if (( matched > 0 )); then
        temp_config="$(mktemp)"
        jq --argjson remove_anytls "$remove_anytls" --argjson remove_vless "$remove_vless" --argjson remove_hy2 "$remove_hy2" --argjson remove_snell5 "$remove_snell5" --argjson remove_snell6 "$remove_snell6" --argjson remove_direct "$remove_direct" '
          .inbounds = [
            (.inbounds // [])[]
            | select(
                (($remove_anytls == false) or (.tag != "anytls-in"))
                and (($remove_vless == false) or (.tag != "vless-in"))
                and (($remove_hy2 == false) or (.tag != "hy2-in"))
                and (($remove_snell5 == false) or (.tag != "snell5-in"))
                and (($remove_snell6 == false) or (.tag != "snell6-in"))
                and (($remove_direct == false) or (.tag != "direct-in"))
              )
          ]
        ' "$SERVER_CONF" > "$temp_config"
        remaining="$(jq '(.inbounds // []) | length' "$temp_config")"

        if (( remaining > 0 )); then
          run_sing_box check -c "$temp_config"
          install -m 600 "$temp_config" "$SERVER_CONF"
        else
          service_disable
          rm -f "$SERVER_CONF"
        fi
        rm -f "$temp_config"
      fi
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
  if [[ "$remove_direct" == true ]]; then
    remove_direct_files
  fi
  rm -f "$COMBINED_INFO"

  service_reload

  if (( matched > 0 && remaining > 0 )); then
    service_enable
    service_restart
  fi

  if [[ "$UNINSTALL_SCOPE" == "all" ]]; then
    if (( PURGE_SING_BOX )); then
      cleanup_all_sing_box_installations
    else
      cleanup_all_sing_box_configs
    fi
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

is_selected_inbound_tag() {
  case "$1" in
    anytls-in) (( INSTALL_ANYTLS )) ;;
    vless-in) (( INSTALL_VLESS )) ;;
    hy2-in) (( INSTALL_HY2 )) ;;
    snell5-in) (( INSTALL_SNELL5 )) ;;
    snell6-in) (( INSTALL_SNELL6 )) ;;
    direct-in) (( INSTALL_DIRECT )) ;;
    *) return 1 ;;
  esac
}

inbound_transports() {
  local type="$1"
  local network="$2"

  case "$network" in
    tcp) printf 'tcp' ;;
    udp) printf 'udp' ;;
    tcp,udp|udp,tcp) printf 'tcp udp' ;;
    *)
      case "$type" in
        anytls|vless|vmess|trojan|snell|http)
          printf 'tcp'
          ;;
        hysteria2|tuic)
          printf 'udp'
          ;;
        *)
          # Unknown inbound types are treated conservatively.
          printf 'tcp udp'
          ;;
      esac
      ;;
  esac
}

validate_planned_port_against_existing_config() {
  local transport="$1"
  local port="$2"
  local label="$3"
  local tag type network existing_port transports
  local -A existing_tcp=()
  local -A existing_udp=()

  [[ "$CONFIG_POLICY" == "merge" && -s "$SERVER_CONF" ]] || return 0

  while IFS=$'\x1f' read -r tag type network existing_port; do
    [[ "$existing_port" =~ ^[0-9]+$ ]] || continue
    is_selected_inbound_tag "$tag" && continue
    transports="$(inbound_transports "$type" "$network")"
    if [[ " $transports " == *" tcp "* ]]; then
      existing_tcp["$existing_port"]+="${tag:-unnamed} "
    fi
    if [[ " $transports " == *" udp "* ]]; then
      existing_udp["$existing_port"]+="${tag:-unnamed} "
    fi
  done < <(
    jq -r '
      .inbounds[]?
      | select(.listen_port != null)
      | [
          (.tag // ""),
          (.type // ""),
          (.network // ""),
          (.listen_port | tostring)
        ]
      | join("\u001f")
    ' "$SERVER_CONF"
  )

  case "$transport" in
    tcp)
      if [[ -n "${existing_tcp[$port]:-}" ]]; then
        echo "错误：$label 端口 $port/TCP 已被现有入站占用：${existing_tcp[$port]}" >&2
        return 1
      fi
      ;;
    udp)
      if [[ -n "${existing_udp[$port]:-}" ]]; then
        echo "错误：$label 端口 $port/UDP 已被现有入站占用：${existing_udp[$port]}" >&2
        return 1
      fi
      ;;
    both)
      if [[ -n "${existing_tcp[$port]:-}" || -n "${existing_udp[$port]:-}" ]]; then
        echo "错误：$label 端口 $port 已被现有入站占用：${existing_tcp[$port]:-}${existing_udp[$port]:-}" >&2
        return 1
      fi
      ;;
  esac
}

validate_udp_range_against_existing_config() {
  local raw="$1"
  local label="$2"
  local spec start end port
  local -a specs
  local -A existing_udp=()
  local tag type network listen_port transports

  [[ "$CONFIG_POLICY" == "merge" && -s "$SERVER_CONF" ]] || return 0

  while IFS=$'\x1f' read -r tag type network listen_port; do
    [[ "$listen_port" =~ ^[0-9]+$ ]] || continue
    is_selected_inbound_tag "$tag" && continue
    transports="$(inbound_transports "$type" "$network")"
    if [[ " $transports " == *" udp "* ]]; then
      existing_udp["$listen_port"]="${tag:-unnamed}"
    fi
  done < <(
    jq -r '
      .inbounds[]?
      | select(.listen_port != null)
      | [(.tag // ""), (.type // ""), (.network // ""), (.listen_port | tostring)]
      | join("\u001f")
    ' "$SERVER_CONF"
  )

  IFS=';' read -r -a specs <<< "$raw"
  for spec in "${specs[@]}"; do
    if [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      for port in "${!existing_udp[@]}"; do
        if (( port >= start && port <= end )); then
          echo "错误：$label 端口跳跃范围 $spec 包含现有入站 ${existing_udp[$port]} 的 UDP 端口 $port" >&2
          return 1
        fi
      done
    else
      if [[ -n "${existing_udp[$spec]:-}" ]]; then
        echo "错误：$label 端口 $spec/UDP 已被现有入站 ${existing_udp[$spec]} 占用" >&2
        return 1
      fi
    fi
  done
}

validate_planned_ports_against_existing_config() {
  (( INSTALL_ANYTLS )) && validate_planned_port_against_existing_config tcp "$ANYTLS_PORT" "AnyTLS"
  (( INSTALL_VLESS )) && validate_planned_port_against_existing_config tcp "$VLESS_PORT" "VLESS"
  (( INSTALL_SNELL5 )) && validate_planned_port_against_existing_config tcp "$SNELL5_PORT" "Snell v5"
  (( INSTALL_SNELL6 )) && validate_planned_port_against_existing_config tcp "$SNELL6_PORT" "Snell v6"
  (( INSTALL_HY2 )) && validate_planned_port_against_existing_config udp "$HY2_PORT" "Hysteria2"
  (( INSTALL_DIRECT )) && validate_planned_port_against_existing_config both "$DIRECT_PORT" "Direct"
  if (( INSTALL_HY2 )) && [[ "$HY2_PORT_HOPPING" == "on" ]]; then
    validate_udp_range_against_existing_config "$NORMALIZED_HOP_PORTS" "Hysteria2"
  fi
}

prepare_inputs() {
  ensure_port_tools || exit 1
  REALITY_DOMAIN="$(strip_host "$REALITY_DOMAIN")"
  VLESS_DOMAIN="$(strip_host "$VLESS_DOMAIN")"
  HY2_SNI="$(strip_host "$HY2_SNI")"

  if (( INSTALL_ANYTLS )); then
    if ! validate_hostname "$REALITY_DOMAIN"; then
      echo "错误：REALITY 域名格式无效：$REALITY_DOMAIN"
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
    if ! validate_hostname "$VLESS_DOMAIN"; then
      echo "错误：VLESS REALITY 域名格式无效：$VLESS_DOMAIN"
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

    case "$HY2_PORT_HOPPING" in
      on|true|1) HY2_PORT_HOPPING="on" ;;
      off|false|0) HY2_PORT_HOPPING="off" ;;
      *) echo "错误：--port-hopping 只能是 on 或 off"; exit 1 ;;
    esac

    if ! validate_hostname "$HY2_SNI"; then
      echo "错误：Hysteria2 SNI 格式无效：$HY2_SNI"
      exit 1
    fi

    if [[ "$HY2_PORT_HOPPING" == "on" ]]; then
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
    elif [[ -z "$HY2_PORT" || "$HY2_PORT" == "auto" || "$HY2_PORT" == "random" ]]; then
      HY2_PORT="$(pick_random_free_high_udp_port)"
      HY2_PORT_MODE="自动随机"
    elif validate_port "$HY2_PORT"; then
      HY2_PORT_MODE="手动指定"
    else
      echo "错误：无效的 Hysteria2 监听端口：$HY2_PORT"
      exit 1
    fi

    if [[ "$HY2_PORT_HOPPING" == "off" ]]; then
      HOP_PORTS="$HY2_PORT"
      normalize_hop_ports
      build_server_ports_json
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
    if [[ "$OBFS_PASSWORD" == *$'\n'* || "$OBFS_PASSWORD" == *$'\r'* ]]; then
      echo "错误：混淆密码不能包含换行符"
      exit 1
    fi
    if [[ "$CERT_PATH" == *$'\n'* || "$CERT_PATH" == *$'\r'* \
      || "$KEY_PATH" == *$'\n'* || "$KEY_PATH" == *$'\r'* ]]; then
      echo "错误：证书和私钥路径不能包含换行符"
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

  if (( INSTALL_DIRECT )); then
    DIRECT_TARGET_ADDRESS="$(strip_host "$DIRECT_TARGET_ADDRESS")"
    if [[ -z "$DIRECT_TARGET_ADDRESS" || ! "$DIRECT_TARGET_ADDRESS" =~ ^[A-Za-z0-9._:-]+$ ]]; then
      echo "错误：必须通过交互输入或 --direct-address 指定有效的中转目标地址"
      exit 1
    fi
    if ! validate_port "$DIRECT_TARGET_PORT"; then
      echo "错误：必须通过交互输入或 --direct-target-port 指定 1-65535 的中转目标端口"
      exit 1
    fi

    if [[ -z "$DIRECT_PORT" || "$DIRECT_PORT" == "auto" || "$DIRECT_PORT" == "random" ]]; then
      DIRECT_PORT="$(pick_random_free_high_direct_port)"
      while { (( INSTALL_HY2 )) && port_in_hop_specs "$DIRECT_PORT" "$NORMALIZED_HOP_PORTS"; } \
        || { (( INSTALL_ANYTLS )) && [[ "$DIRECT_PORT" == "$ANYTLS_PORT" ]]; } \
        || { (( INSTALL_VLESS )) && [[ "$DIRECT_PORT" == "$VLESS_PORT" ]]; } \
        || { (( INSTALL_SNELL5 )) && [[ "$DIRECT_PORT" == "$SNELL5_PORT" ]]; } \
        || { (( INSTALL_SNELL6 )) && [[ "$DIRECT_PORT" == "$SNELL6_PORT" ]]; }; do
        DIRECT_PORT="$(pick_random_free_high_direct_port)"
      done
      DIRECT_PORT_MODE="自动随机"
    elif validate_port "$DIRECT_PORT"; then
      DIRECT_PORT_MODE="手动指定"
    else
      echo "错误：无效的 Direct 监听端口：$DIRECT_PORT"
      exit 1
    fi

    if { (( INSTALL_HY2 )) && port_in_hop_specs "$DIRECT_PORT" "$NORMALIZED_HOP_PORTS"; } \
      || { (( INSTALL_ANYTLS )) && [[ "$DIRECT_PORT" == "$ANYTLS_PORT" ]]; } \
      || { (( INSTALL_VLESS )) && [[ "$DIRECT_PORT" == "$VLESS_PORT" ]]; } \
      || { (( INSTALL_SNELL5 )) && [[ "$DIRECT_PORT" == "$SNELL5_PORT" ]]; } \
      || { (( INSTALL_SNELL6 )) && [[ "$DIRECT_PORT" == "$SNELL6_PORT" ]]; }; then
      echo "错误：Direct 监听端口与本次安装的其他入站端口重复：$DIRECT_PORT"
      exit 1
    fi
    if is_tcp_port_in_use_by_other "$DIRECT_PORT"; then
      echo "错误：TCP 端口 $DIRECT_PORT 已被其他进程占用"
      ss -H -lntp 2>/dev/null | awk -v p="$DIRECT_PORT" '$4 ~ ":" p "$" {print}' || true
      exit 1
    fi
    if is_udp_port_in_use_by_other "$DIRECT_PORT"; then
      echo "错误：UDP 端口 $DIRECT_PORT 已被其他进程占用"
      ss -H -lunp 2>/dev/null | awk -v p="$DIRECT_PORT" '$4 ~ ":" p "$" {print}' || true
      exit 1
    fi
  fi

  validate_planned_ports_against_existing_config
  detect_server_ip
}

fetch_preferred_sing_box_version() {
  local url payload version
  local -a sources=(
    "https://api.github.com/repos/SagerNet/sing-box/releases?per_page=100"
    "https://api.github.com/repos/SagerNet/sing-box/tags?per_page=100"
    "https://data.jsdelivr.com/v1/package/gh/SagerNet/sing-box"
  )

  if command -v git >/dev/null 2>&1; then
    version="$(git ls-remote --tags https://github.com/SagerNet/sing-box.git 'v*-alpha.*' \
      | awk '{ sub(/^refs\/tags\/v/, "", $2); print $2 }' \
      | awk '/^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$/' \
      | sort -V | tail -n 1)"
    if [[ -n "$version" ]]; then
      printf '%s' "$version"
      return 0
    fi
  fi

  for url in "${sources[@]}"; do
    if payload="$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      --connect-timeout 10 --max-time 60 "$url")"; then
      # Only consider version tags; release descriptions may mention old versions.
      version="$(printf '%s' "$payload" | jq -r '
        if type == "array" then
          .[] | select(.draft != true) | (.tag_name // .name // empty)
        else
          .versions[]?
        end
      ' | sed 's/^v//' | awk '
        /^[0-9]+\.[0-9]+\.[0-9]+-alpha\.[0-9]+$/ { print }
      ' | sort -V | tail -n 1)"
      if [[ -n "$version" ]]; then
        printf '%s' "$version"
        return 0
      fi
    fi
    echo "警告：版本源暂时不可用，正在尝试备用源：$url" >&2
  done

  return 1
}

sing_box_alpine_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64)
      printf '%s' "amd64"
      ;;
    aarch64|arm64)
      printf '%s' "arm64"
      ;;
    armv7l|armv7)
      printf '%s' "armv7"
      ;;
    *)
      echo "错误：暂不支持当前 Alpine 架构：$arch" >&2
      return 1
      ;;
  esac
}

fetch_sing_box_alpine_url() {
  local version="$1"
  local arch="$2"

  printf 'https://github.com/SagerNet/sing-box/releases/download/v%s/sing-box-%s-linux-%s-musl.tar.gz' \
    "$version" "$version" "$arch"
}

fetch_release_asset_sha256() {
  local version="$1"
  local asset_name="$2"
  local payload digest=""

  if payload="$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
    --connect-timeout 10 --max-time 60 \
    "https://github.com/SagerNet/sing-box/releases/expanded_assets/v${version}")"; then
    digest="$(printf '%s' "$payload" | awk -v asset="$asset_name" '
      index($0, ">" asset "<") { found = 1 }
      found && !printed && match($0, /sha256:[0-9a-fA-F]+/) {
        print substr($0, RSTART + 7, RLENGTH - 7)
        printed = 1
      }
    ')"
  fi

  if [[ ! "$digest" =~ ^[0-9a-fA-F]{64}$ ]] \
    && payload="$(curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      --connect-timeout 10 --max-time 60 \
      "https://api.github.com/repos/SagerNet/sing-box/releases/tags/v${version}" 2>/dev/null)"; then
    digest="$(printf '%s' "$payload" | jq -r --arg name "$asset_name" '
      first(.assets[]? | select(.name == $name) | (.digest // empty)) // empty
    ' | sed -n 's/^sha256:\([0-9a-fA-F]\{64\}\)$/\1/p')"
  fi

  if [[ ! "$digest" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "错误：无法获取发布文件的 SHA-256：$asset_name" >&2
    return 1
  fi
  printf '%s' "${digest,,}"
}

download_verified_release_asset() {
  local version="$1"
  local asset_name="$2"
  local destination="$3"
  local expected url

  expected="$(fetch_release_asset_sha256 "$version" "$asset_name")" || return 1
  url="https://github.com/SagerNet/sing-box/releases/download/v${version}/${asset_name}"
  echo "Downloading ${url}"
  curl -fL --retry 3 --retry-delay 2 --retry-all-errors \
    --connect-timeout 10 --max-time 120 \
    -o "$destination" "$url" || return 1
  printf '%s  %s\n' "$expected" "$destination" | sha256sum -c - >/dev/null || {
    echo "错误：发布文件 SHA-256 校验失败：$asset_name" >&2
    return 1
  }
}

install_sing_box_debian() {
  local version="$1"
  local arch asset_name tmpdir package_path real_dpkg

  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|arm64|armel|armhf|i386|loongarch64|mips64el|mipsel|ppc64el|riscv64|s390x)
      ;;
    *)
      echo "错误：暂不支持当前 Debian/Ubuntu 架构：$arch" >&2
      return 1
      ;;
  esac

  asset_name="sing-box_${version}_linux_${arch}.deb"
  tmpdir="$(mktemp -d)"
  package_path="${tmpdir}/${asset_name}"
  if ! download_verified_release_asset "$version" "$asset_name" "$package_path"; then
    rm -rf -- "$tmpdir"
    return 1
  fi

  real_dpkg="$(command -v dpkg)"
  if ! DEBIAN_FRONTEND=noninteractive "$real_dpkg" \
    --force-confdef --force-confold -i "$package_path"; then
    rm -rf -- "$tmpdir"
    return 1
  fi
  rm -rf -- "$tmpdir"
}

install_sing_box_openrc_service() {
  mkdir -p /etc/sing-box /run/sing-box /var/log/sing-box

  cat > /etc/init.d/sing-box << 'OPENRC'
#!/sbin/openrc-run

name="sing-box"
description="sing-box service"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background="yes"
pidfile="/run/sing-box/sing-box.pid"
output_log="/var/log/sing-box/sing-box.log"
error_log="/var/log/sing-box/sing-box.log"

depend() {
  need net
  after firewall
}

start_pre() {
  checkpath --directory --mode 0755 /run/sing-box
  checkpath --directory --mode 0755 /var/log/sing-box
}
OPENRC

  chmod 0755 /etc/init.d/sing-box
}

install_sing_box_alpine() {
  local version="$1"
  local arch archive_url asset_name tmpdir archive_path binary_path

  arch="$(sing_box_alpine_arch)"
  archive_url="$(fetch_sing_box_alpine_url "$version" "$arch")"
  asset_name="${archive_url##*/}"
  tmpdir="$(mktemp -d)"
  archive_path="${tmpdir}/sing-box.tar.gz"

  if ! download_verified_release_asset "$version" "$asset_name" "$archive_path"; then
    rm -rf "$tmpdir"
    return 1
  fi

  if ! tar -xzf "$archive_path" -C "$tmpdir"; then
    rm -rf "$tmpdir"
    return 1
  fi

  binary_path="$(find "$tmpdir" -type f -name sing-box | head -n 1)"
  if [[ -z "$binary_path" ]] || ! "$binary_path" version >/dev/null 2>&1; then
    echo "错误：下载的 sing-box Alpine 二进制无效" >&2
    rm -rf "$tmpdir"
    return 1
  fi

  echo "正在安装 sing-box 到 /usr/local/bin/sing-box"
  install -m 0755 "$binary_path" /usr/local/bin/sing-box
  install_sing_box_openrc_service

  rm -rf "$tmpdir"
}

install_base_dependencies() {
  echo "正在安装基础依赖……"
  if [[ "$PLATFORM" == "alpine" ]]; then
    apk add --no-cache bash curl git openssl ca-certificates iproute2 coreutils jq nftables iptables conntrack-tools openrc
  else
    apt update
    DEBIAN_FRONTEND=noninteractive apt install -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      curl git openssl ca-certificates iproute2 coreutils jq nftables iptables conntrack procps
  fi
}

ensure_port_tools() {
  local command_name

  for command_name in ss awk grep; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      echo "错误：缺少端口检测命令 $command_name；请先安装 iproute2 和基础系统工具" >&2
      return 1
    fi
  done
}

install_sing_box() {
  local release_version attempt installed=0

  if ! release_version="$(fetch_preferred_sing_box_version)"; then
    echo "错误：获取 sing-box 最新 Alpha 版本失败"
    exit 1
  fi
  echo "正在安装 sing-box v${release_version}……"
  for attempt in 1 2 3; do
    if {
      if [[ "$PLATFORM" == "alpine" ]]; then
        install_sing_box_alpine "$release_version"
      else
        install_sing_box_debian "$release_version"
      fi
    } && resolve_sing_box_binary; then
      installed=1
      break
    fi
    if (( attempt < 3 )); then
      echo "警告：sing-box 下载失败，正在进行第 $(( attempt + 1 )) 次尝试……" >&2
      sleep 3
    fi
  done
  hash -r
  if (( ! installed )); then
    echo "错误：sing-box v${release_version} 安装失败，请稍后重试"
    exit 1
  fi
  mkdir -p /etc/sing-box
}

install_dependencies() {
  install_base_dependencies
  install_sing_box
}

install_manager_tool() {
  local source_file temp_file install_ref expected_sha256

  [[ "${SBOX_REALITY_TEST_MODE:-0}" == "1" ]] && return 0
  source_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)/sbox-manager.sh"
  if [[ -f "$source_file" ]]; then
    install -m 0755 "$source_file" "$MANAGER_NODE_BIN"
  else
    install_ref="${SBOX_REALITY_INSTALL_REF:-${SBOX_REALITY_REF:-main}}"
    [[ "$install_ref" =~ ^[A-Za-z0-9._/-]+$ ]] \
      || { echo "错误：SBOX_REALITY_INSTALL_REF 格式无效" >&2; return 1; }
    temp_file="$(mktemp)"
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
      --connect-timeout 10 --max-time 60 \
      -o "$temp_file" \
      "https://raw.githubusercontent.com/akaagiao1/sbox-reality/${install_ref}/sbox-manager.sh" \
      || { rm -f "$temp_file"; return 1; }
    expected_sha256="${SBOX_MANAGER_SHA256:-}"
    if [[ -n "$expected_sha256" ]]; then
      printf '%s  %s\n' "$expected_sha256" "$temp_file" | sha256sum -c - >/dev/null \
        || { rm -f "$temp_file"; echo "错误：sbox-manager.sh SHA-256 校验失败" >&2; return 1; }
    fi
    bash -n "$temp_file" || { rm -f "$temp_file"; return 1; }
    install -m 0755 "$temp_file" "$MANAGER_NODE_BIN"
    rm -f "$temp_file"
  fi
  ln -sfn "$MANAGER_NODE_BIN" "$MANAGER_TRAFFIC_BIN"
  echo "节点管理命令已安装：$MANAGER_NODE_BIN"
}

generate_anytls_secrets() {
  local keypair

  keypair="$(run_sing_box generate reality-keypair)"
  ANYTLS_PRIVATE_KEY="$(echo "$keypair" | awk -F': ' '/PrivateKey/ {print $2}')"
  ANYTLS_PUBLIC_KEY="$(echo "$keypair" | awk -F': ' '/PublicKey/ {print $2}')"
  ANYTLS_PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
  ANYTLS_SHORT_ID="$(openssl rand -hex 8)"

  if [[ -z "$ANYTLS_PRIVATE_KEY" || -z "$ANYTLS_PUBLIC_KEY" || -z "$ANYTLS_PASSWORD" || -z "$ANYTLS_SHORT_ID" ]]; then
    echo "错误：生成 AnyTLS + REALITY 密钥失败"
    exit 1
  fi
}

enable_bbr_and_fq() {
  local current_qdisc current_congestion

  echo "正在开启 BBR 和 fq……"
  mkdir -p "$(dirname "$BBR_SYSCTL_CONF")"
  cat > "$BBR_SYSCTL_CONF" << 'SYSCTL'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
SYSCTL

  if command -v modprobe >/dev/null 2>&1; then
    modprobe tcp_bbr >/dev/null 2>&1 || true
  fi

  if ! sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1; then
    echo "警告：当前内核或虚拟化环境暂时无法启用 fq，已保留开机配置"
  fi
  if ! sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1; then
    echo "警告：当前内核未开放 BBR，已保留开机配置，脚本将继续安装"
  fi

  current_qdisc="$(sysctl -n net.core.default_qdisc 2>/dev/null || true)"
  current_congestion="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)"
  if [[ "$current_qdisc" == "fq" && "$current_congestion" == "bbr" ]]; then
    echo "BBR 和 fq 已开启"
  else
    echo "当前状态：qdisc=${current_qdisc:-未知}，拥塞控制=${current_congestion:-未知}"
  fi
}

generate_vless_secrets() {
  local keypair

  keypair="$(run_sing_box generate reality-keypair)"
  VLESS_PRIVATE_KEY="$(echo "$keypair" | awk -F': ' '/PrivateKey/ {print $2}')"
  VLESS_PUBLIC_KEY="$(echo "$keypair" | awk -F': ' '/PublicKey/ {print $2}')"
  VLESS_UUID="$(run_sing_box generate uuid)"
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
        "certificate_path": "$(json_escape "$CERT_PATH")",
        "key_path": "$(json_escape "$KEY_PATH")"
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
      "tcp_fast_open": true,
      "version": 5,
      "psk": "${SNELL5_PSK}"$(json_snell5_obfs_field)
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
      "tcp_fast_open": true,
      "version": 6,
      "psk": "${SNELL6_PSK}"$(json_snell6_mode_field)
    }
JSON
}

direct_inbound_json() {
  cat << JSON
    {
      "type": "direct",
      "tag": "direct-in",
      "listen": "::",
      "listen_port": ${DIRECT_PORT},
      "override_address": "${DIRECT_TARGET_ADDRESS}",
      "override_port": ${DIRECT_TARGET_PORT}
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
    sep=","
  fi

  if (( INSTALL_DIRECT )); then
    inbounds="${inbounds}${sep}
$(direct_inbound_json)"
  fi

  cat << JSON
[
${inbounds}
]
JSON
}

write_fresh_server_config() {
  local destination="${1:-$SERVER_CONF}"
  local inbounds

  inbounds="$(selected_inbounds_json)"
  inbounds="${inbounds#[}"
  inbounds="${inbounds%]}"

  cat > "$destination" << JSON
{
  "inbounds": [
${inbounds}
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
JSON
}

validate_existing_server_config() {
  local normalized backup

  [[ "$CONFIG_POLICY" == "merge" && -s "$SERVER_CONF" ]] || return 0

  if jq -e . "$SERVER_CONF" >/dev/null 2>&1; then
    return 0
  fi

  # sing-box accepts JSONC, while jq only accepts strict JSON.  Verify the
  # original with sing-box first, then remove comments outside quoted strings.
  # This keeps values such as https:// URLs and passwords containing // intact.
  if run_sing_box check -c "$SERVER_CONF" >/dev/null 2>&1; then
    normalized="$(mktemp)"
    awk '
      BEGIN { in_string = 0; escaped = 0; in_block = 0 }
      {
        output = ""
        for (i = 1; i <= length($0); i++) {
          c = substr($0, i, 1)
          next_c = (i < length($0) ? substr($0, i + 1, 1) : "")

          if (in_block) {
            if (c == "*" && next_c == "/") {
              in_block = 0
              i++
            }
            continue
          }

          if (in_string) {
            output = output c
            if (escaped) escaped = 0
            else if (c == "\\") escaped = 1
            else if (c == "\"") in_string = 0
            continue
          }

          if (c == "\"") {
            in_string = 1
            output = output c
          } else if (c == "/" && next_c == "/") {
            break
          } else if (c == "/" && next_c == "*") {
            in_block = 1
            i++
          } else {
            output = output c
          }
        }
        print output
      }
    ' "$SERVER_CONF" > "$normalized"

    if jq -e . "$normalized" >/dev/null 2>&1; then
      backup="${SERVER_CONF}.jsonc.bak.$(date +%Y%m%d-%H%M%S)"
      cp -p "$SERVER_CONF" "$backup"
      install -m 600 "$normalized" "$SERVER_CONF"
      rm -f "$normalized"
      echo "检测到 JSONC 注释，已转换为标准 JSON；原配置备份：$backup"
      return 0
    fi
    rm -f "$normalized"
  fi

  echo "错误：现有 $SERVER_CONF 无法被 sing-box 或 jq 正确解析，无法安全追加新协议"
  echo "请修复配置，或使用 --config new 生成全新配置"
  exit 1
}

write_server_config() {
  local selected_file="" temp_config warp_config="" final_config

  mkdir -p "$(dirname "$SERVER_CONF")"
  temp_config="$(mktemp "$(dirname "$SERVER_CONF")/.sbox-config.XXXXXX")"
  if [[ "$CONFIG_POLICY" != "merge" || ! -s "$SERVER_CONF" ]]; then
    write_fresh_server_config "$temp_config"
  else
    validate_existing_server_config
    selected_file="$(mktemp)"
    selected_inbounds_json > "$selected_file"

    if ! jq --slurpfile selected "$selected_file" '
      ($selected[0] | map(.tag)) as $selected_tags
      | .inbounds = (
          [
            (.inbounds // [])[]
            | select((.tag // "") as $tag | ($selected_tags | index($tag) | not))
          ] + $selected[0]
        )
      | .outbounds = (
          if ((.outbounds // []) | length) > 0 then .outbounds
          else [{"type": "direct"}]
          end
        )
    ' "$SERVER_CONF" > "$temp_config"; then
      rm -f "$selected_file" "$temp_config"
      echo "错误：合并 sing-box 配置失败，现有配置保持不变" >&2
      return 1
    fi
  fi
  rm -f "$selected_file"

  final_config="$temp_config"
  if (( WARP_INSTALL_ACTIVE )); then
    warp_config="$(mktemp "$(dirname "$SERVER_CONF")/.sbox-warp-config.XXXXXX")"
    if ! warp_merge_config "$temp_config" "$WARP_STAGED_CREDENTIALS" \
      "$WARP_INSTALL_RULES_JSON" "$warp_config"; then
      rm -f "$temp_config" "$warp_config"
      echo "错误：WARP 与协议配置合并失败，现有配置保持不变" >&2
      return 1
    fi
    final_config="$warp_config"
  fi

  if ! run_sing_box check -c "$final_config"; then
    rm -f "$temp_config" "$warp_config"
    echo "错误：新配置未通过 sing-box 验证，现有配置保持不变" >&2
    return 1
  fi

  if ! begin_install_transaction; then
    rm -f "$temp_config" "$warp_config"
    return 1
  fi

  if (( WARP_INSTALL_ACTIVE )); then
    if ! chmod 600 "$final_config" "$WARP_STAGED_CREDENTIALS" \
      || ! mv -f "$final_config" "$SERVER_CONF" \
      || ! mv -f "$WARP_STAGED_CREDENTIALS" "$WARP_CREDENTIALS_FILE"; then
      rollback_install_transaction || true
      warp_finalize_install_transaction || true
      rm -f "$temp_config" "$warp_config"
      return 1
    fi
  elif ! chmod 600 "$final_config" || ! mv -f "$final_config" "$SERVER_CONF"; then
    rollback_install_transaction || true
    rm -f "$temp_config" "$warp_config"
    return 1
  fi
  rm -f "$temp_config" "$warp_config"
}

detect_server_ip() {
  local candidate answer

  if [[ -n "$SERVER_HOST" ]]; then
    if ! validate_server_host "$SERVER_HOST"; then
      echo "错误：--server-host 必须是有效的 IP 地址或域名：$SERVER_HOST" >&2
      return 1
    fi
    SERVER_IP="${SERVER_HOST#[}"
    SERVER_IP="${SERVER_IP%]}"
  else
    for candidate in \
      "$(curl -4 -fsS --connect-timeout 5 --max-time 8 https://api.ipify.org 2>/dev/null || true)" \
      "$(curl -6 -fsS --connect-timeout 5 --max-time 8 https://api.ipify.org 2>/dev/null || true)"; do
      if [[ -n "$candidate" ]] && validate_server_host "$candidate"; then
        SERVER_IP="$candidate"
        break
      fi
    done
  fi

  if [[ -z "$SERVER_IP" ]]; then
    if [[ -t 0 ]]; then
      while true; do
        read -rp "无法自动获取公网地址，请输入 VPS 公网 IP 或域名：" answer
        if validate_server_host "$answer"; then
          SERVER_IP="${answer#[}"
          SERVER_IP="${SERVER_IP%]}"
          break
        fi
        echo "错误：请输入有效的 IP 地址或域名"
      done
    else
      echo "错误：无法自动获取公网地址；非交互安装请使用 --server-host 指定" >&2
      return 1
    fi
  fi

  SERVER_URL_HOST="$(url_host "$SERVER_IP")"
}

run_install_after_config_steps() {
  if (( INSTALL_HY2 )); then
    if [[ "$HY2_PORT_HOPPING" == "on" ]]; then
      write_port_hopping_helper || return 1
    else
      disable_hy2_port_hopping || return 1
    fi
  elif [[ "$CONFIG_POLICY" == "new" ]]; then
    disable_hy2_port_hopping || return 1
  fi

  if (( INSTALL_ANYTLS )); then
    write_anytls_client || return 1
  fi
  if (( INSTALL_VLESS )); then
    write_vless_client || return 1
  fi
  if (( INSTALL_HY2 )); then
    write_hy2_clients || return 1
  fi
  if (( INSTALL_SNELL5 || INSTALL_SNELL6 )); then
    write_snell_clients || return 1
  fi
  if (( INSTALL_ANYTLS )) && ! run_sing_box check -c "$ANYTLS_CLIENT_OUT"; then
    return 1
  fi
  if (( INSTALL_VLESS )) && ! run_sing_box check -c "$VLESS_CLIENT_OUT"; then
    return 1
  fi
  if (( INSTALL_HY2 )) && ! run_sing_box check -c "$HY2_CLIENT_OUT"; then
    return 1
  fi
  if (( INSTALL_SNELL5 )) && ! run_sing_box check -c "$SNELL5_CLIENT_OUT"; then
    return 1
  fi
  if (( INSTALL_SNELL6 )) && ! run_sing_box check -c "$SNELL6_CLIENT_OUT"; then
    return 1
  fi

  service_reload || return 1
  service_enable || return 1
  service_restart || return 1
}

complete_install_after_config() {
  local status

  if run_install_after_config_steps; then
    finalize_install_transaction || return 1
    if (( WARP_INSTALL_ACTIVE )); then
      warp_finalize_install_transaction || return 1
    fi
    return 0
  else
    status=$?
  fi

  echo "错误：安装完成阶段失败，正在恢复安装前状态" >&2
  if ! rollback_install_transaction; then
    return 1
  fi
  service_reload || true
  restore_install_service_state
  if (( WARP_INSTALL_ACTIVE )); then
    warp_finalize_install_transaction || true
  fi
  return "$status"
}

write_anytls_client() {
  build_anytls_share_url
  cat > "$ANYTLS_CLIENT_OUT" << JSON
{
  "outbounds": [
    {
      "type": "anytls",
      "server": "${SERVER_IP}",
      "server_port": ${ANYTLS_PORT},
      "password": "${ANYTLS_PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_DOMAIN}",
        "utls": {
          "enabled": true
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
      "server": "${SERVER_IP}",
      "server_port": ${VLESS_PORT},
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${VLESS_DOMAIN}",
        "utls": {
          "enabled": true
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
      "server": "${SERVER_IP}",
$(json_hy2_server_port_field)$(json_hop_interval_field)$(json_number_field "up_mbps" "$UP_MBPS")$(json_number_field "down_mbps" "$DOWN_MBPS")$(json_obfs_field)      "password": "${HY2_PASSWORD}",
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
      "server": "${SERVER_IP}",
      "server_port": ${SNELL5_PORT},
      "tcp_fast_open": true,
      "reuse": true,
      "version": 4,
      "psk": "${SNELL5_PSK}"$(json_snell5_obfs_field)
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
      "server": "${SERVER_IP}",
      "server_port": ${SNELL6_PORT},
      "tcp_fast_open": true,
      "reuse": true,
      "version": 6,
      "psk": "${SNELL6_PSK}"$(json_snell6_mode_field)
    }
  ]
}
JSON
    printf '%s\n' "$SNELL6_SHARE_URL" > "$SNELL6_URL_FILE"
  fi

  if (( INSTALL_SNELL5 )); then
    SNELL5_SURGE_LINE="SnellV5=snell,${SERVER_URL_HOST},${SNELL5_PORT},psk=\"${SNELL5_PSK}\",version=5,tfo=true,reuse=true"
  elif [[ -f "$SNELL5_INFO" ]]; then
    SNELL5_SURGE_LINE="$(sed -n '/^SnellV5=snell,/p' "$SNELL5_INFO" | head -n 1)"
  fi

  if (( INSTALL_SNELL6 )); then
    SNELL6_SURGE_LINE="SnellV6=snell,${SERVER_URL_HOST},${SNELL6_PORT},psk=\"${SNELL6_PSK}\",version=6,mode=${SNELL6_MODE},tfo=true,reuse=true"
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
  local warp_rules_json="[]"
  local has_anytls=0
  local has_vless=0
  local has_hy2=0
  local has_snell5=0
  local has_snell6=0
  local has_direct=0

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
  jq -e '.inbounds[]? | select(.tag == "direct-in")' "$SERVER_CONF" >/dev/null 2>&1 && has_direct=1
  warp_rules_json="$(warp_current_rules "$SERVER_CONF" 2>/dev/null || printf '[]')"

  cat > "$COMBINED_INFO" << TXT
sbox-reality 统一安装完成

服务端：
  配置文件：$SERVER_CONF
  已安装 AnyTLS + REALITY：$has_anytls
  已安装 VLESS + REALITY：$has_vless
  已安装 Hysteria2 + Surge：$has_hy2
  已安装 Snell v5：$has_snell5
  已安装 Snell v6：$has_snell6
  已安装 Direct 固定目标中转：$has_direct
  WARP 分流规则：$(jq -r 'if length == 0 then "未启用" else join(",") end' <<< "$warp_rules_json")
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
Hysteria2 + Surge 安装完成

服务端：
  配置文件：$SERVER_CONF
  监听端口：$HY2_PORT
  端口模式：$HY2_PORT_MODE
  端口跳跃：$HY2_PORT_HOPPING
  SNI：$HY2_SNI
  证书：$CERT_PATH
  私钥：$KEY_PATH

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
  密码：$HY2_PASSWORD
  SNI：$HY2_SNI
  跳过证书验证：true
TXT

    if [[ "$HY2_PORT_HOPPING" == "on" ]]; then
      cat >> "$HY2_INFO" << TXT
  跳跃端口：$NORMALIZED_HOP_PORTS
  跳跃间隔：$HOP_INTERVAL

端口跳跃辅助文件：
  辅助脚本：$PORT_HELPER
  环境文件：$PORT_ENV
  服务配置：$port_service_config
TXT
    fi

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
TXT
    if [[ "$HY2_PORT_HOPPING" == "on" ]]; then
      cat >> "$HY2_INFO" << TXT
  请放行公共 UDP 端口：$NORMALIZED_HOP_PORTS
  如果本机防火墙在重定向后过滤流量，还需放行 UDP 监听端口：$HY2_PORT
TXT
    else
      cat >> "$HY2_INFO" << TXT
  请放行 UDP 监听端口：$HY2_PORT
TXT
    fi
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

  if (( INSTALL_DIRECT )); then
    cat > "$DIRECT_INFO" << TXT
Direct 固定目标中转安装完成

服务端：
  配置文件：$SERVER_CONF
  TCP/UDP 监听端口：$DIRECT_PORT
  端口模式：$DIRECT_PORT_MODE
  中转目标：${DIRECT_TARGET_ADDRESS}:${DIRECT_TARGET_PORT}

使用方式：
  将流量发送到 ${SERVER_IP}:${DIRECT_PORT}，sing-box 会转发到 ${DIRECT_TARGET_ADDRESS}:${DIRECT_TARGET_PORT}。
  请按实际用途在服务器防火墙和 NAT 映射中放行 TCP/UDP 端口 $DIRECT_PORT。

安全提示：
  Direct 入站不提供加密或认证，请仅开放给可信来源，避免成为公开 UDP 转发器。
TXT
    cat "$DIRECT_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  elif [[ -f "$DIRECT_INFO" ]]; then
    cat "$DIRECT_INFO" >> "$COMBINED_INFO"
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

normalize_single_customer_protocol() {
  local raw token normalized found=""
  local -a items

  raw="$(normalize_mode_input "${INSTALL_MODE:-}")"
  IFS=',' read -r -a items <<< "$raw"
  for token in "${items[@]}"; do
    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"
    [[ -n "$token" ]] || continue
    normalized="$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')"
    case "$normalized" in
      1|reality|anytls) normalized="anytls" ;;
      2|hy2|hysteria2|surge) normalized="hy2" ;;
      3|vless|vless-reality) normalized="vless" ;;
      4|snell5|snell-v5) normalized="snell5" ;;
      5|snell6|snell-v6) normalized="snell6" ;;
      9|direct|direct-udp|udp-forward) normalized="direct" ;;
      *) return 1 ;;
    esac
    [[ -z "$found" ]] || return 1
    found="$normalized"
  done
  [[ -n "$found" ]] || return 1
  printf '%s' "$found"
}

run_customer_install() {
  local protocol port
  local -a manager_args args

  [[ "$ACTION" == "install" ]] \
    || { echo "错误：--customer 只能用于创建客户节点" >&2; exit 1; }
  [[ "$CUSTOMER_ID" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$ ]] \
    || { echo "错误：客户 ID 只能包含字母、数字、点、下划线和连字符" >&2; exit 1; }
  protocol="$(normalize_single_customer_protocol)" \
    || { echo "错误：--customer 一次只能创建一个协议节点，例如 --mode snell5" >&2; exit 1; }
  [[ "$CONFIG_POLICY" == "ask" || "$CONFIG_POLICY" == "merge" ]] \
    || { echo "错误：--customer 不能与 --config $CONFIG_POLICY 同用" >&2; exit 1; }
  (( WARP_RULES_EXPLICIT || WARP_RESET || WARP_OFF )) \
    && { echo "错误：--customer 不能和 WARP 参数同时使用；请先创建节点后再单独配置 WARP" >&2; exit 1; }
  if [[ -n "$TG_TOKEN" || -n "$TG_CHAT_ID" ]]; then
    [[ -n "$TG_TOKEN" && -n "$TG_CHAT_ID" ]] \
      || { echo "错误：Telegram Token 和 Chat ID 必须同时提供" >&2; exit 1; }
  fi
  if [[ $EUID -ne 0 && "${SBOX_REALITY_TEST_MODE:-0}" != "1" ]]; then
    echo "错误：请使用 root 用户运行"
    exit 1
  fi

  detect_platform
  install_dependencies
  install_manager_tool
  enable_bbr_and_fq
  service_enable || true

  case "$protocol" in
    anytls)
      port="${SHARED_PORT:-$ANYTLS_PORT}"
      args=(--server-name "$REALITY_DOMAIN")
      ;;
    vless)
      port="${SHARED_PORT:-$VLESS_PORT}"
      args=(--server-name "$VLESS_DOMAIN")
      ;;
    hy2)
      port="${SHARED_PORT:-$HY2_PORT}"
      args=(--server-name "$HY2_SNI")
      [[ "$OBFS" == "off" ]] || args+=(--obfs "$OBFS")
      ;;
    snell5)
      port="${SHARED_PORT:-$SNELL5_PORT}"
      args=(--snell5-obfs "$SNELL5_OBFS_MODE")
      ;;
    snell6)
      port="${SHARED_PORT:-$SNELL6_PORT}"
      args=(--snell6-mode "$SNELL6_MODE")
      ;;
    direct)
      port="${SHARED_PORT:-$DIRECT_PORT}"
      args=(--target "$DIRECT_TARGET_ADDRESS" --target-port "$DIRECT_TARGET_PORT")
      [[ -n "$DIRECT_TARGET_ADDRESS" && -n "$DIRECT_TARGET_PORT" ]] \
        || { echo "错误：Direct 客户节点需要 --direct-address 和 --direct-target-port" >&2; exit 1; }
      ;;
  esac

  manager_args=(
    node add "$CUSTOMER_ID" "$protocol"
    --customer "$CUSTOMER_ID"
    --port "$port"
    --quota "$CUSTOMER_QUOTA"
    --reset-day "$CUSTOMER_RESET_DAY"
  )
  [[ -n "$CUSTOMER_EXPIRES" ]] && manager_args+=(--expires "$CUSTOMER_EXPIRES")
  manager_args+=("${args[@]}")
  SBOX_SERVER_HOST="$SERVER_HOST" "$MANAGER_NODE_BIN" "${manager_args[@]}"

  if [[ -n "$TG_TOKEN" && -n "$TG_CHAT_ID" ]]; then
    "$MANAGER_NODE_BIN" notify setup "$TG_TOKEN" "$TG_CHAT_ID"
    "$MANAGER_NODE_BIN" notify test || true
  fi
  echo
  echo "客户节点一键安装完成：$CUSTOMER_ID"
  echo "使用 sbox-node node list 查看所有客户节点。"
}

prompt_telegram_setup() {
  local answer

  if [[ -n "$TG_TOKEN" || -n "$TG_CHAT_ID" ]]; then
    [[ -n "$TG_TOKEN" && -n "$TG_CHAT_ID" ]] \
      || { echo "错误：Telegram Token 和 Chat ID 必须同时提供" >&2; exit 1; }
    return 0
  fi
  [[ -t 0 ]] || {
    echo "错误：首次初始化需要配置 Telegram；非交互模式请同时提供 --tg-token 和 --tg-chat-id" >&2
    exit 1
  }
  read -rp "是否现在配置 Telegram 通知？[Y/n]：" answer
  case "${answer:-Y}" in
    n|N|no|NO) return 1 ;;
  esac
  read -rsp "Telegram Bot Token：" TG_TOKEN
  echo
  read -rp "Telegram Chat ID（多个用英文逗号分隔）：" TG_CHAT_ID
  [[ -n "$TG_TOKEN" && -n "$TG_CHAT_ID" ]] \
    || { echo "错误：Telegram Token 和 Chat ID 不能为空" >&2; exit 1; }
}

run_manager_setup() {
  local telegram_configured=0 answer

  [[ "$ACTION" == "install" ]] \
    || { echo "错误：--setup 不能和卸载、恢复动作同时使用" >&2; exit 1; }
  [[ -z "$CUSTOMER_ID" && -z "$INSTALL_MODE" ]] \
    || { echo "错误：--setup 只做首次初始化；创建客户请使用 --customer 或 sbox-node node add" >&2; exit 1; }
  if [[ $EUID -ne 0 && "${SBOX_REALITY_TEST_MODE:-0}" != "1" ]]; then
    echo "错误：请使用 root 用户运行"
    exit 1
  fi

  detect_platform
  install_dependencies
  install_manager_tool
  enable_bbr_and_fq
  service_enable || true

  if prompt_telegram_setup; then
    "$MANAGER_NODE_BIN" notify setup "$TG_TOKEN" "$TG_CHAT_ID"
    if "$MANAGER_NODE_BIN" notify test; then
      telegram_configured=1
    else
      echo "警告：Telegram 测试消息发送失败，请检查 Token、Chat ID 或机器人权限" >&2
    fi
  else
    echo "已跳过 Telegram 配置；之后可运行 sbox-node notify setup TOKEN CHAT_ID"
  fi
  "$MANAGER_NODE_BIN" traffic timer >/dev/null 2>&1 || true

  echo
  echo "首次初始化完成。"
  if (( telegram_configured )); then
    echo "Telegram 通知：已配置并测试"
  else
    echo "Telegram 通知：未配置"
  fi
  echo "下一步添加客户："
  echo "  sbox-node node add customer-a snell5 --port 25001 --quota 100G --expires 2026-12-31"
  if [[ -t 0 ]]; then
    read -rp "现在进入客户节点管理菜单？[Y/n]：" answer
    if [[ ! "${answer:-Y}" =~ ^[Nn]$ ]]; then
      "$MANAGER_NODE_BIN" menu
    fi
  fi
}

main() {
  if [[ -n "$MANAGEMENT_MODE" ]]; then
    if [[ -x "$MANAGER_NODE_BIN" ]]; then
      exec "$MANAGER_NODE_BIN" "$MANAGEMENT_MODE" "${MANAGEMENT_ARGS[@]}"
    fi
    echo "错误：节点管理命令尚未安装，请先运行 install.sh 完成安装" >&2
    exit 1
  fi

  if (( INIT_MANAGER )); then
    run_manager_setup
    return 0
  fi
  choose_mode
  if [[ -n "$CUSTOMER_ID" ]]; then
    run_customer_install
    return 0
  fi
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
  warp_migrate_legacy_credentials || return 1
  resolve_sing_box_binary || true

  if [[ "$ACTION" == "warp" ]]; then
    install_base_dependencies
    if [[ -z "$SING_BOX_BIN" ]] && ! resolve_sing_box_binary; then
      echo "错误：独立配置 WARP 前需要已安装 sing-box" >&2
      return 1
    fi
    warp_run_standalone
    return 0
  fi

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

  install_base_dependencies
  validate_existing_server_config
  choose_install_ports
  prepare_inputs
  if [[ -t 0 ]] && (( ! WARP_RULES_EXPLICIT && ! WARP_RESET )); then
    warp_prompt_rules
  fi

  echo "sbox-reality 统一安装脚本"
  echo "  安装 AnyTLS + REALITY：$INSTALL_ANYTLS"
  echo "  安装 VLESS + REALITY：$INSTALL_VLESS"
  echo "  安装 Hysteria2 + Surge：$INSTALL_HY2"
  echo "  安装 Snell v5：$INSTALL_SNELL5"
  echo "  安装 Snell v6：$INSTALL_SNELL6"
  echo "  安装 Direct 固定目标中转：$INSTALL_DIRECT"
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
    echo "  Hysteria2 端口跳跃：$HY2_PORT_HOPPING"
    if [[ "$HY2_PORT_HOPPING" == "on" ]]; then
      echo "  Hysteria2 跳跃端口：$NORMALIZED_HOP_PORTS"
      echo "  Hysteria2 跳跃间隔：${HOP_INTERVAL} 秒"
    fi
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
  if (( INSTALL_DIRECT )); then
    echo "  Direct 监听端口：$DIRECT_PORT ($DIRECT_PORT_MODE)"
    echo "  Direct 中转目标：${DIRECT_TARGET_ADDRESS}:${DIRECT_TARGET_PORT}"
  fi
  if (( WARP_RULES_EXPLICIT )); then
    echo "  WARP 分流规则：$(jq -r 'join(",")' <<< "$WARP_RULES_JSON")"
  elif (( WARP_RESET )); then
    echo "  WARP 凭据：重新注册并沿用现有规则"
  fi
  echo

  if [[ "$CONFIG_POLICY" == "new" && -s "$SERVER_CONF" ]] \
    && (( ! WARP_RULES_EXPLICIT && ! WARP_RESET )); then
    backup_existing_files "before-new-config"
  fi

  install_sing_box
  install_manager_tool
  warp_prepare_install_state
  enable_bbr_and_fq
  verify_snell_support

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
  fi

  write_server_config
  complete_install_after_config

  write_info_files
  print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
