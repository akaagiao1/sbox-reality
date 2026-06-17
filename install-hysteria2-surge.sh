#!/usr/bin/env bash
set -euo pipefail

SNI="${SNI:-www.bing.com}"
PORT="${PORT:-auto}"
HOP_PORTS="${HOP_PORTS:-20000-50000}"
HOP_INTERVAL="${HOP_INTERVAL:-30}"
UP_MBPS="${UP_MBPS:-}"
DOWN_MBPS="${DOWN_MBPS:-}"
OBFS="${OBFS:-off}"
OBFS_PASSWORD="${OBFS_PASSWORD:-}"
PROXY_NAME="${PROXY_NAME:-HY2}"

SERVER_CONF="/etc/sing-box/config.json"
CLIENT_OUT="/root/client-outbounds-hysteria2.json"
SURGE_CONF="/root/surge-hysteria2.conf"
HY2_URL_FILE="/root/hysteria2-url.txt"
INFO="/root/hysteria2-surge-info.txt"
PORT_ENV="/etc/sing-box/hy2-port-hopping.env"
PORT_HELPER="/usr/local/bin/sing-box-hy2-port-hopping"
SYSTEMD_DROPIN="/etc/systemd/system/sing-box.service.d/10-hy2-port-hopping.conf"
DEFAULT_CERT_PATH="/etc/sing-box/hysteria2.crt"
DEFAULT_KEY_PATH="/etc/sing-box/hysteria2.key"
CERT_PATH="${CERT_PATH:-$DEFAULT_CERT_PATH}"
KEY_PATH="${KEY_PATH:-$DEFAULT_KEY_PATH}"

FIRST_HOP_PORT=""
NORMALIZED_HOP_PORTS=""
SERVER_PORTS_JSON=""
PORT_MODE=""
HY2_SHARE_URL=""

usage() {
  cat << USAGE
Usage:
  bash $0
  bash $0 --ports 20000-50000
  bash $0 --sni example.com --ports "20000-50000;7044;8000-9000" --interval 30
  bash $0 --port 8443 --ports 20000-50000

Defaults:
  sni       = www.bing.com
  port      = auto, use the first hop port as the sing-box Hysteria2 listen port
  ports     = 20000-50000
  interval  = 30 seconds

Options:
  -s, --sni           TLS SNI and self-signed certificate common name
  -p, --port          Actual sing-box listen port. Use auto for the first hop port
  -P, --ports         Surge port-hopping ports/ranges, separated by ; or ,
  -i, --interval      Port hopping interval in seconds, minimum 5
      --up            Server upload bandwidth in Mbps, optional
      --down          Server download bandwidth in Mbps, optional
      --obfs          Enable Hysteria2 Salamander obfuscation
      --obfs-password Salamander obfuscation password
      --cert          Existing TLS certificate path
      --key           Existing TLS key path
      --name          Surge proxy name
  -h, --help          Show help

Environment variables with the same names are also supported:
  SNI, PORT, HOP_PORTS, HOP_INTERVAL, UP_MBPS, DOWN_MBPS,
  OBFS, OBFS_PASSWORD, CERT_PATH, KEY_PATH, PROXY_NAME
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--sni)
      SNI="${2:-}"
      shift 2
      ;;
    -p|--port)
      PORT="${2:-}"
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

SNI="${SNI#https://}"
SNI="${SNI#http://}"
SNI="${SNI%%/*}"

if [[ -z "$SNI" ]]; then
  echo "Error: sni cannot be empty"
  exit 1
fi

if [[ "$SNI" =~ [[:space:]] ]]; then
  echo "Error: sni cannot contain whitespace"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Error: please run as root"
  echo "Example: sudo bash $0 --ports 20000-50000"
  exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
  echo "Error: this script only supports Debian/Ubuntu with apt"
  exit 1
fi

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

