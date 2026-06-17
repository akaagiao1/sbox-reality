#!/usr/bin/env bash
set -euo pipefail

INSTALL_MODE="${INSTALL_MODE:-}"
SHARED_PORT="${PORT:-}"

REALITY_DOMAIN="${REALITY_DOMAIN:-${DOMAIN:-www.apple.com}}"
ANYTLS_PORT="${ANYTLS_PORT:-auto}"
HIGH_PORT_MIN="${HIGH_PORT_MIN:-20000}"
HIGH_PORT_MAX="${HIGH_PORT_MAX:-65535}"

HY2_SNI="${HY2_SNI:-${SNI:-www.bing.com}}"
HY2_PORT="${HY2_PORT:-auto}"
HOP_PORTS="${HOP_PORTS:-20000-50000}"
HOP_INTERVAL="${HOP_INTERVAL:-30}"
UP_MBPS="${UP_MBPS:-}"
DOWN_MBPS="${DOWN_MBPS:-}"
OBFS="${OBFS:-off}"
OBFS_PASSWORD="${OBFS_PASSWORD:-}"
PROXY_NAME="${PROXY_NAME:-HY2}"

SERVER_CONF="/etc/sing-box/config.json"
ANYTLS_CLIENT_OUT="/root/client-outbounds-anytls-reality.json"
HY2_CLIENT_OUT="/root/client-outbounds-hysteria2.json"
SURGE_CONF="/root/surge-hysteria2.conf"
HY2_URL_FILE="/root/hysteria2-url.txt"
ANYTLS_INFO="/root/anytls-reality-info.txt"
HY2_INFO="/root/hysteria2-surge-info.txt"
COMBINED_INFO="/root/sbox-reality-info.txt"

PORT_ENV="/etc/sing-box/hy2-port-hopping.env"
PORT_HELPER="/usr/local/bin/sing-box-hy2-port-hopping"
SYSTEMD_DROPIN="/etc/systemd/system/sing-box.service.d/10-hy2-port-hopping.conf"
DEFAULT_CERT_PATH="/etc/sing-box/hysteria2.crt"
DEFAULT_KEY_PATH="/etc/sing-box/hysteria2.key"
CERT_PATH="${CERT_PATH:-$DEFAULT_CERT_PATH}"
KEY_PATH="${KEY_PATH:-$DEFAULT_KEY_PATH}"

INSTALL_ANYTLS=0
INSTALL_HY2=0
ANYTLS_PORT_MODE=""
HY2_PORT_MODE=""
FIRST_HOP_PORT=""
NORMALIZED_HOP_PORTS=""
SERVER_PORTS_JSON=""
SERVER_IP=""

ANYTLS_PRIVATE_KEY=""
ANYTLS_PUBLIC_KEY=""
ANYTLS_PASSWORD=""
ANYTLS_SHORT_ID=""
HY2_PASSWORD=""
HY2_SHARE_URL=""

usage() {
  cat << USAGE
Usage:
  bash $0
  bash $0 --mode 1
  bash $0 --mode 2
  bash $0 --mode both

Install modes:
  1, anytls     Install AnyTLS + REALITY
  2, hy2        Install Hysteria2 + Surge port hopping
  3, both       Install both in the same sing-box config

AnyTLS + REALITY options:
  -d, --domain        REALITY handshake domain, default: www.apple.com
      --anytls-port   AnyTLS TCP listen port, default: auto

Hysteria2 + Surge options:
  -s, --sni           TLS SNI and self-signed certificate common name, default: www.bing.com
      --hy2-port      Hysteria2 UDP listen port, default: auto
  -P, --ports         Surge port-hopping ports/ranges, default: 20000-50000
  -i, --interval      Port hopping interval in seconds, minimum 5, default: 30
      --up            Server upload bandwidth in Mbps, optional
      --down          Server download bandwidth in Mbps, optional
      --obfs          Enable Hysteria2 Salamander obfuscation
      --obfs-password Salamander obfuscation password
      --cert          Existing TLS certificate path
      --key           Existing TLS key path
      --name          Surge proxy name, default: HY2

Shared:
  -m, --mode          Install mode: 1, 2, 3, anytls, hy2, both
  -p, --port          Port for mode 1 or mode 2. Use --anytls-port and --hy2-port for both mode
  -h, --help          Show help

Environment variables:
  INSTALL_MODE, PORT, REALITY_DOMAIN, DOMAIN, ANYTLS_PORT,
  HIGH_PORT_MIN, HIGH_PORT_MAX,
  HY2_SNI, SNI, HY2_PORT, HOP_PORTS, HOP_INTERVAL,
  UP_MBPS, DOWN_MBPS, OBFS, OBFS_PASSWORD, CERT_PATH, KEY_PATH, PROXY_NAME
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
    3|both|all)
      INSTALL_MODE="3"
      shift
      ;;
    -d|--domain|--reality-domain)
      REALITY_DOMAIN="${2:-}"
      shift 2
      ;;
    --anytls-port)
      ANYTLS_PORT="${2:-}"
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
      OBFS="on"
      shift
      ;;
    --obfs-password)
      OBFS="on"
      OBFS_PASSWORD="${2:-}"
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
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

