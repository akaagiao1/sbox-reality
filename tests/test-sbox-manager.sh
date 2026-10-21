#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MANAGER="$ROOT_DIR/sbox-manager.sh"
INSTALL_SCRIPT="$ROOT_DIR/install.sh"
BIN="${SING_BOX_TEST_BIN:-$(command -v sing-box 2>/dev/null || true)}"
TMP="$(mktemp -d)"
PASS=0
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  PASS=$(( PASS + 1 ))
}

assert_true() {
  local message="$1"
  shift
  "$@" || fail "$message"
  pass
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [[ "$actual" == "$expected" ]] \
    || fail "$message (expected: $expected, actual: $actual)"
  pass
}

if [[ -z "$BIN" || ! -x "$BIN" ]]; then
  echo "SKIP: test-sbox-manager requires SING_BOX_TEST_BIN"
  exit 0
fi

mkdir -p "$TMP/bin" "$TMP/etc/sing-box" "$TMP/clients" "$TMP/state"
for tool in iptables ip6tables ss conntrack; do
  cat > "$TMP/bin/$tool" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${FAKE_IPT_LOG:-}" ]]; then
  printf '%s %s\n' "$(basename "$0")" "$*" >> "$FAKE_IPT_LOG"
fi
if [[ " $* " == *" -C "* ]]; then
  exit 1
fi
if [[ " $* " == *" -D "* ]]; then
  exit 1
fi
exit 0
EOF
  chmod +x "$TMP/bin/$tool"
done

export PATH="$TMP/bin:$PATH"
export SBOX_MANAGER_TEST_MODE=1
export SBOX_STATE_DIR_OVERRIDE="$TMP/state"
export SBOX_CLIENTS_ROOT_OVERRIDE="$TMP/clients"
export SBOX_SERVER_CONF_OVERRIDE="$TMP/etc/sing-box/config.json"
export SBOX_SERVER_HOST="127.0.0.1"
export SBOX_NO_RESTART=1
export SING_BOX_BIN="$BIN"
export SBOX_COUNTER_OVERRIDE_FILE="$TMP/counters.json"
export SBOX_NOTIFY_DRY_RUN_FILE="$TMP/notifications.txt"
export FAKE_IPT_LOG="$TMP/iptables.log"

cat > "$TMP/etc/sing-box/config.json" <<'JSON'
{
  "log": {"level": "warn"},
  "inbounds": [
    {"type":"mixed","tag":"user-in","listen":"127.0.0.1","listen_port":1080}
  ],
  "outbounds": [
    {"type":"direct"},
    {"type":"block","tag":"user-block"}
  ],
  "route": {
    "final": "user-final",
    "rules": [{"ip_is_private":true,"action":"reject"}]
  }
}
JSON
printf '{}\n' > "$TMP/counters.json"

manage() {
  bash "$MANAGER" "$@"
}

assert_true "Snell v5 customer node should be created" \
  manage node add cust-a snell5 --customer cust-a --port 24001 --quota 10G \
    --reset-day 1 --expires 2026-12-31
assert_true "Snell v6 customer node should be created" \
  manage node add cust-b snell6 --customer cust-b --port 24002 --quota 5G \
    --reset-day 15
assert_true "AnyTLS customer node should be created" \
  manage node add cust-c anytls --customer cust-c --port 24003 --quota 20G
assert_true "VLESS customer node should be created" \
  manage node add cust-d vless --customer cust-d --port 24004
assert_true "Hysteria2 customer node should be created" \
  manage node add cust-e hy2 --customer cust-e --port 24005
assert_true "Direct customer node should be created" \
  manage node add cust-f direct --customer cust-f --port 24006 \
    --target 1.1.1.1 --target-port 53

assert_eq "6" "$(jq -r '.nodes | length' "$TMP/state/nodes.json")" \
  "all customer nodes should be stored separately"
assert_eq "6" \
  "$(jq -r '[.inbounds[] | select(.tag | startswith("sbox-"))] | length' \
    "$TMP/etc/sing-box/config.json")" \
  "all customer inbounds should be generated"
assert_true "existing user inbound and route must be preserved" \
  jq -e '
    ([.inbounds[] | select(.tag == "user-in")] | length) == 1
    and .route.final == "user-final"
    and .route.rules[0].ip_is_private == true
    and ([.outbounds[] | select(.tag == "user-block")] | length) == 1
  ' "$TMP/etc/sing-box/config.json"
assert_true "generated server config should pass the current Alpha schema" \
  "$BIN" check -c "$TMP/etc/sing-box/config.json"

assert_true "Snell v5 client files should be generated" \
  bash -c 'test -s "$1/sing-box.json" && test -s "$1/url.txt" && test -s "$1/surge.conf"' \
    _ "$TMP/clients/cust-a"
assert_true "Snell v6 client config should pass schema validation" \
  "$BIN" check -c "$TMP/clients/cust-b/sing-box.json"
assert_true "AnyTLS client config should pass schema validation" \
  "$BIN" check -c "$TMP/clients/cust-c/sing-box.json"
assert_true "VLESS client config should pass schema validation" \
  "$BIN" check -c "$TMP/clients/cust-d/sing-box.json"
assert_true "Hysteria2 client config should pass schema validation" \
  "$BIN" check -c "$TMP/clients/cust-e/sing-box.json"

