#!/usr/bin/env bash
set -euo pipefail
umask 077

STATE_DIR="/etc/sbox-reality"
NODES_FILE="$STATE_DIR/nodes.json"
TRAFFIC_DIR="$STATE_DIR/traffic"
TRAFFIC_STATE="$TRAFFIC_DIR/state.json"
NOTIFY_ENV="$STATE_DIR/notify.env"
SERVER_HOST_FILE="$STATE_DIR/server-host"
CLIENTS_ROOT="/root/sbox-reality/clients"
MANAGER_BACKUP_ROOT="$STATE_DIR/backups"
SERVER_CONF="/etc/sing-box/config.json"
TRAFFIC_CHAIN="SBOX_TRF"
TIMEZONE="Asia/Shanghai"
MANAGER_PATH="/usr/local/sbin/sbox-node"
MANAGER_ALIAS="/usr/local/sbin/sbox-traffic"

if [[ "${SBOX_MANAGER_TEST_MODE:-0}" == "1" ]]; then
  STATE_DIR="${SBOX_STATE_DIR_OVERRIDE:-$STATE_DIR}"
  NODES_FILE="$STATE_DIR/nodes.json"
  TRAFFIC_DIR="$STATE_DIR/traffic"
  TRAFFIC_STATE="$TRAFFIC_DIR/state.json"
  NOTIFY_ENV="$STATE_DIR/notify.env"
  SERVER_HOST_FILE="$STATE_DIR/server-host"
  CLIENTS_ROOT="${SBOX_CLIENTS_ROOT_OVERRIDE:-$CLIENTS_ROOT}"
  SERVER_CONF="${SBOX_SERVER_CONF_OVERRIDE:-$SERVER_CONF}"
  MANAGER_BACKUP_ROOT="$STATE_DIR/backups"
fi

SING_BOX_BIN="${SING_BOX_BIN:-}"
LOCK_FILE="$STATE_DIR/.lock"

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

warn() {
  printf '警告：%s\n' "$*" >&2
}

require_root() {
  [[ ${EUID:-0} -eq 0 ]] || die "请使用 root 运行"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

validate_id() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,47}$ ]]
}

validate_port() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

validate_reset_day() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 >= 1 && 10#$1 <= 28 ))
}

size_to_bytes() {
  local value="$1"
  awk -v v="$value" '
    BEGIN {
      if (v !~ /^[0-9]+([.][0-9]+)?([KMGTPE]i?B?|B)?$/) exit 1
      unit = v
      sub(/^[0-9]+([.][0-9]+)?/, "", unit)
      num = v
      sub(/([KMGTPE]i?B?|B)$/, "", num)
      mult = 1
      if (unit ~ /^K/) mult = 1024
      else if (unit ~ /^M/) mult = 1024 * 1024
      else if (unit ~ /^G/) mult = 1024 * 1024 * 1024
      else if (unit ~ /^T/) mult = 1024 * 1024 * 1024 * 1024
      else if (unit ~ /^P/) mult = 1024 * 1024 * 1024 * 1024 * 1024
      printf "%.0f\n", num * mult
    }
  ' 2>/dev/null
}

parse_expiry_epoch() {
  local value="$1"
  [[ -n "$value" ]] || { printf '0'; return; }
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
    return
  fi
  [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && value="$value 23:59:59"
  TZ="$TIMEZONE" date -d "$value" +%s 2>/dev/null \
    || die "无法解析到期时间：$1（使用 YYYY-MM-DD 或 YYYY-MM-DD HH:MM:SS）"
}

format_time() {
  local epoch="${1:-0}"
  (( epoch > 0 )) || { printf '未设置'; return; }
  TZ="$TIMEZONE" date -d "@$epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null \
    || printf '%s' "$epoch"
}

format_bytes() {
  local bytes="${1:-0}"
  awk -v b="$bytes" '
    BEGIN {
      split("B KB MB GB TB PB", u, " ")
      i = 1
      while (b >= 1024 && i < 6) { b /= 1024; i++ }
      if (i == 1) printf "%.0f%s", b, u[i]
      else printf "%.2f%s", b, u[i]
    }
  '
}

acquire_lock() {
  mkdir -p "$STATE_DIR"
  exec 9>"$LOCK_FILE"
  if command -v flock >/dev/null 2>&1; then
    flock -w 60 9 || die "等待状态锁超时"
  fi
}

init_state() {
  mkdir -p "$STATE_DIR" "$TRAFFIC_DIR" "$CLIENTS_ROOT"
  chmod 700 "$STATE_DIR" "$TRAFFIC_DIR" "$CLIENTS_ROOT"
  if [[ ! -s "$NODES_FILE" ]]; then
    printf '{"schema":1,"nodes":[]}\n' > "$NODES_FILE"
  fi
  if [[ ! -s "$TRAFFIC_STATE" ]]; then
    printf '{}\n' > "$TRAFFIC_STATE"
  fi
  chmod 600 "$NODES_FILE" "$TRAFFIC_STATE"
  jq -e '.schema == 1 and (.nodes | type == "array")' "$NODES_FILE" >/dev/null \
    || die "节点状态文件无效：$NODES_FILE"
}

atomic_json_from_tmp() {
  local tmp="$1" destination="$2"
  jq -e . "$tmp" >/dev/null || {
    rm -f "$tmp"
    die "生成的 JSON 无效：$destination"
  }
  chmod 600 "$tmp"
  mv -f "$tmp" "$destination"
}

resolve_sing_box() {
  local candidate
  if [[ -n "$SING_BOX_BIN" && -x "$SING_BOX_BIN" ]]; then
    return 0
  fi
  for candidate in /usr/bin/sing-box /usr/local/bin/sing-box; do
    if [[ -x "$candidate" ]]; then
      SING_BOX_BIN="$candidate"
      return 0
    fi
  done
  if command -v sing-box >/dev/null 2>&1; then
    SING_BOX_BIN="$(command -v sing-box)"
    return 0
  fi
  die "找不到 sing-box 二进制"
}

service_restart() {
  if [[ "${SBOX_NO_RESTART:-0}" == "1" ]]; then
    info "已跳过 sing-box 重启（SBOX_NO_RESTART=1）"
    return 0
  fi
  if command -v systemctl >/dev/null 2>&1 \
    && systemctl list-unit-files sing-box.service >/dev/null 2>&1; then
    systemctl restart sing-box
    for _ in {1..10}; do
      systemctl is-active --quiet sing-box && return 0
      sleep 1
    done
    systemctl status sing-box --no-pager >&2 || true
    return 1
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service sing-box restart >/dev/null 2>&1 \
      || rc-service sing-box start >/dev/null 2>&1 \
      || return 1
    for _ in {1..10}; do
      rc-service sing-box status >/dev/null 2>&1 && return 0
      sleep 1
    done
  fi
  return 1
}

server_host() {
  local host candidate
  host="${SBOX_SERVER_HOST:-}"
  if [[ -z "$host" && -s "$SERVER_HOST_FILE" ]]; then
    IFS= read -r host < "$SERVER_HOST_FILE"
  fi
  if [[ -z "$host" ]]; then
    for candidate in \
      "$(curl -4 -fsS --connect-timeout 5 --max-time 8 https://api.ipify.org 2>/dev/null || true)" \
      "$(curl -6 -fsS --connect-timeout 5 --max-time 8 https://api.ipify.org 2>/dev/null || true)"; do
      if [[ -n "$candidate" ]]; then
        host="$candidate"
        break
      fi
    done
  fi
  [[ -n "$host" ]] || die "无法获取公网地址，请设置 SBOX_SERVER_HOST"
  printf '%s' "$host" > "$SERVER_HOST_FILE"
  chmod 600 "$SERVER_HOST_FILE"
  printf '%s' "$host"
}

url_host() {
  if [[ "$1" == *:* ]]; then printf '[%s]' "$1"; else printf '%s' "$1"; fi
}

url_encode() {
  local value="$1" result="" char encoded
  local i
  for (( i=0; i<${#value}; i++ )); do
    char="${value:i:1}"
    case "$char" in
      [a-zA-Z0-9.~_-]) result+="$char" ;;
      *)
        printf -v encoded '%%%02X' "'$char"
        result+="$encoded"
        ;;
    esac
  done
  printf '%s' "$result"
}

node_tag_for() {
  local protocol="$1" id="$2"
  case "$protocol" in
    snell5) printf 'sbox-snell5-%s' "$id" ;;
    snell6) printf 'sbox-snell6-%s' "$id" ;;
    anytls|vless|hy2|direct) printf 'sbox-%s-%s' "$protocol" "$id" ;;
    *) die "不支持的协议：$protocol" ;;
  esac
}