choose_mode() {
  if [[ -n "$INSTALL_MODE" ]]; then
    return 0
  fi

  if [[ -t 0 ]]; then
    echo "Choose install mode:"
    echo "  1) AnyTLS + REALITY"
    echo "  2) Hysteria2 + Surge port hopping"
    echo "  3) Install both"
    echo
    read -rp "Select [1-3]: " INSTALL_MODE
  else
    echo "Error: install mode is required in non-interactive mode"
    echo "Example: bash $0 --mode both"
    exit 1
  fi
}

normalize_mode() {
  case "$INSTALL_MODE" in
    1|anytls|reality)
      INSTALL_ANYTLS=1
      ;;
    2|hy2|hysteria2|surge)
      INSTALL_HY2=1
      ;;
    3|both|all)
      INSTALL_ANYTLS=1
      INSTALL_HY2=1
      ;;
    *)
      echo "Error: invalid install mode: $INSTALL_MODE"
      usage
      exit 1
      ;;
  esac
}

apply_shared_port() {
  [[ -n "$SHARED_PORT" ]] || return 0

  if (( INSTALL_ANYTLS )); then
    ANYTLS_PORT="$SHARED_PORT"
  fi

  if (( INSTALL_HY2 )); then
    HY2_PORT="$SHARED_PORT"
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
    echo "Error: invalid high port range: ${HIGH_PORT_MIN}-${HIGH_PORT_MAX}" >&2
    exit 1
  fi

  for _ in $(seq 1 100); do
    candidate=$(( HIGH_PORT_MIN + $(random_number) % range ))
    if ! is_tcp_port_in_use "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  echo "Error: failed to find a free high TCP port in ${HIGH_PORT_MIN}-${HIGH_PORT_MAX}" >&2
  exit 1
}