normalize_hop_ports() {
  local -a specs
  local raw spec start end normalized sep first

  raw="${HOP_PORTS//[[:space:]]/}"
  raw="${raw//,/;}"

  if [[ -z "$raw" ]]; then
    echo "Error: ports cannot be empty"
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

is_port_in_use_by_other() {
  local port="$1"
  ss -H -lunp 2>/dev/null | awk -v p="$port" '$4 ~ ":" p "$" {print}' | grep -v "sing-box" | grep -q .
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
  if [[ "$SNI" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    san_type="IP"
  fi

  openssl req -x509 -nodes \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 3650 \
    -keyout "$KEY_PATH" \
    -out "$CERT_PATH" \
    -subj "/CN=${SNI}" \
    -addext "subjectAltName=${san_type}:${SNI}" >/dev/null 2>&1

  chmod 600 "$KEY_PATH"
  chmod 644 "$CERT_PATH"
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
  query="insecure=1&sni=$(url_encode "$SNI")"

  if [[ "$OBFS" == "on" ]]; then
    query="${query}&obfs=salamander&obfs-password=$(url_encode "$OBFS_PASSWORD")"
  fi

  HY2_SHARE_URL="hysteria2://$(url_encode "$PASSWORD")@${SERVER_IP}:${uri_ports}/?${query}#$(url_encode "$PROXY_NAME")"
}

write_port_hopping_helper() {
  mkdir -p /etc/sing-box "$(dirname "$PORT_HELPER")" "$(dirname "$SYSTEMD_DROPIN")"

  cat > "$PORT_ENV" << ENV
HOP_PORTS="${NORMALIZED_HOP_PORTS}"
LISTEN_PORT="${PORT}"
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

normalize_hop_ports
build_server_ports_json

if [[ -z "$PORT" || "$PORT" == "auto" || "$PORT" == "random" ]]; then
  PORT="$FIRST_HOP_PORT"
  PORT_MODE="first-hop-port"
elif validate_port "$PORT"; then
  PORT_MODE="manual"
else
  echo "Error: invalid listen port: $PORT"
  exit 1
fi

if ! validate_positive_number "$HOP_INTERVAL" || (( HOP_INTERVAL < 5 )); then
  echo "Error: interval must be an integer greater than or equal to 5"
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

echo "Hysteria2 + Surge port hopping installer"
echo "  installing dependencies..."

apt update
apt install -y curl openssl ca-certificates iproute2 coreutils nftables iptables

if [[ "$OBFS" == "on" && -z "$OBFS_PASSWORD" ]]; then
  OBFS_PASSWORD="$(openssl rand -hex 16)"
fi

if is_port_in_use_by_other "$PORT"; then
  echo "Error: UDP port $PORT is already used by another process"
  ss -H -lunp 2>/dev/null | awk -v p="$PORT" '$4 ~ ":" p "$" {print}' || true
  exit 1
fi

echo "  sni:          $SNI"
echo "  listen_port:  $PORT ($PORT_MODE)"
echo "  hop_ports:    $NORMALIZED_HOP_PORTS"
echo "  interval:     ${HOP_INTERVAL}s"
echo

curl -fsSL https://sing-box.app/install.sh | sh

mkdir -p /etc/sing-box
prepare_certificate
write_port_hopping_helper

PASSWORD="$(openssl rand -hex 32)"

cp "$SERVER_CONF" "$SERVER_CONF.bak.$(date +%s)" 2>/dev/null || true

cat > "$SERVER_CONF" << JSON
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${PORT},
$(json_number_field "up_mbps" "$UP_MBPS")$(json_number_field "down_mbps" "$DOWN_MBPS")$(json_obfs_field)      "users": [
        {
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "certificate_path": "${CERT_PATH}",
        "key_path": "${KEY_PATH}"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON

SERVER_IP="$(curl -4 -s --max-time 8 https://api.ipify.org || true)"
if [[ -z "$SERVER_IP" ]]; then
  SERVER_IP="your_vps_ip_or_domain"
fi

build_hy2_share_url

cat > "$CLIENT_OUT" << JSON
{
  "outbounds": [
    {
      "type": "hysteria2",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_ports": ${SERVER_PORTS_JSON},
      "hop_interval": "${HOP_INTERVAL}s",
$(json_number_field "up_mbps" "$UP_MBPS")$(json_number_field "down_mbps" "$DOWN_MBPS")$(json_obfs_field)      "password": "${PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${SNI}",
        "insecure": true
      }
    }
  ]
}
JSON

cat > "$SURGE_CONF" << SURGE
[Proxy]
${PROXY_NAME} = hysteria2, ${SERVER_IP}, ${PORT}, password=${PASSWORD}, skip-cert-verify=true, sni=${SNI}, port-hopping="${NORMALIZED_HOP_PORTS}", port-hopping-interval=${HOP_INTERVAL}$(surge_extra_params)

[Proxy Group]
Proxy = select, ${PROXY_NAME}, DIRECT
SURGE

printf '%s\n' "$HY2_SHARE_URL" > "$HY2_URL_FILE"

sing-box check -c "$SERVER_CONF"
systemctl daemon-reload
systemctl enable sing-box
systemctl restart sing-box

cat > "$INFO" << TXT
Hysteria2 + Surge port hopping installed

Server:
  config: $SERVER_CONF
  listen_port: $PORT
  port_mode: $PORT_MODE
  sni: $SNI
  certificate: $CERT_PATH
  key: $KEY_PATH

Port hopping:
  public_udp_ports: $NORMALIZED_HOP_PORTS
  interval: ${HOP_INTERVAL}s
  helper: $PORT_HELPER
  helper_env: $PORT_ENV
  systemd_dropin: $SYSTEMD_DROPIN

Client files:
  sing-box outbounds: $CLIENT_OUT
  surge snippet: $SURGE_CONF
  hysteria2 url: $HY2_URL_FILE

Client URL:
  $HY2_SHARE_URL

Client parameters:
  server: $SERVER_IP
  listen_port: $PORT
  port_hopping: $NORMALIZED_HOP_PORTS
  port_hopping_interval: $HOP_INTERVAL
  password: $PASSWORD
  sni: $SNI
  skip_cert_verify: true
TXT

if [[ "$OBFS" == "on" ]]; then
  cat >> "$INFO" << TXT
  salamander_password: $OBFS_PASSWORD
TXT
fi

cat >> "$INFO" << TXT

Firewall:
  Allow UDP public ports: $NORMALIZED_HOP_PORTS
  If your local firewall filters after REDIRECT, also allow UDP listen port: $PORT

Commands:
  systemctl status sing-box --no-pager
  journalctl -u sing-box -f
  systemctl restart sing-box
  $PORT_HELPER clean
  $PORT_HELPER apply
TXT

echo
cat "$INFO"
echo
echo "Hysteria2 URL:"
cat "$HY2_URL_FILE"
echo
echo "Surge snippet:"
cat "$SURGE_CONF"
echo
echo "sing-box client outbounds:"
cat "$CLIENT_OUT"