assert_true "Telegram notification settings should be accepted" \
  manage notify setup 123456:ABCdef 12345,-100987654321
printf '{"cust-a":1181116006}\n' > "$TMP/counters.json"
assert_true "quota and expiry should apply only to the selected node" \
  manage traffic set cust-a --quota 1G --expires 2020-01-01
assert_true "selected node should record quota and expiry pause reasons" \
  jq -e '
    .["cust-a"].used_bytes >= 1073741824
    and (.["cust-a"].paused_reasons | index("quota") != null)
    and (.["cust-a"].paused_reasons | index("expiry") != null)
  ' "$TMP/state/traffic/state.json"
assert_true "unselected nodes must remain unpaused" \
  jq -e '.["cust-b"].paused_reasons == [] and .["cust-c"].paused_reasons == []' \
    "$TMP/state/traffic/state.json"
assert_true "pause rules should target only the selected node port" \
  bash -c '
    grep -Eq "REJECT.*(dport|dports).*24001" "$1"
    ! grep -Eq "REJECT.*(dport|dports).*24002" "$1"
  ' _ "$FAKE_IPT_LOG"
assert_true "quota exhausted notification should be queued" \
  grep -q "流量额度已用完" "$TMP/notifications.txt"
assert_true "expiry notification should be queued" \
  grep -q "节点已到期" "$TMP/notifications.txt"

printf '{}\n' > "$TMP/counters.json"
assert_true "quota reset should not clear an active expiry pause" \
  manage traffic reset cust-a
assert_true "expiry reason should remain after quota reset" \
  jq -e '.["cust-a"].paused_reasons == ["expiry"]' "$TMP/state/traffic/state.json"
assert_true "renewing expiry should restore the node" \
  manage traffic set cust-a --expires 2030-01-01
assert_true "all pause reasons should be cleared after renewal" \
  jq -e '.["cust-a"].paused_reasons == []' "$TMP/state/traffic/state.json"

assert_true "changing one customer port should preserve its node and credentials" \
  manage node port cust-a 24011
assert_true "new port should be written to config and client file" \
  bash -c '
    jq -e '\''
      ([.inbounds[] | select(.tag == "sbox-snell5-cust-a" and .listen_port == 24011)] | length) == 1
    '\'' "$1/etc/sing-box/config.json"
    jq -e ".outbounds[0].server_port == 24011" "$1/clients/cust-a/sing-box.json"
  ' _ "$TMP"

assert_true "deleting one customer should leave other nodes intact" \
  manage node remove cust-f
assert_eq "5" "$(jq -r '.nodes | length' "$TMP/state/nodes.json")" \
  "node removal should remove exactly one managed node"
assert_true "other customer inbounds should remain" \
  jq -e '([.inbounds[] | select(.tag == "sbox-snell5-cust-a")] | length) == 1' \
    "$TMP/etc/sing-box/config.json"

mkdir -p "$TMP/migrate/etc/sing-box" "$TMP/migrate/state" "$TMP/migrate/clients"
cat > "$TMP/migrate/etc/sing-box/config.json" <<'JSON'
{
  "inbounds": [
    {
      "type": "snell",
      "tag": "snell5-in",
      "listen": "::",
      "listen_port": 25001,
      "version": 5,
      "psk": "legacy-password"
    }
  ],
  "outbounds": [{"type":"direct"}]
}
JSON
assert_true "legacy fixed nodes should migrate into the manager state" \
  env SBOX_STATE_DIR_OVERRIDE="$TMP/migrate/state" \
    SBOX_CLIENTS_ROOT_OVERRIDE="$TMP/migrate/clients" \
    SBOX_SERVER_CONF_OVERRIDE="$TMP/migrate/etc/sing-box/config.json" \
    bash "$MANAGER" node migrate
assert_true "migration should preserve the original tag and port" \
  jq -e '
    .nodes == [.nodes[] | select(.id == "default-snell5"
      and .tag == "snell5-in" and .port == 25001 and .psk == "legacy-password")]
  ' "$TMP/migrate/state/nodes.json"

cat > "$TMP/fake-manager" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_MANAGER_LOG"
EOF
chmod +x "$TMP/fake-manager"
assert_true "install.sh should dispatch a customer node in one command" \
  env FAKE_MANAGER_LOG="$TMP/one-click.log" \
    SBOX_REALITY_TEST_MODE=1 \
    bash -c '
      script=$1
      shift
      manager=$1
      set --
      source "$script"
      ACTION=install
      INSTALL_MODE=snell5
      CUSTOMER_ID=customer-one
      CUSTOMER_QUOTA=100G
      CUSTOMER_RESET_DAY=1
      CUSTOMER_EXPIRES=2027-12-31
      SHARED_PORT=26001
      MANAGER_NODE_BIN=$manager
      detect_platform() { :; }
      install_dependencies() { :; }
      install_manager_tool() { :; }
      enable_bbr_and_fq() { :; }
      run_customer_install
    ' _ "$INSTALL_SCRIPT" "$TMP/fake-manager"
assert_true "one-click dispatch should forward customer, quota and expiry" \
  grep -Eq \
    'node add customer-one snell5 .*--port 26001 .*--quota 100G .*--reset-day 1 .*--expires 2027-12-31' \
    "$TMP/one-click.log"

printf 'PASS: %s assertions (multi-tenant manager)\n' "$PASS"