normalize_hop_ports() {
  local -a specs
  local raw spec start end normalized sep first

  raw="${HOP_PORTS//[[:space:]]/}"
  raw="${raw//,/;}"

  if [[ -z "$raw" ]]; then
    echo "Error: Hysteria2 ports cannot be empty"
    exit 1
  fi

  IFS=';' read -r -a specs <<< "$raw"
  normalized=""
  sep=""
  first=""

  for spec in "${specs[@]}"; do
    if [[ -z "$spec" ]]; then
      echo "Error: invalid empty port item in: $HOP_PORTS"
      exit 1
    fi

    if [[ "$spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      start="${BASH_REMATCH[1]}"
      end="${BASH_REMATCH[2]}"
      if ! validate_port "$start" || ! validate_port "$end" || (( start > end )); then
        echo "Error: invalid port range: $spec"
        exit 1
      fi
      [[ -z "$first" ]] && first="$start"
    elif validate_port "$spec"; then
      [[ -z "$first" ]] && first="$spec"
    else
      echo "Error: invalid port item: $spec"
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
  [[ "$OBFS" == "on" ]] || return 0

  cat << JSON
      "obfs": {
        "type": "salamander",
        "password": "${OBFS_PASSWORD}"
      },
JSON
}

surge_extra_params() {
  local extra=""

  if [[ -n "$DOWN_MBPS" ]]; then
    extra="${extra}, download-bandwidth=${DOWN_MBPS}"
  fi

  if [[ "$OBFS" == "on" ]]; then
    extra="${extra}, salamander-password=${OBFS_PASSWORD}"
  fi

  printf '%s' "$extra"
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

  if [[ "$OBFS" == "on" ]]; then
    query="${query}&obfs=salamander&obfs-password=$(url_encode "$OBFS_PASSWORD")"
  fi

  HY2_SHARE_URL="hysteria2://$(url_encode "$HY2_PASSWORD")@${SERVER_IP}:${uri_ports}/?${query}#$(url_encode "$PROXY_NAME")"
}

prepare_certificate() {
  local san_type

  mkdir -p "$(dirname "$CERT_PATH")" "$(dirname "$KEY_PATH")"

  if [[ "$CERT_PATH" != "$DEFAULT_CERT_PATH" || "$KEY_PATH" != "$DEFAULT_KEY_PATH" ]]; then
    if [[ ! -f "$CERT_PATH" || ! -f "$KEY_PATH" ]]; then
      echo "Error: custom --cert and --key must both exist"
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
  mkdir -p /etc/sing-box "$(dirname "$PORT_HELPER")" "$(dirname "$SYSTEMD_DROPIN")"

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
    echo "Usage: $0 apply|clean" >&2
    exit 1
    ;;
esac
SH

  chmod +x "$PORT_HELPER"

  cat > "$SYSTEMD_DROPIN" << DROPIN
[Service]
ExecStartPre=+${PORT_HELPER} clean
ExecStartPre=+${PORT_HELPER} apply
ExecStopPost=+${PORT_HELPER} clean
DROPIN
}

disable_hy2_port_hopping() {
  if [[ -x "$PORT_HELPER" ]]; then
    "$PORT_HELPER" clean >/dev/null 2>&1 || true
  fi

  rm -f "$SYSTEMD_DROPIN" "$PORT_ENV"
}

prepare_inputs() {
  REALITY_DOMAIN="$(strip_host "$REALITY_DOMAIN")"
  HY2_SNI="$(strip_host "$HY2_SNI")"

  if (( INSTALL_ANYTLS )); then
    if [[ -z "$REALITY_DOMAIN" || "$REALITY_DOMAIN" =~ [[:space:]] ]]; then
      echo "Error: REALITY domain cannot be empty or contain whitespace"
      exit 1
    fi

    if [[ -z "$ANYTLS_PORT" || "$ANYTLS_PORT" == "auto" || "$ANYTLS_PORT" == "random" ]]; then
      ANYTLS_PORT="$(pick_random_free_high_tcp_port)"
      ANYTLS_PORT_MODE="random"
    elif validate_port "$ANYTLS_PORT"; then
      ANYTLS_PORT_MODE="manual"
    else
      echo "Error: invalid AnyTLS port: $ANYTLS_PORT"
      exit 1
    fi

    if is_tcp_port_in_use_by_other "$ANYTLS_PORT"; then
      echo "Error: TCP port $ANYTLS_PORT is already used by another process"
      ss -H -lntp 2>/dev/null | awk -v p="$ANYTLS_PORT" '$4 ~ ":" p "$" {print}' || true
      exit 1
    fi
  fi

  if (( INSTALL_HY2 )); then
    if [[ -z "$HY2_SNI" || "$HY2_SNI" =~ [[:space:]] ]]; then
      echo "Error: Hysteria2 SNI cannot be empty or contain whitespace"
      exit 1
    fi

    normalize_hop_ports
    build_server_ports_json

    if [[ -z "$HY2_PORT" || "$HY2_PORT" == "auto" || "$HY2_PORT" == "random" ]]; then
      HY2_PORT="$FIRST_HOP_PORT"
      HY2_PORT_MODE="first-hop-port"
    elif validate_port "$HY2_PORT"; then
      HY2_PORT_MODE="manual"
    else
      echo "Error: invalid Hysteria2 listen port: $HY2_PORT"
      exit 1
    fi

    if ! validate_positive_number "$HOP_INTERVAL" || (( HOP_INTERVAL < 5 )); then
      echo "Error: Hysteria2 interval must be an integer greater than or equal to 5"
      exit 1
    fi

    if [[ -n "$UP_MBPS" ]] && ! validate_positive_number "$UP_MBPS"; then
      echo "Error: --up must be a positive integer"
      exit 1
    fi

    if [[ -n "$DOWN_MBPS" ]] && ! validate_positive_number "$DOWN_MBPS"; then
      echo "Error: --down must be a positive integer"
      exit 1
    fi

    if [[ "$OBFS" != "on" && "$OBFS" != "off" ]]; then
      echo "Error: OBFS must be on or off"
      exit 1
    fi

    if ! validate_proxy_name; then
      echo "Error: proxy name may only contain letters, numbers, dot, underscore, and hyphen"
      exit 1
    fi

    if is_udp_port_in_use_by_other "$HY2_PORT"; then
      echo "Error: UDP port $HY2_PORT is already used by another process"
      ss -H -lunp 2>/dev/null | awk -v p="$HY2_PORT" '$4 ~ ":" p "$" {print}' || true
      exit 1
    fi
  fi
}

install_dependencies() {
  echo "Installing dependencies..."
  apt update
  apt install -y curl openssl ca-certificates iproute2 coreutils nftables iptables
  curl -fsSL https://sing-box.app/install.sh | sh
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
    echo "Error: failed to generate AnyTLS + REALITY keys"
    exit 1
  fi
}

generate_hy2_secrets() {
  if [[ "$OBFS" == "on" && -z "$OBFS_PASSWORD" ]]; then
    OBFS_PASSWORD="$(openssl rand -hex 16)"
  fi

  HY2_PASSWORD="$(openssl rand -hex 32)"
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

write_server_config() {
  local inbounds

  if (( INSTALL_ANYTLS && INSTALL_HY2 )); then
    inbounds="$(anytls_inbound_json),
$(hy2_inbound_json)"
  elif (( INSTALL_ANYTLS )); then
    inbounds="$(anytls_inbound_json)"
  else
    inbounds="$(hy2_inbound_json)"
  fi

  cp "$SERVER_CONF" "$SERVER_CONF.bak.$(date +%s)" 2>/dev/null || true

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

detect_server_ip() {
  SERVER_IP="$(curl -4 -s --max-time 8 https://api.ipify.org || true)"
  if [[ -z "$SERVER_IP" ]]; then
    SERVER_IP="your_vps_ip_or_domain"
  fi
}

write_anytls_client() {
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
}

write_hy2_clients() {
  build_hy2_share_url

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
${PROXY_NAME} = hysteria2, ${SERVER_IP}, ${HY2_PORT}, password=${HY2_PASSWORD}, skip-cert-verify=true, sni=${HY2_SNI}, port-hopping="${NORMALIZED_HOP_PORTS}", port-hopping-interval=${HOP_INTERVAL}$(surge_extra_params)

[Proxy Group]
Proxy = select, ${PROXY_NAME}, DIRECT
SURGE

  printf '%s\n' "$HY2_SHARE_URL" > "$HY2_URL_FILE"
}

write_info_files() {
  cat > "$COMBINED_INFO" << TXT
sbox-reality unified install complete

Server:
  config: $SERVER_CONF
  installed_anytls_reality: $INSTALL_ANYTLS
  installed_hysteria2_surge: $INSTALL_HY2
TXT

  if (( INSTALL_ANYTLS )); then
    cat > "$ANYTLS_INFO" << TXT
AnyTLS + REALITY installed

Server:
  config: $SERVER_CONF
  listen_port: $ANYTLS_PORT
  port_mode: $ANYTLS_PORT_MODE
  handshake_domain: $REALITY_DOMAIN

Client outbounds:
  file: $ANYTLS_CLIENT_OUT

Client parameters:
  server: $SERVER_IP
  server_port: $ANYTLS_PORT
  password: $ANYTLS_PASSWORD
  server_name: $REALITY_DOMAIN
  public_key: $ANYTLS_PUBLIC_KEY
  short_id: $ANYTLS_SHORT_ID
TXT
    cat "$ANYTLS_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  fi

  if (( INSTALL_HY2 )); then
    cat > "$HY2_INFO" << TXT
Hysteria2 + Surge port hopping installed

Server:
  config: $SERVER_CONF
  listen_port: $HY2_PORT
  port_mode: $HY2_PORT_MODE
  sni: $HY2_SNI
  certificate: $CERT_PATH
  key: $KEY_PATH

Port hopping:
  public_udp_ports: $NORMALIZED_HOP_PORTS
  interval: ${HOP_INTERVAL}s
  helper: $PORT_HELPER
  helper_env: $PORT_ENV
  systemd_dropin: $SYSTEMD_DROPIN

Client files:
  sing-box outbounds: $HY2_CLIENT_OUT
  surge snippet: $SURGE_CONF
  hysteria2 url: $HY2_URL_FILE

Client URL:
  $HY2_SHARE_URL

Client parameters:
  server: $SERVER_IP
  listen_port: $HY2_PORT
  port_hopping: $NORMALIZED_HOP_PORTS
  port_hopping_interval: $HOP_INTERVAL
  password: $HY2_PASSWORD
  sni: $HY2_SNI
  skip_cert_verify: true
TXT

    if [[ "$OBFS" == "on" ]]; then
      cat >> "$HY2_INFO" << TXT
  salamander_password: $OBFS_PASSWORD
TXT
    fi

    cat >> "$HY2_INFO" << TXT

Firewall:
  Allow UDP public ports: $NORMALIZED_HOP_PORTS
  If your local firewall filters after REDIRECT, also allow UDP listen port: $HY2_PORT
TXT
    cat "$HY2_INFO" >> "$COMBINED_INFO"
    printf '\n' >> "$COMBINED_INFO"
  fi

  cat >> "$COMBINED_INFO" << TXT
Commands:
  systemctl status sing-box --no-pager
  journalctl -u sing-box -f
  systemctl restart sing-box
TXT

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
    echo "AnyTLS + REALITY client outbounds:"
    cat "$ANYTLS_CLIENT_OUT"
  fi

  if (( INSTALL_HY2 )); then
    echo
    echo "Surge snippet:"
    cat "$SURGE_CONF"
    echo
    echo "Hysteria2 URL:"
    cat "$HY2_URL_FILE"
    echo
    echo "Hysteria2 sing-box client outbounds:"
    cat "$HY2_CLIENT_OUT"
  fi
}

main() {
  choose_mode
  normalize_mode
  apply_shared_port

  if [[ $EUID -ne 0 ]]; then
    echo "Error: please run as root"
    echo "Example: sudo bash $0 --mode both"
    exit 1
  fi

  if ! command -v apt >/dev/null 2>&1; then
    echo "Error: this script only supports Debian/Ubuntu with apt"
    exit 1
  fi

  prepare_inputs

  echo "sbox-reality unified installer"
  echo "  install_anytls_reality: $INSTALL_ANYTLS"
  echo "  install_hysteria2_surge: $INSTALL_HY2"
  if (( INSTALL_ANYTLS )); then
    echo "  anytls_domain: $REALITY_DOMAIN"
    echo "  anytls_port:   $ANYTLS_PORT ($ANYTLS_PORT_MODE)"
  fi
  if (( INSTALL_HY2 )); then
    echo "  hy2_sni:       $HY2_SNI"
    echo "  hy2_port:      $HY2_PORT ($HY2_PORT_MODE)"
    echo "  hy2_hop_ports: $NORMALIZED_HOP_PORTS"
    echo "  hy2_interval:  ${HOP_INTERVAL}s"
  fi
  echo

  install_dependencies

  if (( INSTALL_ANYTLS )); then
    generate_anytls_secrets
  fi

  if (( INSTALL_HY2 )); then
    prepare_certificate
    generate_hy2_secrets
    write_port_hopping_helper
  else
    disable_hy2_port_hopping
  fi

  write_server_config
  detect_server_ip

  if (( INSTALL_ANYTLS )); then
    write_anytls_client
  fi

  if (( INSTALL_HY2 )); then
    write_hy2_clients
  fi

  sing-box check -c "$SERVER_CONF"
  systemctl daemon-reload
  systemctl enable sing-box
  systemctl restart sing-box

  write_info_files
  print_summary
}

main "$@"
