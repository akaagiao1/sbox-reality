#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALL_SCRIPT="$ROOT_DIR/install.sh"
TEST_GROUP="${1:-all}"
PASS_COUNT=0
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$actual" == "$expected" ]] \
    || fail "$message (expected: $expected, actual: $actual)"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

assert_fails() {
  local message="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "$message (command unexpectedly succeeded)"
  fi
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

assert_succeeds() {
  local message="$1"
  shift
  "$@" >/dev/null 2>&1 || fail "$message (command failed)"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

source_with_args() {
  bash -c '
    script=$1
    shift
    set -- "$@"
    source "$script"
    printf "%s|%s|%s|%s|%s|%s\n" \
      "$ACTION" "$INSTALL_MODE" "$WARP_RULES_EXPLICIT" \
      "$WARP_RULES_INPUT" "$WARP_OFF" "$WARP_RESET"
  ' _ "$INSTALL_SCRIPT" "$@"
}

normalize_rules() {
  bash -c '
    script=$1
    raw=$2
    set --
    source "$script"
    warp_normalize_rules "$raw"
  ' _ "$INSTALL_SCRIPT" "$1"
}

test_normalization() {
  local actual state

  actual="$(normalize_rules 'YouTube， netflix youtube;open_ai')"
  assert_eq '["youtube","netflix","open_ai"]' "$actual" \
    "mixed separators should normalize, lowercase, and deduplicate"

  assert_fails "blank rules should fail" normalize_rules ' ,， ; '
  assert_fails "parent path should fail" normalize_rules '../youtube'
  assert_fails "URL should fail" normalize_rules 'https://example.com/youtube.srs'
  assert_fails "slash should fail" normalize_rules 'google/youtube'
  assert_fails "shell metacharacters should fail" normalize_rules 'youtube,$(id)'

  actual="$(bash -c 'script=$1; set --; source "$script"; type -t warp_normalize_rules' _ "$INSTALL_SCRIPT")"
  assert_eq 'function' "$actual" "sourcing install.sh should not execute main"

  state="$(source_with_args --warp-rules youtube)"
  assert_eq 'warp||1|youtube|0|0' "$state" \
    "warp-only rules should select the standalone action"

  state="$(source_with_args --mode anytls --warp-rules youtube)"
  assert_eq 'install|anytls|1|youtube|0|0' "$state" \
    "protocol and warp rules should remain a combined install action"

  assert_fails "missing --warp-rules value should fail" \
    source_with_args --warp-rules
  assert_fails "warp-off and rules should conflict" \
    source_with_args --warp-off --warp-rules youtube
  assert_fails "warp-off and reset should conflict" \
    source_with_args --warp-off --warp-reset
}

write_registration_response() {
  local destination="$1"
  local client_id="${2:-AQID}"
  cat > "$destination" <<JSON
{
  "config": {
    "client_id": "$client_id",
    "interface": {
      "addresses": {
        "v4": "172.16.0.2/32",
        "v6": "2606:4700:110:8765::2/128"
      }
    }
  }
}
JSON
}

test_credentials() {
  local response="$TEST_TMP/registration.json"
  local credentials="$TEST_TMP/credentials.json"
  local private_key public_key

  private_key="$(head -c 32 /dev/zero | base64 | tr -d '\n')"
  public_key="$(head -c 32 /dev/zero | base64 | tr -d '\n')"
  write_registration_response "$response"

  assert_succeeds "valid Cloudflare response should produce credentials" \
    bash -c '
      script=$1; response=$2; private_key=$3; public_key=$4; destination=$5
      set --; source "$script"
      warp_parse_registration_response \
        "$response" "$private_key" "$public_key" "$destination"
    ' _ "$INSTALL_SCRIPT" "$response" "$private_key" "$public_key" "$credentials"

  assert_succeeds "credential JSON should contain normalized fixed values" \
    jq -e '
      .schema == 1
      and .private_key == $private_key
      and .public_key == $public_key
      and .address == ["172.16.0.2/32", "2606:4700:110:8765::2/128"]
      and .reserved == [1, 2, 3]
      and .mtu == 1280
      and .peer.address == "engage.cloudflareclient.com"
      and .peer.port == 2408
      and .peer.public_key == "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo="
      and .peer.allowed_ips == ["0.0.0.0/0", "::/0"]
      and .peer.persistent_keepalive_interval == 30
    ' --arg private_key "$private_key" --arg public_key "$public_key" "$credentials"

  assert_succeeds "generated credential file should validate" \
    bash -c '
      script=$1; credentials=$2
      set --; source "$script"
      warp_validate_credentials "$credentials"
    ' _ "$INSTALL_SCRIPT" "$credentials"

  assert_succeeds "OpenSSL key generation should return two valid X25519 keys" \
    bash -c '
      script=$1
      set --; source "$script"
      keypair="$(warp_generate_keypair)"
      generated_private="$(jq -er .private_key <<< "$keypair")"
      generated_public="$(jq -er .public_key <<< "$keypair")"
      warp_validate_key "$generated_private"
      warp_validate_key "$generated_public"
    ' _ "$INSTALL_SCRIPT"

  assert_succeeds "registration POST should send the required Cloudflare request" \
    bash -c '
      script=$1; mock_public_key=$2; response_file=$3; capture_file=$4
      set --; source "$script"
      curl() {
        local output="" data="" url="" cf_header=0 content_header=0
        while (( $# )); do
          case "$1" in
            --output) output=$2; shift 2 ;;
            --data) data=$2; shift 2 ;;
            --header)
              [[ "$2" == "CF-Client-Version: a-6.11-2223" ]] && cf_header=1
              [[ "$2" == "Content-Type: application/json" ]] && content_header=1
              shift 2
              ;;
            https://*) url=$1; shift ;;
            *) shift ;;
          esac
        done
        printf "{}\n" > "$output"
        jq -n --arg url "$url" --argjson cf "$cf_header" \
          --argjson content "$content_header" --argjson data "$data" \
          "{url:\$url,cf_header:\$cf,content_header:\$content,data:\$data}" \
          > "$capture_file"
        printf 201
      }
      warp_post_registration "$mock_public_key" "$response_file"
      jq -e --arg key "$mock_public_key" \
        ".url == \"https://api.cloudflareclient.com/v0a2158/reg\"
         and .cf_header == 1 and .content_header == 1
         and .data.key == \$key
         and .data.install_id == \"\"
         and .data.fcm_token == \"\"
         and .data.model == \"Linux\"
         and (.data.serial_number | test(\"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\$\"))
         and (.data.tos | test(\"Z\$\"))" "$capture_file"
    ' _ "$INSTALL_SCRIPT" "$public_key" "$TEST_TMP/post-response.json" "$TEST_TMP/post-capture.json"

  jq 'del(.config.interface.addresses.v4)' "$response" > "$TEST_TMP/missing-v4.json"
  assert_fails "missing WARP IPv4 should fail without a destination" \
    bash -c '
      script=$1; response=$2; private_key=$3; public_key=$4; destination=$5
      rm -f "$destination"; set --; source "$script"
      warp_parse_registration_response "$response" "$private_key" "$public_key" "$destination"
    ' _ "$INSTALL_SCRIPT" "$TEST_TMP/missing-v4.json" "$private_key" "$public_key" "$TEST_TMP/missing-v4-output.json"
  [[ ! -e "$TEST_TMP/missing-v4-output.json" ]] \
    || fail "missing IPv4 left a partial credential file"
  PASS_COUNT=$(( PASS_COUNT + 1 ))

  write_registration_response "$TEST_TMP/bad-client-id.json" 'not-base64!'
  assert_fails "malformed client_id should fail" \
    bash -c 'script=$1; shift; set --; source "$script"; warp_parse_registration_response "$@"' \
      _ "$INSTALL_SCRIPT" "$TEST_TMP/bad-client-id.json" "$private_key" "$public_key" "$TEST_TMP/bad-client-id-output.json"

  write_registration_response "$TEST_TMP/short-client-id.json" 'AQI='
  assert_fails "client_id must decode to exactly three bytes" \
    bash -c 'script=$1; shift; set --; source "$script"; warp_parse_registration_response "$@"' \
      _ "$INSTALL_SCRIPT" "$TEST_TMP/short-client-id.json" "$private_key" "$public_key" "$TEST_TMP/short-client-id-output.json"

  assert_fails "malformed private key should fail" \
    bash -c 'script=$1; shift; set --; source "$script"; warp_parse_registration_response "$@"' \
      _ "$INSTALL_SCRIPT" "$response" bad-key "$public_key" "$TEST_TMP/bad-key-output.json"

  assert_succeeds "registration should use seams and avoid real network access" \
    bash -c '
      script=$1; response=$2; destination=$3; mock_private_key=$4; mock_public_key=$5
      set --; source "$script"
      warp_generate_keypair() {
        printf "{\"private_key\":\"%s\",\"public_key\":\"%s\"}\n" \
          "$mock_private_key" "$mock_public_key"
      }
      warp_post_registration() {
        [[ "$1" == "$mock_public_key" ]] || return 91
        cp "$response" "$2"
      }
      warp_register_credentials "$destination"
      warp_validate_credentials "$destination"
    ' _ "$INSTALL_SCRIPT" "$response" "$TEST_TMP/registered.json" "$private_key" "$public_key"

  assert_fails "registration POST failure should propagate" \
    bash -c '
      script=$1; destination=$2; mock_private_key=$3; mock_public_key=$4
      set --; source "$script"
      warp_generate_keypair() {
        printf "{\"private_key\":\"%s\",\"public_key\":\"%s\"}\n" \
          "$mock_private_key" "$mock_public_key"
      }
      warp_post_registration() { return 1; }
      warp_register_credentials "$destination"
    ' _ "$INSTALL_SCRIPT" "$TEST_TMP/post-failed.json" "$private_key" "$public_key"
  [[ ! -e "$TEST_TMP/post-failed.json" ]] || fail "failed POST left a credential file"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

write_test_credentials() {
  local destination="$1"
  local response="$TEST_TMP/config-registration.json"
  local key
  key="$(head -c 32 /dev/zero | base64 | tr -d '\n')"
  write_registration_response "$response"
  bash -c '
    script=$1; response=$2; key=$3; destination=$4
    set --; source "$script"
    warp_parse_registration_response "$response" "$key" "$key" "$destination"
  ' _ "$INSTALL_SCRIPT" "$response" "$key" "$destination"
}

merge_warp_config() {
  local input="$1"
  local credentials="$2"
  local rules="$3"
  local output="$4"
  bash -c '
    script=$1; input=$2; credentials=$3; rules=$4; output=$5
    set --; source "$script"
    warp_merge_config "$input" "$credentials" "$rules" "$output"
  ' _ "$INSTALL_SCRIPT" "$input" "$credentials" "$rules" "$output"
}

test_config() {
  local base="$TEST_TMP/base.json"
  local credentials="$TEST_TMP/config-credentials.json"
  local merged="$TEST_TMP/merged.json"
  local updated="$TEST_TMP/updated.json"
  local removed="$TEST_TMP/removed.json"
  local removed_twice="$TEST_TMP/removed-twice.json"
  local current_rules

  write_test_credentials "$credentials"
  cat > "$base" <<'JSON'
{
  "log": {"level": "warn"},
  "inbounds": [{"type": "mixed", "tag": "user-in", "listen": "127.0.0.1", "listen_port": 2081}],
  "outbounds": [
    {"type": "direct"},
    {"type": "block", "tag": "user-block"}
  ],
  "endpoints": [{"type": "user-endpoint", "tag": "user-endpoint", "value": 7}],
  "route": {
    "rules": [{"ip_is_private": true, "action": "reject"}],
    "final": "user-final",
    "auto_detect_interface": true
  },
  "experimental": {"cache_file": {"enabled": true}}
}
JSON

  assert_succeeds "youtube and netflix should merge into the existing config" \
    merge_warp_config "$base" "$credentials" '["youtube","netflix"]' "$merged"

  assert_succeeds "merged config should contain all managed objects" \
    jq -e '
      ([.outbounds[] | select(.tag == "sbox-warp-direct" and .type == "direct")] | length) == 1
      and ([.endpoints[] | select(.tag == "sbox-warp-out" and .type == "wireguard")] | length) == 1
      and ([.route.rule_set[] | select(.tag == "sbox-warp-geosite-youtube"
        and .type == "remote" and .format == "binary"
        and .download_detour == "sbox-warp-direct"
        and .url == "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/youtube.srs")] | length) == 1
      and ([.route.rule_set[] | select(.tag == "sbox-warp-geosite-netflix")] | length) == 1
      and .route.rules[0] == {"action":"sniff"}
      and .route.rules[1].action == "route"
      and .route.rules[1].outbound == "sbox-warp-out"
      and .route.rules[1].rule_set == ["sbox-warp-geosite-youtube", "sbox-warp-geosite-netflix"]
      and .route.rules[2] == {"ip_is_private":true,"action":"reject"}
    ' "$merged"

  assert_succeeds "unmanaged configuration values should be preserved" \
    jq -e --slurpfile base "$base" '
      .log == $base[0].log
      and .inbounds == $base[0].inbounds
      and ([.outbounds[] | select((.tag // "") != "sbox-warp-direct")] == $base[0].outbounds)
      and ([.endpoints[] | select((.tag // "") != "sbox-warp-out")] == $base[0].endpoints)
      and .route.final == $base[0].route.final
      and .route.auto_detect_interface == $base[0].route.auto_detect_interface
      and .experimental == $base[0].experimental
    ' "$merged"

  current_rules="$(bash -c '
    script=$1; config=$2; set --; source "$script"; warp_current_rules "$config"
  ' _ "$INSTALL_SCRIPT" "$merged")"
  assert_eq '["youtube","netflix"]' "$current_rules" \
    "managed rule names should be extractable"

  assert_succeeds "replacement should remove old managed rule sets" \
    merge_warp_config "$merged" "$credentials" '["netflix"]' "$updated"
  assert_succeeds "replacement should retain only netflix" \
    jq -e '
      ([.route.rule_set[] | select(.tag == "sbox-warp-geosite-youtube")] | length) == 0
      and ([.route.rule_set[] | select(.tag == "sbox-warp-geosite-netflix")] | length) == 1
      and .route.rules[1].rule_set == ["sbox-warp-geosite-netflix"]
    ' "$updated"

  assert_succeeds "warp removal should succeed" \
    bash -c '
      script=$1; input=$2; output=$3; set --; source "$script"
      warp_remove_config "$input" "$output"
    ' _ "$INSTALL_SCRIPT" "$updated" "$removed"
  assert_succeeds "warp removal should delete only managed objects" \
    jq -e --slurpfile base "$base" '
      .outbounds == $base[0].outbounds
      and .endpoints == $base[0].endpoints
      and (.route.rule_set // []) == []
      and .route.rules == $base[0].route.rules
      and .route.final == $base[0].route.final
      and .experimental == $base[0].experimental
    ' "$removed"
  assert_succeeds "warp removal should be idempotent" \
    bash -c '
      script=$1; input=$2; output=$3; set --; source "$script"
      warp_remove_config "$input" "$output"
    ' _ "$INSTALL_SCRIPT" "$removed" "$removed_twice"
  assert_succeeds "second removal should not change JSON" \
    bash -c 'diff -u <(jq -S . "$1") <(jq -S . "$2")' \
      _ "$removed" "$removed_twice"

  jq '.outbounds += [{"type":"block","tag":"sbox-warp-direct"}]' "$base" \
    > "$TEST_TMP/conflict-outbound.json"
  assert_fails "unexpected managed outbound collision should fail" \
    merge_warp_config "$TEST_TMP/conflict-outbound.json" "$credentials" '["youtube"]' "$TEST_TMP/conflict-outbound-result.json"

  jq '.endpoints += [{"type":"direct","tag":"sbox-warp-out"}]' "$base" \
    > "$TEST_TMP/conflict-endpoint.json"
  assert_fails "unexpected managed endpoint collision should fail" \
    merge_warp_config "$TEST_TMP/conflict-endpoint.json" "$credentials" '["youtube"]' "$TEST_TMP/conflict-endpoint-result.json"

  jq '.route.rule_set = [{"type":"local","tag":"sbox-warp-geosite-youtube","path":"/tmp/user.srs"}]' "$base" \
    > "$TEST_TMP/conflict-ruleset.json"
  assert_fails "unexpected managed rule-set collision should fail" \
    merge_warp_config "$TEST_TMP/conflict-ruleset.json" "$credentials" '["youtube"]' "$TEST_TMP/conflict-ruleset-result.json"

  assert_fails "all rule URLs should be probed and one missing rule should fail" \
    bash -c '
      script=$1; capture=$2; set --; source "$script"
      warp_probe_url() {
        printf "%s\n" "$1" >> "$capture"
        [[ "$1" != *netflix.srs ]]
      }
      warp_validate_rule_urls "[\"youtube\",\"netflix\"]"
    ' _ "$INSTALL_SCRIPT" "$TEST_TMP/probed-urls.txt"
  assert_eq '2' "$(wc -l < "$TEST_TMP/probed-urls.txt" | tr -d ' ')" \
    "URL validation should check every selected rule"
  assert_succeeds "URL validation should build exact MetaCubeX URLs" \
    bash -c '
      grep -Fx "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/youtube.srs" "$1"
      grep -Fx "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo-lite/geosite/netflix.srs" "$1"
    ' _ "$TEST_TMP/probed-urls.txt"

  if [[ -x /workspace/.sbox-dev/bin/sing-box ]]; then
    cat > "$TEST_TMP/schema-base.json" <<'JSON'
{
  "inbounds": [{"type":"mixed","tag":"test-in","listen":"127.0.0.1","listen_port":2080}],
  "outbounds": [{"type":"direct"}]
}
JSON
    assert_succeeds "generated WARP config should pass sing-box schema validation" \
      merge_warp_config "$TEST_TMP/schema-base.json" "$credentials" '["youtube"]' "$TEST_TMP/schema-merged.json"
    assert_succeeds "sing-box should accept the generated WARP config" \
      /workspace/.sbox-dev/bin/sing-box check -c "$TEST_TMP/schema-merged.json"
    cp "$TEST_TMP/schema-merged.json" /tmp/sbox-warp-generated-test.json
  fi
}

run_warp_apply() {
  local config="$1"
  local credentials="$2"
  local registration_fixture="$3"
  local rules_json="$4"
  local reset="$5"
  local register_count="$6"
  local restart_count="$7"
  local failure="${8:-none}"

  SERVER_CONF="$config" WARP_CREDENTIALS_FILE="$credentials" \
    bash -c '
      script=$1; registration_fixture=$2; rules_json=$3; reset=$4
      register_count=$5; restart_count=$6; failure=$7
      set --; source "$script"
      WARP_RULES_JSON="$rules_json"
      WARP_RULES_EXPLICIT=1
      WARP_RESET="$reset"
      warp_probe_url() { [[ "$failure" != url ]]; }
      warp_register_credentials() {
        count=0; [[ -f "$register_count" ]] && count="$(cat "$register_count")"
        printf "%s\n" "$(( count + 1 ))" > "$register_count"
        [[ "$failure" != registration ]] || return 1
        cp "$registration_fixture" "$1"
      }
      if [[ "$failure" == merge ]]; then
        warp_merge_config() { return 1; }
      fi
      run_sing_box() {
        [[ "$failure" != check ]]
      }
      backup_existing_files() { return 0; }
      service_restart() {
        count=0; [[ -f "$restart_count" ]] && count="$(cat "$restart_count")"
        count=$(( count + 1 ))
        printf "%s\n" "$count" > "$restart_count"
        if [[ "$failure" == restart && "$count" == 1 ]]; then
          return 1
        fi
        return 0
      }
      warp_apply_existing
    ' _ "$INSTALL_SCRIPT" "$registration_fixture" "$rules_json" "$reset" \
      "$register_count" "$restart_count" "$failure"
}

run_warp_off() {
  local config="$1"
  local credentials="$2"
  local restart_count="$3"

  SERVER_CONF="$config" WARP_CREDENTIALS_FILE="$credentials" \
    bash -c '
      script=$1; restart_count=$2; set --; source "$script"
      run_sing_box() { return 0; }
      backup_existing_files() { return 0; }
      service_restart() {
        count=0; [[ -f "$restart_count" ]] && count="$(cat "$restart_count")"
        printf "%s\n" "$(( count + 1 ))" > "$restart_count"
      }
      warp_disable_existing
    ' _ "$INSTALL_SCRIPT" "$restart_count"
}

test_transaction() {
  local config="$TEST_TMP/transaction-config.json"
  local credentials="$TEST_TMP/transaction-credentials.json"
  local fixture_one="$TEST_TMP/transaction-fixture-one.json"
  local fixture_two="$TEST_TMP/transaction-fixture-two.json"
  local register_count="$TEST_TMP/register-count"
  local restart_count="$TEST_TMP/restart-count"
  local original_config original_credentials

  cat > "$config" <<'JSON'
{
  "inbounds": [{"type":"mixed","tag":"test-in","listen":"127.0.0.1","listen_port":2080}],
  "outbounds": [{"type":"direct"}]
}
JSON
  write_test_credentials "$fixture_one"
  cp "$fixture_one" "$fixture_two"
  jq --arg key "$(printf '11111111111111111111111111111111' | base64 | tr -d '\n')" \
    '.private_key = $key | .public_key = $key' "$fixture_two" > "$fixture_two.tmp"
  mv "$fixture_two.tmp" "$fixture_two"

  assert_succeeds "first standalone enable should register and apply WARP" \
    run_warp_apply "$config" "$credentials" "$fixture_one" '["youtube"]' 0 \
      "$register_count" "$restart_count"
  assert_eq '1' "$(cat "$register_count")" "first enable should register once"
  assert_eq '1' "$(cat "$restart_count")" "first enable should restart once"
  assert_eq '600' "$(stat -c '%a' "$config")" "server config mode should be 600"
  assert_eq '600' "$(stat -c '%a' "$credentials")" "credential mode should be 600"
  assert_succeeds "first enable should install youtube routing" \
    jq -e '.route.rules[1].rule_set == ["sbox-warp-geosite-youtube"]' "$config"

  assert_succeeds "second update should reuse credentials" \
    run_warp_apply "$config" "$credentials" "$fixture_two" '["netflix"]' 0 \
      "$register_count" "$restart_count"
  assert_eq '1' "$(cat "$register_count")" "ordinary update must not register again"
  assert_succeeds "second update should replace the selected rule" \
    jq -e '.route.rules[1].rule_set == ["sbox-warp-geosite-netflix"]' "$config"
  assert_succeeds "ordinary update should preserve original credentials" \
    bash -c 'cmp -s "$1" "$2"' _ "$credentials" "$fixture_one"

  assert_succeeds "reset should replace credentials" \
    run_warp_apply "$config" "$credentials" "$fixture_two" '["netflix"]' 1 \
      "$register_count" "$restart_count"
  assert_eq '2' "$(cat "$register_count")" "reset should register exactly once more"
  assert_succeeds "reset should install newly registered credentials" \
    bash -c 'cmp -s "$1" "$2"' _ "$credentials" "$fixture_two"

  assert_succeeds "warp-off should remove managed routing" \
    run_warp_off "$config" "$credentials" "$restart_count"
  assert_succeeds "warp-off should remove endpoint and managed outbound" \
    jq -e '
      ([.endpoints[]? | select(.tag == "sbox-warp-out")] | length) == 0
      and ([.outbounds[]? | select(.tag == "sbox-warp-direct")] | length) == 0
    ' "$config"
  assert_succeeds "warp-off should retain credentials" \
    bash -c 'cmp -s "$1" "$2"' _ "$credentials" "$fixture_two"
  assert_succeeds "repeated warp-off should be idempotent" \
    run_warp_off "$config" "$credentials" "$restart_count"

  assert_succeeds "restore youtube before failure injection" \
    run_warp_apply "$config" "$credentials" "$fixture_two" '["youtube"]' 0 \
      "$register_count" "$restart_count"
  original_config="$(sha256sum "$config" | awk '{print $1}')"
  original_credentials="$(sha256sum "$credentials" | awk '{print $1}')"

  assert_fails "rule URL failure should not change formal files" \
    run_warp_apply "$config" "$credentials" "$fixture_one" '["netflix"]' 0 \
      "$register_count" "$restart_count" url
  assert_eq "$original_config" "$(sha256sum "$config" | awk '{print $1}')" \
    "URL failure should preserve config"
  assert_eq "$original_credentials" "$(sha256sum "$credentials" | awk '{print $1}')" \
    "URL failure should preserve credentials"

  assert_fails "registration failure during reset should preserve files" \
    run_warp_apply "$config" "$credentials" "$fixture_one" '["netflix"]' 1 \
      "$register_count" "$restart_count" registration
  assert_eq "$original_config" "$(sha256sum "$config" | awk '{print $1}')" \
    "registration failure should preserve config"
  assert_eq "$original_credentials" "$(sha256sum "$credentials" | awk '{print $1}')" \
    "registration failure should preserve old credentials"

  assert_fails "merge failure should preserve files" \
    run_warp_apply "$config" "$credentials" "$fixture_one" '["netflix"]' 0 \
      "$register_count" "$restart_count" merge
  assert_eq "$original_config" "$(sha256sum "$config" | awk '{print $1}')" \
    "merge failure should preserve config"

  assert_fails "sing-box check failure should preserve files" \
    run_warp_apply "$config" "$credentials" "$fixture_one" '["netflix"]' 0 \
      "$register_count" "$restart_count" check
  assert_eq "$original_config" "$(sha256sum "$config" | awk '{print $1}')" \
    "check failure should preserve config"

  printf '0\n' > "$restart_count"
  assert_fails "restart failure should roll back both formal files" \
    run_warp_apply "$config" "$credentials" "$fixture_one" '["netflix"]' 1 \
      "$register_count" "$restart_count" restart
  assert_eq '2' "$(cat "$restart_count")" \
    "restart failure should attempt the restored service"
  assert_eq "$original_config" "$(sha256sum "$config" | awk '{print $1}')" \
    "restart rollback should restore config"
  assert_eq "$original_credentials" "$(sha256sum "$credentials" | awk '{print $1}')" \
    "restart rollback should restore credentials"

  assert_succeeds "standalone dispatcher should select a WARP update" \
    bash -c '
      script=$1; sentinel=$2; set --; source "$script"
      WARP_OFF=0
      warp_apply_existing() { printf update > "$sentinel"; }
      warp_run_standalone
      [[ "$(cat "$sentinel")" == update ]]
    ' _ "$INSTALL_SCRIPT" "$TEST_TMP/main-update-sentinel"

  assert_succeeds "standalone dispatcher should select WARP disable" \
    bash -c '
      script=$1; sentinel=$2; set --; source "$script"
      WARP_OFF=1
      warp_disable_existing() { printf disable > "$sentinel"; }
      warp_run_standalone
      [[ "$(cat "$sentinel")" == disable ]]
    ' _ "$INSTALL_SCRIPT" "$TEST_TMP/main-disable-sentinel"
}

case "$TEST_GROUP" in
  normalization)
    test_normalization
    ;;
  credentials)
    test_credentials
    ;;
  config)
    test_config
    ;;
  transaction)
    test_transaction
    ;;
  all)
    test_normalization
    test_credentials
    test_config
    test_transaction
    ;;
  integration)
    fail "test group not implemented yet: $TEST_GROUP"
    ;;
  *)
    fail "unknown test group: $TEST_GROUP"
    ;;
esac

printf 'PASS: %d assertions (%s)\n' "$PASS_COUNT" "$TEST_GROUP"