transport_for() {
  case "$1" in
    snell5|snell6|anytls|vless) printf 'tcp' ;;
    hy2) printf 'udp' ;;
    direct) printf 'tcp udp' ;;
    *) die "不支持的协议：$1" ;;
  esac
}

port_in_config() {
  local port="$1"
  [[ -s "$SERVER_CONF" ]] || return 1
  jq -e --argjson p "$port" \
    '[.inbounds[]? | select(.listen_port == $p)] | length > 0' \
    "$SERVER_CONF" >/dev/null 2>&1
}

pick_free_port() {
  local port
  for _ in {1..200}; do
    port=$(( 20000 + $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 45536 ))
    if ! ss -H -lntup 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {found=1} END {exit !found}'; then
      if ! port_in_config "$port" \
        && ! jq -e --argjson p "$port" '[.nodes[] | select(.port == $p)] | length > 0' \
          "$NODES_FILE" >/dev/null 2>&1; then
        printf '%s' "$port"
        return 0
      fi
    fi
  done
  die "无法自动选择空闲端口"
}

generate_reality_keypair() {
  resolve_sing_box
  "$SING_BOX_BIN" generate reality-keypair
}

render_generated_inbounds() {
  local nodes_file="$1" output="$2"
  jq '
    def reality($n):
      {
        enabled: true,
        server_name: $n.server_name,
        reality: {
          enabled: true,
          handshake: {server: $n.server_name, server_port: 443},
          private_key: $n.private_key,
          short_id: [$n.short_id]
        }
      };
    [
      .nodes[] |
      if .protocol == "snell5" then
        ({type:"snell", tag:.tag, listen:"::", listen_port:.port,
          tcp_fast_open:true, version:5, psk:.psk}
         + (if (.obfs_mode // "none") == "http" then {obfs_mode:"http"} else {} end))
      elif .protocol == "snell6" then
        ({type:"snell", tag:.tag, listen:"::", listen_port:.port,
          tcp_fast_open:true, version:6, psk:.psk}
         + (if (.mode // "default") != "default" then {mode:.mode} else {} end))
      elif .protocol == "anytls" then
        {type:"anytls", tag:.tag, listen:"::", listen_port:.port,
         users:[{password:.password}], tls:reality(.)}
      elif .protocol == "vless" then
        {type:"vless", tag:.tag, listen:"::", listen_port:.port,
         users:[{uuid:.uuid, flow:"xtls-rprx-vision"}], tls:reality(.)}
      elif .protocol == "hy2" then
        ({type:"hysteria2", tag:.tag, listen:"::", listen_port:.port,
          users:[{password:.password}],
          tls:{enabled:true, certificate_path:.cert_path, key_path:.key_path}}
         + (if (.obfs // "") != "" then
              {obfs:{type:.obfs, password:.obfs_password}}
            else {} end))
      elif .protocol == "direct" then
        {type:"direct", tag:.tag, listen:"::", listen_port:.port,
         override_address:.target_address, override_port:.target_port}
      else empty end
    ]
  ' "$nodes_file" > "$output"
}

render_server_config() {
  local nodes_file="$1" output="$2" generated managed_tags
  generated="$(mktemp)"
  render_generated_inbounds "$nodes_file" "$generated"
  managed_tags="$(jq -c '[.nodes[].tag]' "$nodes_file")"
  if [[ -s "$SERVER_CONF" ]]; then
    jq --slurpfile generated "$generated" --argjson managed "$managed_tags" '
      .inbounds = ([
        (.inbounds // [])[]
        | select((.tag // "") as $tag | ($managed | index($tag)) == null)
      ] + $generated[0])
      | .outbounds =
          (if ((.outbounds // []) | length) > 0 then .outbounds
           else [{type:"direct"}] end)
    ' "$SERVER_CONF" > "$output"
  else
    jq -n --slurpfile generated "$generated" \
      '{inbounds:$generated[0], outbounds:[{type:"direct"}]}' > "$output"
  fi
  rm -f "$generated"
}

validate_candidate_config() {
  local nodes_file="$1" config="$2" port
  if [[ "${SBOX_SKIP_SING_BOX_CHECK:-0}" != "1" ]]; then
    resolve_sing_box
    "$SING_BOX_BIN" check -c "$config" >/dev/null
  fi
  while IFS= read -r port; do
    [[ -n "$port" ]] || continue
    if (( $(jq --argjson p "$port" '[.nodes[] | select(.port == $p)] | length' "$nodes_file") > 1 )); then
      die "节点端口重复：$port"
    fi
  done < <(jq -r '.nodes[].port' "$nodes_file")
}

backup_manager_state() {
  local reason="$1" directory candidate count=0
  mkdir -p "$MANAGER_BACKUP_ROOT"
  chmod 700 "$MANAGER_BACKUP_ROOT"
  directory="$MANAGER_BACKUP_ROOT/${reason}-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$directory"
  chmod 700 "$directory"
  cp -p "$NODES_FILE" "$directory/nodes.json"
  [[ -f "$SERVER_CONF" ]] && cp -p "$SERVER_CONF" "$directory/config.json"
  [[ -f "$TRAFFIC_STATE" ]] && cp -p "$TRAFFIC_STATE" "$directory/traffic-state.json"
  : > "$directory/.sbox-manager-backup"
  chmod 600 "$directory"/*
  while IFS= read -r candidate; do
    count=$(( count + 1 ))
    if (( count > 20 )); then
      rm -rf -- "$candidate"
    fi
  done < <(find "$MANAGER_BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
    | sort -r)
}

commit_nodes_and_config() {
  local candidate_nodes="$1" candidate_config="$2"
  local old_nodes old_config="" config_existed=0
  old_nodes="$(mktemp)"
  cp -p "$NODES_FILE" "$old_nodes"
  if [[ -f "$SERVER_CONF" ]]; then
    config_existed=1
    old_config="$(mktemp)"
    cp -p "$SERVER_CONF" "$old_config"
  fi
  backup_manager_state before-change
  validate_candidate_config "$candidate_nodes" "$candidate_config"
  atomic_json_from_tmp "$candidate_nodes" "$NODES_FILE"
  atomic_json_from_tmp "$candidate_config" "$SERVER_CONF"
  if ! service_restart; then
    warn "sing-box 重启失败，正在回滚节点配置"
    atomic_json_from_tmp "$old_nodes" "$NODES_FILE"
    if (( config_existed )); then
      atomic_json_from_tmp "$old_config" "$SERVER_CONF"
    else
      rm -f "$SERVER_CONF"
    fi
    service_restart || true
    return 1
  fi
  rm -f "$old_nodes" "$old_config"
}

node_json_by_id() {
  jq -c --arg id "$1" '.nodes[] | select(.id == $id)' "$NODES_FILE"
}

node_exists() {
  jq -e --arg id "$1" '[.nodes[] | select(.id == $id)] | length == 1' \
    "$NODES_FILE" >/dev/null 2>&1
}

client_dir_for() {
  printf '%s/%s' "$CLIENTS_ROOT" "$1"
}

write_client_files() {
  local node_json="$1"
  local id customer protocol tag port host url_host_value client_dir out
  local outbound_url info_text
  id="$(jq -r '.id' <<<"$node_json")"
  customer="$(jq -r '.customer' <<<"$node_json")"
  protocol="$(jq -r '.protocol' <<<"$node_json")"
  tag="$(jq -r '.tag' <<<"$node_json")"
  port="$(jq -r '.port' <<<"$node_json")"
  client_dir="$(client_dir_for "$id")"
  mkdir -p "$client_dir"
  chmod 700 "$client_dir"
  [[ "$protocol" == "direct" ]] && return 0

  host="$(server_host)"
  url_host_value="$(url_host "$host")"
  out="$client_dir/sing-box.json"
  outbound_url="$client_dir/url.txt"
  info_text="$client_dir/info.txt"

  jq '{outbounds:[
    if .protocol == "snell5" then
      {type:"snell", server:$host, server_port:.port,
       tcp_fast_open:true, reuse:true, version:4, psk:.psk}
      + (if (.obfs_mode // "none") == "http" then {obfs_mode:"http"} else {} end)
    elif .protocol == "snell6" then
      {type:"snell", server:$host, server_port:.port,
       tcp_fast_open:true, reuse:true, version:6, psk:.psk}
      + (if (.mode // "default") != "default" then {mode:.mode} else {} end)
    elif .protocol == "anytls" then
      {type:"anytls", server:$host, server_port:.port, password:.password,
       tls:{enabled:true, server_name:.server_name, utls:{enabled:true},
            reality:{enabled:true, public_key:.public_key, short_id:.short_id}}}
    elif .protocol == "vless" then
      {type:"vless", server:$host, server_port:.port, uuid:.uuid,
       flow:"xtls-rprx-vision",
       tls:{enabled:true, server_name:.server_name, utls:{enabled:true},
            reality:{enabled:true, public_key:.public_key, short_id:.short_id}}}
    elif .protocol == "hy2" then
      {type:"hysteria2", server:$host, server_port:.port, password:.password,
       tls:{enabled:true, server_name:.server_name, insecure:true}}
      + (if (.obfs // "") != "" then
           {obfs:{type:.obfs,password:.obfs_password}}
         else {} end)
    else empty end
  ]}' --arg host "$host" <<<"$node_json" > "$out"
  chmod 600 "$out"
  if [[ "${SBOX_SKIP_SING_BOX_CHECK:-0}" != "1" ]]; then
    resolve_sing_box
    "$SING_BOX_BIN" check -c "$out" >/dev/null
  fi

  case "$protocol" in
    snell5)
      printf 'snell://%s@%s:%s?version=5&obfs=%s&tfo=true&reuse=true#%s\n' \
        "$(url_encode "$(jq -r '.psk' <<<"$node_json")")" \
        "$url_host_value" "$port" \
        "$(jq -r '.obfs_mode // "none"' <<<"$node_json")" "$tag" > "$outbound_url"
      ;;
    snell6)
      printf 'snell://%s@%s:%s?version=6&mode=%s&tfo=true&reuse=true#%s\n' \
        "$(url_encode "$(jq -r '.psk' <<<"$node_json")")" \
        "$url_host_value" "$port" \
        "$(jq -r '.mode // "default"' <<<"$node_json")" "$tag" > "$outbound_url"
      ;;
    anytls)
      printf 'anytls://%s@%s:%s?security=reality&sni=%s&pbk=%s&sid=%s#%s\n' \
        "$(url_encode "$(jq -r '.password' <<<"$node_json")")" \
        "$url_host_value" "$port" \
        "$(url_encode "$(jq -r '.server_name' <<<"$node_json")")" \
        "$(url_encode "$(jq -r '.public_key' <<<"$node_json")")" \
        "$(url_encode "$(jq -r '.short_id' <<<"$node_json")")" "$tag" > "$outbound_url"
      ;;
    vless)
      printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp#%s\n' \
        "$(jq -r '.uuid' <<<"$node_json")" "$url_host_value" "$port" \
        "$(url_encode "$(jq -r '.server_name' <<<"$node_json")")" \
        "$(url_encode "$(jq -r '.public_key' <<<"$node_json")")" \
        "$(url_encode "$(jq -r '.short_id' <<<"$node_json")")" "$tag" > "$outbound_url"
      ;;
    hy2)
      printf 'hysteria2://%s@%s:%s/?insecure=1&sni=%s#%s\n' \
        "$(url_encode "$(jq -r '.password' <<<"$node_json")")" \
        "$url_host_value" "$port" \
        "$(url_encode "$(jq -r '.server_name' <<<"$node_json")")" "$tag" > "$outbound_url"
      ;;
  esac
  chmod 600 "$outbound_url"

  case "$protocol" in
    snell5)
      printf 'Snell=snell,%s,%s,psk="%s",version=5,tfo=true,reuse=true\n' \
        "$url_host_value" "$port" "$(jq -r '.psk' <<<"$node_json")" > "$client_dir/surge.conf"
      ;;
    snell6)
      printf 'Snell=snell,%s,%s,psk="%s",version=6,mode=%s,tfo=true,reuse=true\n' \
        "$url_host_value" "$port" "$(jq -r '.psk' <<<"$node_json")" \
        "$(jq -r '.mode // "default"' <<<"$node_json")" > "$client_dir/surge.conf"
      ;;
    hy2)
      printf 'HY2=hysteria2,%s,%s,password="%s",sni="%s",skip-cert-verify=true,tfo=false\n' \
        "$url_host_value" "$port" "$(jq -r '.password' <<<"$node_json")" \
        "$(jq -r '.server_name' <<<"$node_json")" > "$client_dir/surge.conf"
      ;;
  esac
  [[ -f "$client_dir/surge.conf" ]] && chmod 600 "$client_dir/surge.conf"

  {
    printf '节点：%s\n客户：%s\n协议：%s\n标签：%s\n' "$id" "$customer" "$protocol" "$tag"
    printf '服务器：%s\n端口：%s\n' "$host" "$port"
    printf '\n客户端配置：%s\n分享链接：%s\n' "$out" "$outbound_url"
  } > "$info_text"
  chmod 600 "$info_text"
}

cmd_node_add() {
  local id="${1:-}" protocol="${2:-}"
  local customer="" port="auto" quota="0" reset_day="1" expires=""
  local tag="" server_name="www.apple.com" target_address="" target_port=""
  local obfs_mode="none" snell6_mode="default" hy2_obfs=""
  local keypair private_key public_key uuid
  local client_dir cert_path key_path tmp_nodes tmp_config node_json
  shift 2 || die "用法：sbox-node node add ID snell5|snell6|anytls|vless|hy2|direct [选项]"
  [[ -n "$id" && -n "$protocol" ]] || die "node add 需要 ID 和协议"
  validate_id "$id" || die "ID 只能包含字母、数字、点、下划线和连字符"
  customer="$id"
  while (( $# )); do
    case "$1" in
      --customer) customer="${2:-}"; shift 2 ;;
      --port) port="${2:-}"; shift 2 ;;
      --quota) quota="${2:-}"; shift 2 ;;
      --reset-day) reset_day="${2:-}"; shift 2 ;;
      --expires) expires="${2:-}"; shift 2 ;;
      --tag) tag="${2:-}"; shift 2 ;;
      --name) tag="${2:-}"; shift 2 ;;
      --server-name) server_name="${2:-}"; shift 2 ;;
      --snell5-obfs) obfs_mode="${2:-}"; shift 2 ;;
      --snell6-mode) snell6_mode="${2:-}"; shift 2 ;;
      --obfs) hy2_obfs="${2:-}"; shift 2 ;;
      --target) target_address="${2:-}"; shift 2 ;;
      --target-port) target_port="${2:-}"; shift 2 ;;
      --no-restart) export SBOX_NO_RESTART=1; shift ;;
      *) die "未知选项：$1" ;;
    esac
  done
  validate_id "$customer" || die "客户 ID 格式无效"
  validate_reset_day "$reset_day" || die "重置日必须是 1-28"
  quota="$(size_to_bytes "$quota")" || die "额度格式无效，例如 100G"
  if [[ "$port" == "auto" ]]; then
    port="$(pick_free_port)"
  fi
  validate_port "$port" || die "端口无效：$port"
  port_in_config "$port" && die "端口 $port 已被现有入站占用"
  jq -e --argjson p "$port" '[.nodes[] | select(.port == $p)] | length == 0' \
    "$NODES_FILE" >/dev/null || die "端口 $port 已被管理节点占用"
  node_exists "$id" && die "节点 ID 已存在：$id"
  [[ -n "$tag" ]] || tag="$(node_tag_for "$protocol" "$id")"
  [[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
    || die "tag 只能包含字母、数字、点、下划线和连字符"
  jq -e --arg tag "$tag" '[.nodes[] | select(.tag == $tag)] | length == 0' \
    "$NODES_FILE" >/dev/null || die "tag 已存在：$tag"
  client_dir="$(client_dir_for "$id")"
  mkdir -p "$client_dir"
  chmod 700 "$client_dir"
  node_json="$(jq -n \
    --arg id "$id" --arg customer "$customer" --arg protocol "$protocol" \
    --arg tag "$tag" --argjson port "$port" \
    --arg transport "$(transport_for "$protocol")" \
    --argjson quota "$quota" --argjson reset_day "$reset_day" \
    --argjson expires "$(parse_expiry_epoch "$expires")" '
      {id:$id, customer:$customer, protocol:$protocol, tag:$tag,
       port:$port, transport:$transport, enabled:true, manual_pause:false,
       quota_bytes:$quota, reset_day:$reset_day, expires_at:$expires,
       created_at:(now | floor), updated_at:(now | floor)}
    ')"

  case "$protocol" in
    snell5)
      [[ "$obfs_mode" == "none" || "$obfs_mode" == "http" ]] \
        || die "Snell v5 obfs 只能是 none 或 http"
      node_json="$(jq --arg psk "$(openssl rand -base64 32 | tr -d '\n')" \
        --arg obfs "$obfs_mode" '. + {psk:$psk, obfs_mode:$obfs}' <<<"$node_json")"
      ;;
    snell6)
      [[ "$snell6_mode" == "default" || "$snell6_mode" == "unshaped" || "$snell6_mode" == "unsafe-raw" ]] \
        || die "Snell v6 mode 无效"
      node_json="$(jq --arg psk "$(openssl rand -base64 32 | tr -d '\n')" \
        --arg mode "$snell6_mode" '. + {psk:$psk, mode:$mode}' <<<"$node_json")"
      ;;
    anytls)
      keypair="$(generate_reality_keypair)"
      private_key="$(awk -F': ' '/PrivateKey/ {print $2}' <<<"$keypair")"
      public_key="$(awk -F': ' '/PublicKey/ {print $2}' <<<"$keypair")"
      node_json="$(jq --arg password "$(openssl rand -base64 32 | tr -d '\n')" \
        --arg private "$private_key" --arg public "$public_key" \
        --arg short "$(openssl rand -hex 8)" --arg sni "$server_name" \
        '. + {password:$password, private_key:$private, public_key:$public,
              short_id:$short, server_name:$sni}' <<<"$node_json")"
      ;;
    vless)
      resolve_sing_box
      keypair="$(generate_reality_keypair)"
      private_key="$(awk -F': ' '/PrivateKey/ {print $2}' <<<"$keypair")"
      public_key="$(awk -F': ' '/PublicKey/ {print $2}' <<<"$keypair")"
      uuid="$("$SING_BOX_BIN" generate uuid)"
      node_json="$(jq --arg uuid "$uuid" --arg private "$private_key" \
        --arg public "$public_key" --arg short "$(openssl rand -hex 8)" \
        --arg sni "$server_name" \
        '. + {uuid:$uuid, private_key:$private, public_key:$public,
              short_id:$short, server_name:$sni}' <<<"$node_json")"
      ;;
    hy2)
      cert_path="$client_dir/cert.pem"
      key_path="$client_dir/key.pem"
      openssl req -x509 -nodes \
        -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -keyout "$key_path" -out "$cert_path" \
        -subj "/CN=$server_name" \
        -addext "subjectAltName=DNS:$server_name" >/dev/null 2>&1 \
        || die "生成 Hysteria2 证书失败"
      node_json="$(jq --arg password "$(openssl rand -hex 32)" \
        --arg cert "$cert_path" --arg key "$key_path" --arg sni "$server_name" \
        --arg obfs "$hy2_obfs" \
        '. + {password:$password, cert_path:$cert, key_path:$key,
              server_name:$sni, obfs:$obfs, obfs_password:""}
        ' <<<"$node_json")"
      if [[ -n "$hy2_obfs" ]]; then
        node_json="$(jq --arg password "$(openssl rand -hex 16)" \
          '. + {obfs_password:$password}' <<<"$node_json")"
      fi
      ;;
    direct)
      [[ -n "$target_address" ]] && validate_port "$target_port" \
        || die "Direct 节点需要 --target 和 --target-port"
      node_json="$(jq --arg address "$target_address" --argjson target_port "$target_port" \
        '. + {target_address:$address, target_port:$target_port}' <<<"$node_json")"
      ;;
    *) die "不支持的协议：$protocol" ;;
  esac

  [[ "$protocol" == "direct" ]] || server_host >/dev/null
  tmp_nodes="$(mktemp)"
  tmp_config="$(mktemp)"
  jq --argjson node "$node_json" '.nodes += [$node]' "$NODES_FILE" > "$tmp_nodes"
  render_server_config "$tmp_nodes" "$tmp_config"
  commit_nodes_and_config "$tmp_nodes" "$tmp_config"
  init_traffic_entry "$id"
  if ! write_client_files "$(node_json_by_id "$id")"; then
    warn "节点已创建，但客户端文件生成失败；稍后运行 sbox-node node clients $id"
  fi
  cmd_traffic_ensure_rules "$id" >/dev/null 2>&1 || true
  ensure_traffic_timer
  cmd_traffic_check_once
  info "节点已创建：$id"
  info "客户：$customer"
  info "协议：$protocol"
  info "端口：$port"
  info "客户端目录：$(client_dir_for "$id")"
  info "额度：$(format_bytes "$quota")"
  info "到期：$(format_time "$(jq -r '.expires_at' <<<"$node_json")")"
}

cmd_node_list() {
  init_state
  jq -r '
    .nodes[] |
    [
      .id,
      .customer,
      .protocol,
      (.port | tostring),
      (if .quota_bytes > 0 then (.quota_bytes | tostring) else "unlimited" end),
      (if .expires_at > 0 then (.expires_at | tostring) else "-" end),
      (if .enabled then "enabled" else "disabled" end)
    ] | @tsv
  ' "$NODES_FILE" | awk -F '\t' '
    BEGIN {
      printf "%-20s %-16s %-10s %-7s %-12s %-20s %s\n",
             "NODE", "CUSTOMER", "PROTOCOL", "PORT", "QUOTA", "EXPIRES_EPOCH", "STATE"
    }
    {
      printf "%-20s %-16s %-10s %-7s %-12s %-20s %s\n",
             $1, $2, $3, $4, $5, $6, $7
    }
  '
}

cmd_node_show() {
  local id="${1:-}"
  node_exists "$id" || die "节点不存在：$id"
  jq --arg id "$id" '.nodes[] | select(.id == $id)' "$NODES_FILE"
  printf '\n客户端目录：%s\n' "$(client_dir_for "$id")"
}

cmd_node_clients() {
  local id="${1:-}"
  node_exists "$id" || die "节点不存在：$id"
  write_client_files "$(node_json_by_id "$id")"
  info "客户端文件已生成：$(client_dir_for "$id")"
}

cmd_node_disable() {
  local id="${1:-}" tmp
  node_exists "$id" || die "节点不存在：$id"
  tmp="$(mktemp)"
  jq --arg id "$id" '(.nodes[] | select(.id == $id) | .enabled) = false
    | (.nodes[] | select(.id == $id) | .updated_at) = (now | floor)' "$NODES_FILE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$NODES_FILE"
  cmd_traffic_check_once
  info "节点已禁用：$id"
}

cmd_node_enable() {
  local id="${1:-}" tmp
  node_exists "$id" || die "节点不存在：$id"
  tmp="$(mktemp)"
  jq --arg id "$id" '(.nodes[] | select(.id == $id) | .enabled) = true
    | (.nodes[] | select(.id == $id) | .updated_at) = (now | floor)' "$NODES_FILE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$NODES_FILE"
  cmd_traffic_check_once
  info "节点已启用：$id"
}

cmd_node_set_port() {
  local id="${1:-}" port="${2:-}" node_json old_port tmp_nodes tmp_config
  node_exists "$id" || die "节点不存在：$id"
  validate_port "$port" || die "端口无效：$port"
  node_json="$(node_json_by_id "$id")"
  old_port="$(jq -r '.port' <<<"$node_json")"
  [[ "$port" == "$old_port" ]] && { info "端口未变化：$port"; return 0; }
  port_in_config "$port" && die "端口 $port 已被现有入站占用"
  jq -e --arg id "$id" --argjson p "$port" '
    [.nodes[] | select(.id != $id and .port == $p)] | length == 0
  ' "$NODES_FILE" >/dev/null || die "端口 $port 已被其他管理节点占用"
  tmp_nodes="$(mktemp)"
  tmp_config="$(mktemp)"
  jq --arg id "$id" --argjson port "$port" '
    .nodes |= map(if .id == $id then . + {port:$port, updated_at:(now | floor)} else . end)
  ' "$NODES_FILE" > "$tmp_nodes"
  render_server_config "$tmp_nodes" "$tmp_config"
  cmd_traffic_unblock "$id" >/dev/null 2>&1 || true
  cmd_traffic_remove_rules "$id" >/dev/null 2>&1 || true
  commit_nodes_and_config "$tmp_nodes" "$tmp_config"
  set_traffic_state "$id" last_counter_bytes 0
  if ! write_client_files "$(node_json_by_id "$id")"; then
    warn "端口已修改，但客户端文件生成失败；运行 sbox-node node clients $id"
  fi
  cmd_traffic_check_once
  info "节点端口已修改：$id $old_port -> $port"
}

cmd_node_remove() {
  local id="${1:-}" node_json tag client_dir tmp_nodes tmp_config
  node_exists "$id" || die "节点不存在：$id"
  node_json="$(node_json_by_id "$id")"
  tag="$(jq -r '.tag' <<<"$node_json")"
  client_dir="$(client_dir_for "$id")"
  cmd_traffic_unblock "$id" >/dev/null 2>&1 || true
  cmd_traffic_remove_rules "$id" >/dev/null 2>&1 || true
  tmp_nodes="$(mktemp)"
  tmp_config="$(mktemp)"
  jq --arg id "$id" '.nodes = [.nodes[] | select(.id != $id)]' "$NODES_FILE" > "$tmp_nodes"
  render_server_config "$tmp_nodes" "$tmp_config"
  commit_nodes_and_config "$tmp_nodes" "$tmp_config"
  jq --arg id "$id" 'del(.[$id])' "$TRAFFIC_STATE" > "${TRAFFIC_STATE}.tmp"
  atomic_json_from_tmp "${TRAFFIC_STATE}.tmp" "$TRAFFIC_STATE"
  rm -rf -- "$client_dir"
  info "节点已删除：$id（tag: $tag）"
}

init_traffic_entry() {
  local id="$1" tmp
  [[ -s "$TRAFFIC_STATE" ]] || printf '{}\n' > "$TRAFFIC_STATE"
  tmp="$(mktemp)"
  jq --arg id "$id" --arg month "$(date +%Y-%m)" '
    if .[$id] == null then
      .[$id] = {
        used_bytes: 0,
        last_counter_bytes: 0,
        last_check: null,
        last_reset: $month,
        paused_reasons: [],
        notified: {}
      }
    else . end
  ' "$TRAFFIC_STATE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$TRAFFIC_STATE"
}

iptables_cmd_for() {
  case "$1" in
    ipv4)
      command -v iptables >/dev/null 2>&1 || return 1
      command -v iptables
      ;;
    ipv6)
      command -v ip6tables >/dev/null 2>&1 || return 1
      command -v ip6tables
      ;;
  esac
}

ensure_accounting_chain() {
  local family="$1" ipt
  ipt="$(iptables_cmd_for "$family")" || return 0
  "$ipt" -t mangle -N "$TRAFFIC_CHAIN" 2>/dev/null || true
  "$ipt" -t mangle -C PREROUTING -j "$TRAFFIC_CHAIN" 2>/dev/null \
    || "$ipt" -t mangle -I PREROUTING 1 -j "$TRAFFIC_CHAIN"
  "$ipt" -t mangle -C POSTROUTING -j "$TRAFFIC_CHAIN" 2>/dev/null \
    || "$ipt" -t mangle -I POSTROUTING 1 -j "$TRAFFIC_CHAIN"
}

node_protocols() {
  case "$1" in
    tcp) printf 'tcp' ;;
    udp) printf 'udp' ;;
    "tcp udp") printf 'tcp udp' ;;
  esac
}

cmd_traffic_ensure_rules() {
  local id="${1:-}" node_json port transport proto family ipt
  node_json="$(node_json_by_id "$id")" || die "节点不存在：$id"
  port="$(jq -r '.port' <<<"$node_json")"
  transport="$(jq -r '.transport' <<<"$node_json")"
  ensure_accounting_chain ipv4
  ensure_accounting_chain ipv6
  for family in ipv4 ipv6; do
    ipt="$(iptables_cmd_for "$family")" || continue
    for proto in $(node_protocols "$transport"); do
      "$ipt" -t mangle -C "$TRAFFIC_CHAIN" -p "$proto" --dport "$port" \
        -m comment --comment "sbox-in-$id" -j RETURN 2>/dev/null \
        || "$ipt" -t mangle -A "$TRAFFIC_CHAIN" -p "$proto" --dport "$port" \
          -m comment --comment "sbox-in-$id" -j RETURN
      "$ipt" -t mangle -C "$TRAFFIC_CHAIN" -p "$proto" --sport "$port" \
        -m comment --comment "sbox-out-$id" -j RETURN 2>/dev/null \
        || "$ipt" -t mangle -A "$TRAFFIC_CHAIN" -p "$proto" --sport "$port" \
          -m comment --comment "sbox-out-$id" -j RETURN
    done
  done
}

cmd_traffic_remove_rules() {
  local id="${1:-}" node_json port transport proto family ipt
  node_json="$(node_json_by_id "$id" 2>/dev/null)" || return 0
  [[ -n "$node_json" ]] || return 0
  port="$(jq -r '.port' <<<"$node_json")"
  transport="$(jq -r '.transport' <<<"$node_json")"
  for family in ipv4 ipv6; do
    ipt="$(iptables_cmd_for "$family")" || continue
    for proto in $(node_protocols "$transport"); do
      for _ in {1..20}; do
        "$ipt" -t mangle -D "$TRAFFIC_CHAIN" -p "$proto" --dport "$port" \
          -m comment --comment "sbox-in-$id" -j RETURN 2>/dev/null || break
      done
      for _ in {1..20}; do
        "$ipt" -t mangle -D "$TRAFFIC_CHAIN" -p "$proto" --sport "$port" \
          -m comment --comment "sbox-out-$id" -j RETURN 2>/dev/null || break
      done
    done
  done
}

traffic_current_bytes() {
  local id="$1" total=0 family ipt listing value
  if [[ -n "${SBOX_COUNTER_OVERRIDE_FILE:-}" && -s "${SBOX_COUNTER_OVERRIDE_FILE}" ]]; then
    jq -r --arg id "$id" '.[$id] // 0' "$SBOX_COUNTER_OVERRIDE_FILE"
    return 0
  fi
  for family in ipv4 ipv6; do
    ipt="$(iptables_cmd_for "$family")" || continue
    listing="$("$ipt" -t mangle -nvxL "$TRAFFIC_CHAIN" 2>/dev/null || true)"
    value="$(awk -v id="$id" '
      index($0, "sbox-in-" id " ") || index($0, "sbox-out-" id " ") { total += $2 }
      END { printf "%.0f\n", total + 0 }
    ' <<<"$listing")"
    total=$(( total + value ))
  done
  printf '%s' "$total"
}

cmd_traffic_block() {
  local id="${1:-}" node_json port transport proto family ipt udp_reject
  node_json="$(node_json_by_id "$id")" || return 1
  port="$(jq -r '.port' <<<"$node_json")"
  transport="$(jq -r '.transport' <<<"$node_json")"
  for family in ipv4 ipv6; do
    ipt="$(iptables_cmd_for "$family")" || continue
    if [[ "$family" == "ipv6" ]]; then
      udp_reject="icmp6-port-unreachable"
    else
      udp_reject="icmp-port-unreachable"
    fi
    for proto in $(node_protocols "$transport"); do
      if [[ "$proto" == "tcp" ]]; then
        "$ipt" -C INPUT -p tcp --dport "$port" \
          -m comment --comment "sbox-pause-$id" \
          -j REJECT --reject-with tcp-reset 2>/dev/null \
          || "$ipt" -I INPUT 1 -p tcp --dport "$port" \
            -m comment --comment "sbox-pause-$id" \
            -j REJECT --reject-with tcp-reset
      else
        "$ipt" -C INPUT -p udp --dport "$port" \
          -m comment --comment "sbox-pause-$id" \
          -j REJECT --reject-with "$udp_reject" 2>/dev/null \
          || "$ipt" -I INPUT 1 -p udp --dport "$port" \
            -m comment --comment "sbox-pause-$id" \
            -j REJECT --reject-with "$udp_reject" 2>/dev/null || true
      fi
    done
  done
  ss -K "sport = :$port" >/dev/null 2>&1 || true
  if command -v conntrack >/dev/null 2>&1; then
    for proto in $(node_protocols "$transport"); do
      conntrack -D -p "$proto" --dport "$port" >/dev/null 2>&1 || true
    done
  fi
}

cmd_traffic_unblock() {
  local id="${1:-}" node_json port transport proto family ipt udp_reject
  node_json="$(node_json_by_id "$id" 2>/dev/null)" || return 1
  [[ -n "$node_json" ]] || return 1
  port="$(jq -r '.port' <<<"$node_json")"
  transport="$(jq -r '.transport' <<<"$node_json")"
  for family in ipv4 ipv6; do
    ipt="$(iptables_cmd_for "$family")" || continue
    if [[ "$family" == "ipv6" ]]; then
      udp_reject="icmp6-port-unreachable"
    else
      udp_reject="icmp-port-unreachable"
    fi
    for proto in $(node_protocols "$transport"); do
      if [[ "$proto" == "tcp" ]]; then
        for _ in {1..20}; do
          "$ipt" -D INPUT -p tcp --dport "$port" \
            -m comment --comment "sbox-pause-$id" \
            -j REJECT --reject-with tcp-reset 2>/dev/null || break
        done
      else
        for _ in {1..20}; do
          "$ipt" -D INPUT -p udp --dport "$port" \
            -m comment --comment "sbox-pause-$id" \
            -j REJECT --reject-with "$udp_reject" 2>/dev/null || break
        done
      fi
    done
  done
}

traffic_state_field() {
  local id="$1" field="$2"
  jq -r --arg id "$id" --arg field "$field" '.[$id][$field] // ""' "$TRAFFIC_STATE"
}

set_traffic_state() {
  local id="$1" field="$2" json_value="$3" tmp
  tmp="$(mktemp)"
  jq --arg id "$id" --arg field "$field" --argjson value "$json_value" \
    '.[$id][$field] = $value' "$TRAFFIC_STATE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$TRAFFIC_STATE"
}

notify_setup() {
  local token="${1:-}" chat="${2:-}" tmp
  [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || die "Telegram Bot Token 格式无效"
  [[ "$chat" =~ ^-?[0-9]+(,-?[0-9]+)*$ ]] || die "Telegram Chat ID 格式无效"
  mkdir -p "$STATE_DIR"
  tmp="$(mktemp)"
  {
    printf 'TG_BOT_TOKEN=%q\n' "$token"
    printf 'TG_CHAT_ID=%q\n' "$chat"
  } > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$NOTIFY_ENV"
  info "Telegram 通知配置已保存"
}

notify_send() {
  local text="$1" chat response failed=0
  local -a chats
  [[ -s "$NOTIFY_ENV" ]] || return 1
  # shellcheck disable=SC1090
  source "$NOTIFY_ENV" || return 1
  [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" ]] || return 1
  if [[ -n "${SBOX_NOTIFY_DRY_RUN_FILE:-}" ]]; then
    printf '%s\n' "$text" >> "$SBOX_NOTIFY_DRY_RUN_FILE"
    return 0
  fi
  IFS=',' read -r -a chats <<< "$TG_CHAT_ID"
  for chat in "${chats[@]}"; do
    response="$(curl -fsS --max-time 12 \
      --data-urlencode "chat_id=$chat" \
      --data-urlencode "text=$text" \
      "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" 2>/dev/null || true)"
    if ! jq -e '.ok == true' <<<"${response:-{}}" >/dev/null 2>&1; then
      warn "Telegram 通知发送失败（chat_id=$chat）"
      failed=1
    fi
  done
  return "$failed"
}

notify_node() {
  local node_json="$1" message="$2"
  notify_send "[sbox-reality]
客户：$(jq -r '.customer' <<<"$node_json")
节点：$(jq -r '.id' <<<"$node_json")
协议：$(jq -r '.protocol' <<<"$node_json")
端口：$(jq -r '.port' <<<"$node_json")
$message"
}

cmd_traffic_check_once() {
  local now now_month current_day node_json id current used last delta
  local quota reset_day expires reason_json reason_string prior_string
  local month_key node_enabled manual_pause warn80 warn100 expiry_key
  local local_days remaining
  init_state
  now="$(date +%s)"
  now_month="$(date +%Y-%m)"
  current_day="$(date +%d)"
  while IFS= read -r node_json; do
    [[ -n "$node_json" ]] || continue
    id="$(jq -r '.id' <<<"$node_json")"
    init_traffic_entry "$id"
    cmd_traffic_ensure_rules "$id"
    current="$(traffic_current_bytes "$id")"
    last="$(traffic_state_field "$id" last_counter_bytes)"; last="${last:-0}"
    used="$(traffic_state_field "$id" used_bytes)"; used="${used:-0}"
    if (( current >= last )); then delta=$(( current - last )); else delta="$current"; fi
    used=$(( used + delta ))
    reset_day="$(jq -r '.reset_day // 1' <<<"$node_json")"
    month_key="$(traffic_state_field "$id" last_reset)"
    if (( 10#$current_day >= 10#$reset_day )) && [[ "$month_key" != "$now_month" ]]; then
      used=0
      set_traffic_state "$id" last_reset "$(jq -n --arg m "$now_month" '$m')"
      set_traffic_state "$id" notified \
        "$(jq -c '.["quota80"] = false | .["quota100"] = false' <<<"$(traffic_state_field "$id" notified)")"
    fi

    quota="$(jq -r '.quota_bytes // 0' <<<"$node_json")"
    expires="$(jq -r '.expires_at // 0' <<<"$node_json")"
    node_enabled="$(jq -r '.enabled' <<<"$node_json")"
    manual_pause="$(jq -r '.manual_pause // false' <<<"$node_json")"
    reason_json='[]'
    [[ "$node_enabled" == "true" && "$manual_pause" != "true" ]] \
      || reason_json="$(jq -c '. + ["disabled"]' <<<"$reason_json")"
    (( quota > 0 && used >= quota )) \
      && reason_json="$(jq -c '. + ["quota"]' <<<"$reason_json")"
    (( expires > 0 && now >= expires )) \
      && reason_json="$(jq -c '. + ["expiry"]' <<<"$reason_json")"
    prior_string="$(jq -r --arg id "$id" '.[$id].paused_reasons // [] | join(",")' "$TRAFFIC_STATE")"
    reason_string="$(jq -r 'join(",")' <<<"$reason_json")"

    set_traffic_state "$id" last_counter_bytes "$current"
    set_traffic_state "$id" used_bytes "$used"
    set_traffic_state "$id" last_check "$(jq -n --argjson n "$now" '$n')"
    set_traffic_state "$id" paused_reasons "$reason_json"

    if [[ -n "$reason_string" ]]; then
      cmd_traffic_block "$id"
    else
      cmd_traffic_unblock "$id"
    fi

    if (( quota > 0 )); then
      warn80="$(jq -r --arg id "$id" '.[$id].notified.quota80 // false' "$TRAFFIC_STATE")"
      warn100="$(jq -r --arg id "$id" '.[$id].notified.quota100 // false' "$TRAFFIC_STATE")"
      if (( used * 100 >= quota * 80 )) && [[ "$warn80" != "true" ]]; then
        if notify_node "$node_json" "流量已使用 $(format_bytes "$used") / $(format_bytes "$quota")，达到 80%。"; then
          set_traffic_state "$id" notified \
            "$(jq -c '.["quota80"] = true' <<<"$(traffic_state_field "$id" notified)")"
        fi
      fi
      if (( used >= quota )) && [[ "$warn100" != "true" ]]; then
        if notify_node "$node_json" "流量额度已用完：$(format_bytes "$used") / $(format_bytes "$quota")。节点已暂停。"; then
          set_traffic_state "$id" notified \
            "$(jq -c '.["quota100"] = true' <<<"$(traffic_state_field "$id" notified)")"
        fi
      fi
    fi

    if (( expires > 0 )); then
      remaining=$(( expires - now ))
      for local_days in 7 3 1; do
        expiry_key="expiry${local_days}d"
        if (( remaining > 0 && remaining <= local_days * 86400 )); then
          if [[ "$(jq -r --arg id "$id" --arg key "$expiry_key" '.[$id].notified[$key] // false' "$TRAFFIC_STATE")" != "true" ]]; then
            if notify_node "$node_json" "距离到期还有约 ${local_days} 天（$(format_time "$expires")）。"; then
              set_traffic_state "$id" notified \
                "$(jq -c --arg key "$expiry_key" '.[$key] = true' <<<"$(traffic_state_field "$id" notified)")"
            fi
          fi
        fi
      done
      if (( remaining <= 0 )) \
        && [[ "$(jq -r --arg id "$id" '.[$id].notified.expired // false' "$TRAFFIC_STATE")" != "true" ]]; then
        if notify_node "$node_json" "节点已到期（$(format_time "$expires")），端口已暂停。"; then
          set_traffic_state "$id" notified \
            "$(jq -c '.["expired"] = true' <<<"$(traffic_state_field "$id" notified)")"
        fi
      fi
    fi

    if [[ -n "$prior_string" && -z "$reason_string" ]]; then
      notify_node "$node_json" "节点限制已解除，端口恢复可用。"
    fi
  done < <(jq -c '.nodes[]' "$NODES_FILE")
}

cmd_traffic_set() {
  local id="${1:-}" tmp quota="" reset_day="" expires=""
  shift || true
  node_exists "$id" || die "节点不存在：$id"
  while (( $# )); do
    case "$1" in
      --quota) quota="${2:-}"; shift 2 ;;
      --reset-day) reset_day="${2:-}"; shift 2 ;;
      --expires) expires="${2:-}"; shift 2 ;;
      --no-expiry) expires="0"; shift ;;
      *) die "未知选项：$1" ;;
    esac
  done
  if [[ -n "$quota" ]]; then
    quota="$(size_to_bytes "$quota")" || die "额度格式无效，例如 100G"
  fi
  if [[ -n "$reset_day" ]]; then
    validate_reset_day "$reset_day" || die "重置日必须是 1-28"
  fi
  if [[ -n "$expires" ]]; then
    expires="$(parse_expiry_epoch "$expires")"
  fi
  tmp="$(mktemp)"
  jq --arg id "$id" \
    --arg quota "$quota" --arg reset_day "$reset_day" --arg expires "$expires" '
      .nodes |= map(
        if .id == $id then
          . +
          (if $quota != "" then {quota_bytes:($quota | tonumber)} else {} end) +
          (if $reset_day != "" then {reset_day:($reset_day | tonumber)} else {} end) +
          (if $expires != "" then {expires_at:($expires | tonumber)} else {} end) +
          {updated_at:(now | floor)}
        else . end
      )
    ' "$NODES_FILE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$NODES_FILE"
  init_traffic_entry "$id"
  if [[ -n "$expires" ]]; then
    set_traffic_state "$id" notified \
      "$(jq -c 'del(."expiry7d", ."expiry3d", ."expiry1d", ."expired")' <<<"$(traffic_state_field "$id" notified)")"
  fi
  ensure_traffic_timer
  cmd_traffic_check_once
  cmd_traffic_show "$id"
}

cmd_traffic_reset() {
  local id="${1:-}" current
  node_exists "$id" || die "节点不存在：$id"
  current="$(traffic_current_bytes "$id")"
  set_traffic_state "$id" used_bytes 0
  set_traffic_state "$id" last_counter_bytes "$current"
  set_traffic_state "$id" last_reset "$(jq -n --arg m "$(date +%Y-%m)" '$m')"
  set_traffic_state "$id" notified \
    "$(jq -c 'del(."quota80", ."quota100")' <<<"$(traffic_state_field "$id" notified)")"
  cmd_traffic_check_once
  info "流量统计已重置：$id"
}

cmd_traffic_unset() {
  local id="${1:-}" tmp
  node_exists "$id" || die "节点不存在：$id"
  cmd_traffic_unblock "$id" >/dev/null 2>&1 || true
  cmd_traffic_remove_rules "$id" >/dev/null 2>&1 || true
  tmp="$(mktemp)"
  jq --arg id "$id" '
    .nodes |= map(if .id == $id then . + {quota_bytes:0, expires_at:0} else . end)
  ' "$NODES_FILE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$NODES_FILE"
  tmp="$(mktemp)"
  jq --arg id "$id" 'del(.[$id])' "$TRAFFIC_STATE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$TRAFFIC_STATE"
  info "已移除节点限制：$id"
}

cmd_traffic_show() {
  local only="${1:-}"
  init_state
  jq -r --arg only "$only" '
    .nodes[] | select($only == "" or .id == $only) |
    .id as $id |
    [$id, .customer, (.port|tostring), (.quota_bytes|tostring),
     (.expires_at|tostring), (.enabled|tostring)]
    | @tsv
  ' "$NODES_FILE" | while IFS=$'\t' read -r id customer port quota expires enabled; do
    local used reasons
    used="$(traffic_state_field "$id" used_bytes)"; used="${used:-0}"
    reasons="$(jq -r --arg id "$id" '.[$id].paused_reasons // [] | join(",")' "$TRAFFIC_STATE")"
    printf '%-20s %-16s port=%-6s used=%-10s quota=%-10s expires=%-20s state=%s%s\n' \
      "$id" "$customer" "$port" "$(format_bytes "$used")" \
      "$(if (( quota > 0 )); then format_bytes "$quota"; else printf 'unlimited'; fi)" \
      "$(format_time "$expires")" \
      "$(if [[ "$enabled" != "true" || "$reasons" == *disabled* ]]; then printf 'disabled'; else printf 'enabled'; fi)" \
      "$(if [[ -n "$reasons" ]]; then printf ' paused=%s' "$reasons"; fi)"
  done
}

cmd_traffic_pause() {
  local id="${1:-}" tmp
  node_exists "$id" || die "节点不存在：$id"
  tmp="$(mktemp)"
  jq --arg id "$id" '(.nodes[] | select(.id == $id) | .manual_pause) = true' \
    "$NODES_FILE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$NODES_FILE"
  cmd_traffic_check_once
  info "节点已手动暂停：$id"
}

cmd_traffic_resume() {
  local id="${1:-}" tmp
  node_exists "$id" || die "节点不存在：$id"
  tmp="$(mktemp)"
  jq --arg id "$id" '(.nodes[] | select(.id == $id) | .manual_pause) = false' \
    "$NODES_FILE" > "$tmp"
  atomic_json_from_tmp "$tmp" "$NODES_FILE"
  cmd_traffic_check_once
  info "已取消手动暂停：$id"
}

ensure_traffic_timer() {
  [[ "${SBOX_MANAGER_TEST_MODE:-0}" == "1" ]] && return 0
  if [[ ! -x "$MANAGER_PATH" ]]; then
    install_manager >/dev/null
  fi
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    cat > /etc/systemd/system/sbox-traffic.service <<'EOF'
[Unit]
Description=sbox-reality per-node traffic guard
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sbox-node traffic check
EOF
    cat > /etc/systemd/system/sbox-traffic.timer <<'EOF'
[Unit]
Description=Run sbox-reality traffic guard every minute

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload
    systemctl enable --now sbox-traffic.timer >/dev/null 2>&1 || true
  else
    cat > /etc/init.d/sbox-traffic <<'EOF'
#!/sbin/openrc-run
description="sbox-reality per-node traffic guard"
command="/usr/local/sbin/sbox-node"
command_args="traffic daemon"
command_background=true
pidfile="/run/sbox-traffic.pid"
output_log="/var/log/sbox-traffic.log"
error_log="/var/log/sbox-traffic.log"
EOF
    chmod 755 /etc/init.d/sbox-traffic
    rc-update add sbox-traffic default >/dev/null 2>&1 || true
    rc-service sbox-traffic restart >/dev/null 2>&1 \
      || rc-service sbox-traffic start >/dev/null 2>&1 || true
  fi
}

traffic_daemon() {
  trap 'exit 0' INT TERM
  while true; do
    cmd_traffic_check_once >/dev/null 2>&1 || warn "流量检查失败"
    sleep 60
  done
}

cleanup_manager() {
  local purge="${1:-}" id family ipt
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    cmd_traffic_unblock "$id" >/dev/null 2>&1 || true
    cmd_traffic_remove_rules "$id" >/dev/null 2>&1 || true
  done < <(jq -r '.nodes[].id' "$NODES_FILE" 2>/dev/null || true)
  for family in ipv4 ipv6; do
    ipt="$(iptables_cmd_for "$family")" || continue
    for _ in {1..20}; do
      "$ipt" -t mangle -D PREROUTING -j "$TRAFFIC_CHAIN" >/dev/null 2>&1 || break
    done
    for _ in {1..20}; do
      "$ipt" -t mangle -D POSTROUTING -j "$TRAFFIC_CHAIN" >/dev/null 2>&1 || break
    done
    "$ipt" -t mangle -F "$TRAFFIC_CHAIN" >/dev/null 2>&1 || true
    "$ipt" -t mangle -X "$TRAFFIC_CHAIN" >/dev/null 2>&1 || true
  done
  if command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
    systemctl disable --now sbox-traffic.timer >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/sbox-traffic.service /etc/systemd/system/sbox-traffic.timer
    systemctl daemon-reload >/dev/null 2>&1 || true
  else
    rc-service sbox-traffic stop >/dev/null 2>&1 || true
    rc-update del sbox-traffic default >/dev/null 2>&1 || true
    rm -f /etc/init.d/sbox-traffic
  fi
  if [[ "$purge" == "--purge" ]]; then
    rm -rf -- "$STATE_DIR" "$CLIENTS_ROOT"
    rm -f "$MANAGER_PATH" "$MANAGER_ALIAS"
  fi
}

install_manager() {
  local source_path="${BASH_SOURCE[0]}"
  require_root
  [[ -f "$source_path" ]] || die "无法定位当前管理脚本"
  install -d -m 755 /usr/local/sbin
  install -m 755 "$source_path" "$MANAGER_PATH"
  ln -sfn "$MANAGER_PATH" "$MANAGER_ALIAS"
  info "已安装：$MANAGER_PATH"
  info "别名：$MANAGER_ALIAS"
}

cmd_node_migrate() {
  local inbounds tmp_nodes tmp_config found=0 public_key cert_subject cert_path
  init_state
  if (( $(jq '.nodes | length' "$NODES_FILE") > 0 )); then
    die "nodes.json 已包含节点；请先备份并清空后再迁移"
  fi
  [[ -s "$SERVER_CONF" ]] || die "服务端配置不存在"
  inbounds="$(jq -c '.inbounds // []' "$SERVER_CONF")"
  tmp_nodes="$(mktemp)"
  jq -n --argjson inbounds "$inbounds" '
    {
      schema:1,
      nodes:[
        $inbounds[] |
        if .tag == "snell5-in" then
          {id:"default-snell5", customer:"default", protocol:"snell5", tag:.tag,
           port:.listen_port, transport:"tcp", enabled:true, manual_pause:false,
           quota_bytes:0, reset_day:1, expires_at:0,
           psk:.psk, obfs_mode:(.obfs_mode // "none")}
        elif .tag == "snell6-in" then
          {id:"default-snell6", customer:"default", protocol:"snell6", tag:.tag,
           port:.listen_port, transport:"tcp", enabled:true, manual_pause:false,
           quota_bytes:0, reset_day:1, expires_at:0,
           psk:.psk, mode:(.mode // "default")}
        elif .tag == "anytls-in" then
          {id:"default-anytls", customer:"default", protocol:"anytls", tag:.tag,
           port:.listen_port, transport:"tcp", enabled:true, manual_pause:false,
           quota_bytes:0, reset_day:1, expires_at:0,
           password:.users[0].password, private_key:.tls.reality.private_key,
           public_key:null, short_id:.tls.reality.short_id[0],
           server_name:.tls.server_name}
        elif .tag == "vless-in" then
          {id:"default-vless", customer:"default", protocol:"vless", tag:.tag,
           port:.listen_port, transport:"tcp", enabled:true, manual_pause:false,
           quota_bytes:0, reset_day:1, expires_at:0,
           uuid:.users[0].uuid, private_key:.tls.reality.private_key,
           public_key:null, short_id:.tls.reality.short_id[0],
           server_name:.tls.server_name}
        elif .tag == "hy2-in" then
          {id:"default-hy2", customer:"default", protocol:"hy2", tag:.tag,
           port:.listen_port, transport:"udp", enabled:true, manual_pause:false,
           quota_bytes:0, reset_day:1, expires_at:0,
           password:.users[0].password, cert_path:.tls.certificate_path,
           key_path:.tls.key_path, server_name:"", obfs:(.obfs.type // ""),
           obfs_password:(.obfs.password // "")}
        elif .tag == "direct-in" then
          {id:"default-direct", customer:"default", protocol:"direct", tag:.tag,
           port:.listen_port, transport:"tcp udp", enabled:true, manual_pause:false,
           quota_bytes:0, reset_day:1, expires_at:0,
           target_address:.override_address, target_port:.override_port}
        else empty end
      ]
    }
  ' > "$tmp_nodes"

  if [[ -s /root/sing-box/anytls-sing-box.json ]]; then
    public_key="$(jq -r '.outbounds[0].tls.reality.public_key // empty' \
      /root/sing-box/anytls-sing-box.json 2>/dev/null || true)"
    if [[ -n "$public_key" ]]; then
      jq --arg key "$public_key" '
        (.nodes[] | select(.protocol == "anytls") | .public_key) = $key
      ' "$tmp_nodes" > "${tmp_nodes}.next"
      mv -f "${tmp_nodes}.next" "$tmp_nodes"
    fi
  fi
  if [[ -s /root/sing-box/vless-sing-box.json ]]; then
    public_key="$(jq -r '.outbounds[0].tls.reality.public_key // empty' \
      /root/sing-box/vless-sing-box.json 2>/dev/null || true)"
    if [[ -n "$public_key" ]]; then
      jq --arg key "$public_key" '
        (.nodes[] | select(.protocol == "vless") | .public_key) = $key
      ' "$tmp_nodes" > "${tmp_nodes}.next"
      mv -f "${tmp_nodes}.next" "$tmp_nodes"
    fi
  fi
  cert_path="$(jq -r '.nodes[] | select(.protocol == "hy2") | .cert_path // empty' "$tmp_nodes")"
  if [[ -n "$cert_path" && -f "$cert_path" && -x "$(command -v openssl || true)" ]]; then
    cert_subject="$(openssl x509 -in "$cert_path" -noout -subject 2>/dev/null || true)"
    cert_subject="${cert_subject#subject=}"
    cert_subject="${cert_subject#*CN=}"
    cert_subject="${cert_subject%%,*}"
    if [[ -n "$cert_subject" ]]; then
      jq --arg sni "$cert_subject" '
        (.nodes[] | select(.protocol == "hy2") | .server_name) = $sni
      ' "$tmp_nodes" > "${tmp_nodes}.next"
      mv -f "${tmp_nodes}.next" "$tmp_nodes"
    fi
  fi
  found="$(jq '.nodes | length' "$tmp_nodes")"
  (( found > 0 )) || die "没有找到可迁移的 Sbox Reality 入站"
  # REALITY public keys cannot be recovered from a private key with sing-box;
  # derive them by asking sing-box for a temporary pair only for fresh nodes.
  # Existing clients keep their original files, so migration never invents keys.
  tmp_config="$(mktemp)"
  render_server_config "$tmp_nodes" "$tmp_config"
  validate_candidate_config "$tmp_nodes" "$tmp_config"
  atomic_json_from_tmp "$tmp_nodes" "$NODES_FILE"
  rm -f "$tmp_config"
  while IFS= read -r node_json; do
    local id protocol
    id="$(jq -r '.id' <<<"$node_json")"
    protocol="$(jq -r '.protocol' <<<"$node_json")"
    init_traffic_entry "$id"
    if [[ "$protocol" == "anytls" || "$protocol" == "vless" ]]; then
      if [[ "$(jq -r '.public_key // empty' <<<"$node_json")" == "null" \
        || -z "$(jq -r '.public_key // empty' <<<"$node_json")" ]]; then
        warn "迁移节点 $id 缺少公钥，继续使用原 /root/sing-box 客户端文件"
      else
        write_client_files "$node_json" \
          || warn "迁移节点 $id 的客户端文件生成失败"
      fi
    elif [[ "$protocol" == "snell5" || "$protocol" == "snell6" ]]; then
      write_client_files "$node_json" \
        || warn "迁移节点 $id 的客户端文件生成失败"
    elif [[ "$protocol" == "hy2" && -n "$(jq -r '.server_name // empty' <<<"$node_json")" ]]; then
      write_client_files "$node_json" \
        || warn "迁移节点 $id 的客户端文件生成失败"
    fi
  done < <(jq -c '.nodes[]' "$NODES_FILE")
  info "已迁移 $found 个现有节点"
}

usage() {
  cat <<'EOF'
用法：
  sbox-node install
  sbox-node node add ID snell5|snell6|anytls|vless|hy2|direct [选项]
  sbox-node node list
  sbox-node node show ID
  sbox-node node clients ID
  sbox-node node port ID NEW_PORT
  sbox-node node disable|enable|remove ID
  sbox-node node migrate
  sbox-node traffic set ID [--quota 100G] [--reset-day 1] [--expires YYYY-MM-DD]
  sbox-node traffic show [ID]
  sbox-node traffic reset|pause|resume|unset ID
  sbox-node traffic check
  sbox-node traffic timer
  sbox-node notify setup TOKEN CHAT_ID
  sbox-node notify test
  sbox-node cleanup [--purge]

管理多个客户的独立节点；流量与到期限制只作用于目标端口。
EOF
}

main() {
  local action="${1:-}"
  shift || true
  case "$action" in
    install) install_manager ;;
    node)
      action="${1:-}"; shift || true
      acquire_lock
      init_state
      case "$action" in
        add) cmd_node_add "$@" ;;
        list) cmd_node_list ;;
        show) cmd_node_show "$@" ;;
        clients|regen) cmd_node_clients "$@" ;;
        port|set-port) cmd_node_set_port "$@" ;;
        disable) cmd_node_disable "$@" ;;
        enable) cmd_node_enable "$@" ;;
        remove|delete) cmd_node_remove "$@" ;;
        migrate|import-existing) cmd_node_migrate ;;
        *) usage; exit 2 ;;
      esac
      ;;
    traffic)
      action="${1:-}"; shift || true
      acquire_lock
      init_state
      case "$action" in
        set) cmd_traffic_set "$@" ;;
        show|list|status) cmd_traffic_show "$@" ;;
        reset) cmd_traffic_reset "$@" ;;
        pause) cmd_traffic_pause "$@" ;;
        resume) cmd_traffic_resume "$@" ;;
        unset|remove) cmd_traffic_unset "$@" ;;
        check) cmd_traffic_check_once ;;
        timer|install-timer) ensure_traffic_timer ;;
        daemon) traffic_daemon ;;
        *) usage; exit 2 ;;
      esac
      ;;
    notify)
      action="${1:-}"; shift || true
      case "$action" in
        setup) notify_setup "$@" ;;
        test)
          [[ -s "$NOTIFY_ENV" ]] || die "Telegram 通知尚未配置"
          notify_send "[sbox-reality] Telegram 通知测试成功 $(TZ="$TIMEZONE" date '+%Y-%m-%d %H:%M:%S')"
          info "测试通知已发送"
          ;;
        *) usage; exit 2 ;;
      esac
      ;;
    cleanup) cleanup_manager "${1:-}" ;;
    help|-h|--help|"") usage ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
