#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${DOMAIN:-www.apple.com}"
PORT="${PORT:-443}"
SERVER_CONF="/etc/sing-box/config.json"
CLIENT_OUT="/root/client-outbounds-anytls-reality.json"
INFO="/root/anytls-reality-info.txt"

usage() {
  cat << USAGE
Usage:
  bash $0
  bash $0 -d www.apple.com -p 443
  bash $0 --domain www.microsoft.com --port 8443

Defaults:
  domain = www.apple.com
  port   = 443
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--domain)
      DOMAIN="${2:-}"
      shift 2
      ;;
    -p|--port)
      PORT="${2:-}"
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

DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN%%/*}"

if [[ -z "$DOMAIN" ]]; then
  echo "Error: domain cannot be empty"
  exit 1
fi

if [[ ! "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
  echo "Error: invalid port: $PORT"
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  echo "Error: please run as root"
  echo "Example: sudo bash $0 -d www.apple.com -p 443"
  exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
  echo "Error: this script only supports Debian/Ubuntu with apt"
  exit 1
fi

echo "AnyTLS + REALITY installer"
echo "  domain: $DOMAIN"
echo "  port:   $PORT"
echo

apt update
apt install -y curl openssl ca-certificates

curl -fsSL https://sing-box.app/install.sh | sh

mkdir -p /etc/sing-box

KEYPAIR="$(sing-box generate reality-keypair)"
PRIVATE_KEY="$(echo "$KEYPAIR" | awk -F': ' '/PrivateKey/ {print $2}')"
PUBLIC_KEY="$(echo "$KEYPAIR" | awk -F': ' '/PublicKey/ {print $2}')"
PASSWORD="$(openssl rand -base64 32 | tr -d '\n')"
SHORT_ID="$(openssl rand -hex 8)"

if [[ -z "$PRIVATE_KEY" || -z "$PUBLIC_KEY" || -z "$PASSWORD" || -z "$SHORT_ID" ]]; then
  echo "Error: failed to generate keys"
  exit 1
fi

cp "$SERVER_CONF" "$SERVER_CONF.bak.$(date +%s)" 2>/dev/null || true

cat > "$SERVER_CONF" << JSON
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${PORT},
      "users": [
        {
          "password": "${PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${DOMAIN}",
            "server_port": 443
          },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [
            "${SHORT_ID}"
          ]
        }
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

cat > "$CLIENT_OUT" << JSON
{
  "outbounds": [
    {
      "type": "anytls",
      "tag": "proxy",
      "server": "${SERVER_IP}",
      "server_port": ${PORT},
      "password": "${PASSWORD}",
      "tls": {
        "enabled": true,
        "server_name": "${DOMAIN}",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "${PUBLIC_KEY}",
          "short_id": "${SHORT_ID}"
        }
      }
    }
  ]
}
JSON

sing-box check -c "$SERVER_CONF"
systemctl enable sing-box
systemctl restart sing-box

cat > "$INFO" << TXT
AnyTLS + REALITY installed

Server:
  config: $SERVER_CONF
  listen_port: $PORT
  handshake_domain: $DOMAIN

Client outbounds:
  file: $CLIENT_OUT

Client parameters:
  server: $SERVER_IP
  server_port: $PORT
  password: $PASSWORD
  server_name: $DOMAIN
  public_key: $PUBLIC_KEY
  short_id: $SHORT_ID

Commands:
  systemctl status sing-box --no-pager
  journalctl -u sing-box -f
  systemctl restart sing-box
TXT

echo
cat "$INFO"
echo
echo "Client outbounds:"
cat "$CLIENT_OUT"
