#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALL_SCRIPT="$ROOT_DIR/install.sh"
TEST_GROUP="${1:-all}"
PASS_COUNT=0
TEST_TMP="$(mktemp -d)"
SING_BOX_TEST_BIN="${SING_BOX_TEST_BIN:-$(command -v sing-box 2>/dev/null || true)}"
export SBOX_REALITY_TEST_MODE=1
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

assert_mode_600() {
  local file="$1"
  local message="$2"

  [[ -s "$file" ]] || fail "$message (file is empty or missing)"
  if [[ "$OSTYPE" != cygwin* ]]; then
    [[ "$(stat -c '%a' "$file")" == "600" ]] \
      || fail "$message (actual mode: $(stat -c '%a' "$file"))"
  fi
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
  assert_fails "warp-off should not be combined with protocol install" \
    source_with_args --mode anytls --warp-off
  assert_fails "restore should not be overridden by WARP rules" \
    source_with_args --restore --warp-rules youtube
  assert_fails "uninstall should not be overridden by warp-off" \
    source_with_args --uninstall anytls --warp-off
  assert_fails "config keep should not silently ignore WARP rules" \
    source_with_args --mode anytls --config keep --warp-rules youtube
  assert_fails "action aliases in --mode should not ignore WARP rules" \
    source_with_args --mode uninstall --warp-rules youtube
  assert_fails "tab-wrapped action aliases should not bypass WARP conflicts" \
    source_with_args --mode $'\t7\t' --warp-rules youtube
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
        and .http_client == {"detour":"sbox-warp-direct"}
        and (has("download_detour") | not)
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

  jq '
    .route.rule_set |= map(.download_detour = .http_client.detour | del(.http_client))
    | .outbounds |= map(if .tag == "sbox-warp-direct" then del(.connect_timeout) else . end)
  ' "$merged" > "$TEST_TMP/legacy-warp.json"
  assert_eq '["youtube","netflix"]' "$(bash -c '
    script=$1; config=$2; set --; source "$script"; warp_current_rules "$config"
  ' _ "$INSTALL_SCRIPT" "$TEST_TMP/legacy-warp.json")" \
    "legacy selected rules should remain reusable without registering again"
  assert_succeeds "legacy rules should upgrade to the supported HTTP client" \
    merge_warp_config "$TEST_TMP/legacy-warp.json" "$credentials" '["youtube"]' "$TEST_TMP/upgraded-warp.json"
  assert_succeeds "upgraded rules should contain no deprecated download fields" \
    jq -e 'all(.route.rule_set[]; (has("download_detour") | not) and .http_client == {detour:"sbox-warp-direct"})' \
      "$TEST_TMP/upgraded-warp.json"
  assert_succeeds "warp-off should recognize legacy managed objects" \
    bash -c '
      script=$1; input=$2; output=$3; set --; source "$script"
      warp_remove_config "$input" "$output"
      jq -e "(.route.rule_set | length) == 0" "$output"
    ' _ "$INSTALL_SCRIPT" "$TEST_TMP/legacy-warp.json" "$TEST_TMP/legacy-off.json"

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

  jq '.route.rule_set = [{"type":"local","tag":"sbox-warp-geosite-Custom","path":"/tmp/user.srs"}]' "$base" \
    > "$TEST_TMP/conflict-uppercase-ruleset.json"
  assert_fails "every prefix-shaped rule-set collision should fail before removal" \
    merge_warp_config "$TEST_TMP/conflict-uppercase-ruleset.json" "$credentials" '["youtube"]' "$TEST_TMP/conflict-uppercase-ruleset-result.json"

  jq '.endpoints |= map(if .tag == "sbox-warp-out" then . + {listen_port: 51820} else . end)' "$merged" \
    > "$TEST_TMP/conflict-customized-endpoint.json"
  assert_fails "managed endpoint with extra settings should not be overwritten" \
    merge_warp_config "$TEST_TMP/conflict-customized-endpoint.json" "$credentials" '["youtube"]' "$TEST_TMP/conflict-customized-endpoint-result.json"

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

  if [[ -n "$SING_BOX_TEST_BIN" && -x "$SING_BOX_TEST_BIN" ]]; then
    cat > "$TEST_TMP/schema-base.json" <<'JSON'
{
  "inbounds": [{"type":"mixed","tag":"test-in","listen":"127.0.0.1","listen_port":2080}],
  "outbounds": [{"type":"direct"}]
}
JSON
    assert_succeeds "generated WARP config should pass sing-box schema validation" \
      merge_warp_config "$TEST_TMP/schema-base.json" "$credentials" '["youtube"]' "$TEST_TMP/schema-merged.json"
    assert_succeeds "sing-box should accept the generated WARP config" \
      "$SING_BOX_TEST_BIN" check -c "$TEST_TMP/schema-merged.json"
    assert_succeeds "rule downloader must start without deprecated-feature overrides" \
      python3 "$ROOT_DIR/tests/check-ruleset-startup.py" \
        "$SING_BOX_TEST_BIN" "$TEST_TMP/schema-merged.json"
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

  SERVER_CONF_OVERRIDE="$config" WARP_CREDENTIALS_FILE_OVERRIDE="$credentials" \
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

  SERVER_CONF_OVERRIDE="$config" WARP_CREDENTIALS_FILE_OVERRIDE="$credentials" \
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
  assert_mode_600 "$config" "server config mode should be 600"
  assert_mode_600 "$credentials" "credential mode should be 600"
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

  local snapshot_config="$TEST_TMP/snapshot-copy-config.json"
  local snapshot_credentials="$TEST_TMP/snapshot-copy-credentials.json"
  local staged_config="$TEST_TMP/snapshot-copy-staged-config.json"
  local staged_credentials="$TEST_TMP/snapshot-copy-staged-credentials.json"
  printf 'original-config\n' > "$snapshot_config"
  printf 'original-credentials\n' > "$snapshot_credentials"
  printf 'new-config\n' > "$staged_config"
  printf 'new-credentials\n' > "$staged_credentials"
  assert_fails "failed snapshot copy should abort before replacing formal files" \
    env SERVER_CONF_OVERRIDE="$snapshot_config" WARP_CREDENTIALS_FILE_OVERRIDE="$snapshot_credentials" \
      bash -c '
        script=$1; staged_config=$2; staged_credentials=$3
        set --; source "$script"
        backup_existing_files() { return 0; }
        service_restart() { return 0; }
        cp() {
          local destination="${@: -1}"
          if [[ "$destination" == */.sbox-warp-snapshot.*/config.json ]]; then
            : > "$destination"
            return 1
          fi
          command cp "$@"
        }
        if warp_commit_staged_files "$staged_config" "$staged_credentials"; then
          exit 0
        fi
        exit 1
      ' _ "$INSTALL_SCRIPT" "$staged_config" "$staged_credentials"
  assert_eq 'original-config' "$(cat "$snapshot_config")" \
    "snapshot failure should preserve formal config"
  assert_eq 'original-credentials' "$(cat "$snapshot_credentials")" \
    "snapshot failure should preserve formal credentials"

  local restore_root="$TEST_TMP/restore-copy"
  mkdir -p "$restore_root"
  printf 'original-config\n' > "$restore_root/config.json"
  printf 'original-credentials\n' > "$restore_root/credentials.json"
  printf 'new-config\n' > "$restore_root/staged-config.json"
  printf 'new-credentials\n' > "$restore_root/staged-credentials.json"
  assert_fails "failed rollback copy should retain intact recovery snapshots" \
    env SERVER_CONF_OVERRIDE="$restore_root/config.json" WARP_CREDENTIALS_FILE_OVERRIDE="$restore_root/credentials.json" \
      bash -c '
        script=$1; staged_config=$2; staged_credentials=$3; recovery_path=$4
        set --; source "$script"
        backup_existing_files() { return 0; }
        service_restart() { return 1; }
        cp() {
          local destination="${@: -1}"
          if [[ "$destination" == */.sbox-warp-restore.* ]]; then
            : > "$destination"
            return 1
          fi
          command cp "$@"
        }
        status=0
        warp_commit_staged_files "$staged_config" "$staged_credentials" || status=$?
        snapshot_dir="$(find "$(dirname "$SERVER_CONF")" -maxdepth 1 -type d -name ".sbox-warp-snapshot.*" -print -quit)"
        [[ -n "$snapshot_dir" ]]
        [[ "$(cat "$snapshot_dir/config.json")" == original-config ]]
        [[ "$(cat "$snapshot_dir/credentials.json")" == original-credentials ]]
        [[ -s "$SERVER_CONF" && -s "$WARP_CREDENTIALS_FILE" ]]
        printf "%s\n" "$snapshot_dir" > "$recovery_path"
        exit "$status"
      ' _ "$INSTALL_SCRIPT" "$restore_root/staged-config.json" \
        "$restore_root/staged-credentials.json" "$restore_root/recovery-path"
  assert_succeeds "rollback failure should leave a recovery snapshot path" \
    test -s "$restore_root/recovery-path"

  local backup_failure_root="$TEST_TMP/backup-failure"
  mkdir -p "$backup_failure_root"
  printf 'must-survive\n' > "$backup_failure_root/config.json"
  assert_fails "failed backup copy should be reported before a transaction continues" \
    env SERVER_CONF_OVERRIDE="$backup_failure_root/config.json" \
      WARP_CREDENTIALS_FILE_OVERRIDE="$backup_failure_root/missing-credentials.json" \
      BACKUP_ROOT_OVERRIDE="$backup_failure_root/backups" \
      bash -c '
        script=$1
        set --; source "$script"
        cp() {
          local source="${@: -2:1}"
          [[ "$source" != "$SERVER_CONF" ]] || return 1
          command cp "$@"
        }
        if backup_existing_files injected-failure; then
          exit 0
        fi
        exit 1
      ' _ "$INSTALL_SCRIPT"
  assert_eq 'must-survive' "$(cat "$backup_failure_root/config.json")" \
    "backup failure should not alter the source file"
}

test_integration() {
  local prompt_state
  local config="$TEST_TMP/install-config.json"
  local credentials="$TEST_TMP/install-credentials.json"
  local staged_credentials="$TEST_TMP/install-staged-credentials.json"
  local check_count="$TEST_TMP/install-check-count"
  local backup_root="$TEST_TMP/backups"

  prompt_state="$(printf 'y\nYouTube， netflix youtube\n' | bash -c '
    script=$1; set --; source "$script"
    warp_prompt_rules
    printf "%s|%s|%s\n" "$WARP_RULES_EXPLICIT" "$WARP_RULES_INPUT" "$WARP_RULES_JSON"
  ' _ "$INSTALL_SCRIPT")"
  assert_eq '1|YouTube， netflix youtube|["youtube","netflix"]' "$prompt_state" \
    "interactive WARP prompt should accept and normalize multiple rules"

  write_test_credentials "$staged_credentials"
  SERVER_CONF_OVERRIDE="$config" WARP_CREDENTIALS_FILE_OVERRIDE="$credentials" \
    bash -c '
      script=$1; staged_credentials=$2; check_count=$3
      set --; source "$script"
      CONFIG_POLICY=new
      INSTALL_DIRECT=1
      DIRECT_PORT=23456
      DIRECT_TARGET_ADDRESS=example.com
      DIRECT_TARGET_PORT=443
      WARP_INSTALL_ACTIVE=1
      WARP_INSTALL_RULES_JSON="[\"youtube\"]"
      WARP_STAGED_CREDENTIALS="$staged_credentials"
      backup_existing_files() { return 0; }
      run_sing_box() {
        count=0; [[ -f "$check_count" ]] && count="$(cat "$check_count")"
        printf "%s\n" "$(( count + 1 ))" > "$check_count"
        return 0
      }
      write_server_config
      finalize_install_transaction
      warp_finalize_install_transaction
    ' _ "$INSTALL_SCRIPT" "$staged_credentials" "$check_count"
  assert_eq '1' "$(cat "$check_count")" \
    "combined protocol and WARP config should receive one final check"
  assert_succeeds "fresh install should contain protocol and selective WARP routing" \
    jq -e '
      ([.inbounds[] | select(.tag == "direct-in")] | length) == 1
      and ([.endpoints[] | select(.tag == "sbox-warp-out")] | length) == 1
      and .route.rules[1].rule_set == ["sbox-warp-geosite-youtube"]
    ' "$config"
  assert_mode_600 "$credentials" "combined install should place staged credentials in mode 600"

  local rollback_root="$TEST_TMP/combined-rollback"
  mkdir -p "$rollback_root"
  printf 'old-config\n' > "$rollback_root/config.json"
  printf 'old-credentials\n' > "$rollback_root/credentials.json"
  assert_fails "nested service restart failure should roll back combined installation" \
    env SERVER_CONF_OVERRIDE="$rollback_root/config.json" \
      WARP_CREDENTIALS_FILE_OVERRIDE="$rollback_root/credentials.json" \
      bash -c '
        script=$1; restart_count=$2
        set --; source "$script"
        WARP_INSTALL_ACTIVE=1
        begin_install_transaction
        INSTALL_SERVICE_WAS_ACTIVE=1
        INSTALL_SERVICE_WAS_ENABLED=1
        printf "new-config\n" > "$SERVER_CONF"
        printf "new-credentials\n" > "$WARP_CREDENTIALS_FILE"
        CONFIG_POLICY=merge
        detect_server_ip() { return 0; }
        service_reload() { return 0; }
        service_enable() { return 0; }
        service_restart() {
          local count=0
          [[ -f "$restart_count" ]] && count="$(cat "$restart_count")"
          count=$(( count + 1 ))
          printf "%s\n" "$count" > "$restart_count"
          (( count > 1 ))
        }
        complete_install_after_config
      ' _ "$INSTALL_SCRIPT" "$rollback_root/restart-count"
  assert_eq '2' "$(cat "$rollback_root/restart-count")" \
    "combined rollback should restart the restored service"
  assert_eq 'old-config' "$(cat "$rollback_root/config.json")" \
    "combined rollback should restore config"
  assert_eq 'old-credentials' "$(cat "$rollback_root/credentials.json")" \
    "combined rollback should restore credentials"

  assert_succeeds "combined install should back up before staging new credentials" \
    env SERVER_CONF_OVERRIDE="$config" WARP_CREDENTIALS_FILE_OVERRIDE="$credentials" bash -c '
      script=$1; order_file=$2; fixture=$3
      set --; source "$script"
      WARP_RULES_EXPLICIT=1
      WARP_RULES_JSON="[\"youtube\"]"
      warp_validate_rule_urls() { return 0; }
      backup_existing_files() { printf "backup\n" >> "$order_file"; }
      warp_prepare_credentials() {
        printf "prepare\n" >> "$order_file"
        cp "$fixture" "$1"
      }
      warp_prepare_install_state
      [[ "$(tr "\n" " " < "$order_file")" == "backup prepare " ]]
      warp_finalize_install_transaction
    ' _ "$INSTALL_SCRIPT" "$TEST_TMP/install-order.txt" "$credentials"

  BACKUP_ROOT_OVERRIDE="$backup_root" SERVER_CONF_OVERRIDE="$config" WARP_CREDENTIALS_FILE_OVERRIDE="$credentials" \
    bash -c '
      script=$1; set --; source "$script"
      backup_existing_files integration-test
      test -f "$LAST_BACKUP_DIR/$(basename "$WARP_CREDENTIALS_FILE")"
      declare -f restore_latest_backup | grep -F "\$WARP_CREDENTIALS_FILE" >/dev/null
      declare -f cleanup_all_sing_box_configs | grep -F "\$WARP_CREDENTIALS_FILE" >/dev/null
    ' _ "$INSTALL_SCRIPT" || fail "backup, restore, and full cleanup should include WARP credentials"
  PASS_COUNT=$(( PASS_COUNT + 1 ))

  assert_succeeds "legacy wrappers should forward all WARP arguments" \
    bash -c '
      for script in "$@"; do
        grep -F '\''"$@"'\'' "$script" >/dev/null
      done
    ' _ "$ROOT_DIR/install-anytls-reality.sh" "$ROOT_DIR/install-hysteria2-surge.sh" "$ROOT_DIR/reality.sh"

  assert_succeeds "README should document WARP commands, source, and secret path" \
    bash -c '
      grep -Fq -- "--warp-rules" "$1"
      grep -Fq "MetaCubeX/meta-rules-dat" "$1"
      grep -Fq "/etc/sing-box/sbox-warp-credentials.credentials" "$1"
    ' _ "$ROOT_DIR/README.md"
}

test_hardening() {
  local backup_test="$TEST_TMP/backup-safety"
  local keep_backup="$backup_test/managed-keep"
  local old_backup="$backup_test/managed-old"
  local unrelated="$backup_test/unrelated"
  local port_config="$TEST_TMP/port-config.json"
  local tx_config="$TEST_TMP/transaction/config.json"
  local tx_output="$TEST_TMP/transaction/output"

  assert_fails "general option without value should fail clearly" \
    source_with_args --server-host
  assert_fails "restore and uninstall should conflict" \
    source_with_args --restore --uninstall all
  assert_fails "external action and --mode should conflict" \
    source_with_args --uninstall all --mode anytls

  assert_succeeds "server host validation should accept IPv4, IPv6 and DNS" \
    bash -c '
      script=$1; set --; source "$script"
      validate_server_host 1.2.3.4
      validate_server_host 2001:db8::1
      validate_server_host example.com
      [[ "$(url_host 2001:db8::1)" == "[2001:db8::1]" ]]
    ' _ "$INSTALL_SCRIPT"
  assert_fails "server host validation should reject invalid values" \
    bash -c 'script=$1; set --; source "$script"; validate_server_host "bad host"' _ "$INSTALL_SCRIPT"

  mkdir -p "$keep_backup" "$old_backup" "$unrelated"
  printf 'keep\n' > "$keep_backup/config.json"
  printf 'old\n' > "$old_backup/config.json"
  printf 'unrelated\n' > "$unrelated/important"
  : > "$keep_backup/.sbox-reality-backup"
  : > "$old_backup/.sbox-reality-backup"
  assert_succeeds "backup pruning should only delete marked installer backups" \
    env SERVER_CONF_OVERRIDE="$TEST_TMP/backup-safety/config.json" \
      BACKUP_ROOT_OVERRIDE="$backup_test" bash -c '
        script=$1; keep=$2; old=$3; unrelated=$4
        set --; source "$script"
        prune_backups_except "$keep"
        [[ -d "$keep" && ! -e "$old" && -f "$unrelated/important" ]]
      ' _ "$INSTALL_SCRIPT" "$keep_backup" "$old_backup" "$unrelated"

  jq -n '{
    inbounds: [
      {type:"anytls", tag:"anytls-in", listen:"::", listen_port:25000}
    ],
    outbounds: [{type:"direct"}]
  }' > "$port_config"
  assert_fails "new protocol should not reuse an unselected managed port" \
    env SERVER_CONF_OVERRIDE="$port_config" bash -c '
      script=$1; set --; source "$script"
      CONFIG_POLICY=merge
      INSTALL_VLESS=1
      validate_planned_port_against_existing_config tcp 25000 VLESS
    ' _ "$INSTALL_SCRIPT"
  assert_succeeds "replacing the same managed tag may reuse its port" \
    env SERVER_CONF_OVERRIDE="$port_config" bash -c '
      script=$1; set --; source "$script"
      CONFIG_POLICY=merge
      INSTALL_ANYTLS=1
      validate_planned_port_against_existing_config tcp 25000 AnyTLS
    ' _ "$INSTALL_SCRIPT"

  mkdir -p "$(dirname "$tx_config")" "$tx_output"
  printf 'old-config\n' > "$tx_config"
  printf 'old-client\n' > "$tx_output/client.json"
  assert_succeeds "generic install transaction should restore config and client outputs" \
    env SERVER_CONF_OVERRIDE="$tx_config" OUTPUT_DIR_OVERRIDE="$tx_output" bash -c '
      script=$1; config=$2; output=$3
      set --; source "$script"
      begin_install_transaction
      printf "new-config\n" > "$config"
      rm -f "$output/client.json"
      printf "new-client\n" > "$output/new.json"
      rollback_install_transaction
      [[ "$(cat "$config")" == "old-config" ]]
      [[ "$(cat "$output/client.json")" == "old-client" ]]
      [[ ! -e "$output/new.json" ]]
    ' _ "$INSTALL_SCRIPT" "$tx_config" "$tx_output"
}

test_protocol_schema() {
  local schema_dir="$TEST_TMP/protocol-schema"

  if [[ -z "$SING_BOX_TEST_BIN" || ! -x "$SING_BOX_TEST_BIN" ]]; then
    echo "SKIP: protocol schema tests require SING_BOX_TEST_BIN"
    return 0
  fi

  mkdir -p "$schema_dir/output"
  openssl req -x509 -nodes \
    -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -days 1 -keyout "$schema_dir/key.pem" -out "$schema_dir/cert.pem" \
    -subj "/CN=www.bing.com" >/dev/null 2>&1

  bash -c '
    script=$1; directory=$2
    set --; source "$script"
    OUTPUT_DIR="$directory/output"
    ANYTLS_CLIENT_OUT="$OUTPUT_DIR/anytls.json"
    VLESS_CLIENT_OUT="$OUTPUT_DIR/vless.json"
    HY2_CLIENT_OUT="$OUTPUT_DIR/hy2.json"
    SNELL5_CLIENT_OUT="$OUTPUT_DIR/snell5.json"
    SNELL6_CLIENT_OUT="$OUTPUT_DIR/snell6.json"
    ANYTLS_URL_FILE="$OUTPUT_DIR/anytls-url.txt"
    ANYTLS_SURGE_CONF="$OUTPUT_DIR/anytls-surge.conf"
    VLESS_URL_FILE="$OUTPUT_DIR/vless-url.txt"
    VLESS_SURGE_CONF="$OUTPUT_DIR/vless-surge.conf"
    HY2_URL_FILE="$OUTPUT_DIR/hy2-url.txt"
    SURGE_CONF="$OUTPUT_DIR/hy2-surge.conf"
    SNELL5_URL_FILE="$OUTPUT_DIR/snell5-url.txt"
    SNELL5_SURGE_CONF="$OUTPUT_DIR/snell5-surge.conf"
    SNELL6_URL_FILE="$OUTPUT_DIR/snell6-url.txt"
    SNELL6_SURGE_CONF="$OUTPUT_DIR/snell6-surge.conf"
    SNELL_SURGE_CONF="$OUTPUT_DIR/snell-surge.conf"
    INSTALL_ANYTLS=1
    INSTALL_VLESS=1
    INSTALL_HY2=1
    INSTALL_SNELL5=1
    INSTALL_SNELL6=1
    ANYTLS_PORT=21001
    VLESS_PORT=21002
    HY2_PORT=21003
    SNELL5_PORT=21004
    SNELL6_PORT=21005
    REALITY_DOMAIN=www.apple.com
    VLESS_DOMAIN=www.apple.com
    ANYTLS_PRIVATE_KEY=aLGSmo_RQnjngdPeQve8roGrhNM5bbDmJOrMFgT4Hk8
    ANYTLS_PUBLIC_KEY=OseeW1QCGvBgl7Eb0SKAQiuwH1VWYEzjoRn9xncV1FM
    ANYTLS_PASSWORD=anytls-test-password
    ANYTLS_SHORT_ID=0123456789abcdef
    VLESS_PRIVATE_KEY=aLGSmo_RQnjngdPeQve8roGrhNM5bbDmJOrMFgT4Hk8
    VLESS_PUBLIC_KEY=OseeW1QCGvBgl7Eb0SKAQiuwH1VWYEzjoRn9xncV1FM
    VLESS_UUID=509c1e7b-9f5d-42b8-91b2-ddb8cf2a8673
    VLESS_SHORT_ID=0123456789abcdef
    HY2_PASSWORD=hy2-test-password
    HY2_SNI=www.bing.com
    OBFS=gecko
    OBFS_PASSWORD="obfs-\\\"quoted-password"
    GECKO_MIN_PACKET_SIZE=512
    GECKO_MAX_PACKET_SIZE=1200
    HY2_PORT_HOPPING=on
    HOP_INTERVAL=30
    NORMALIZED_HOP_PORTS=20000-50000
    SERVER_PORTS_JSON="[\"20000:50000\"]"
    SNELL5_PSK=snell5-test-password
    SNELL6_PSK=snell6-test-password
    SNELL5_OBFS_MODE=http
    SNELL6_MODE=default
    CERT_PATH="$directory/cert.pem"
    KEY_PATH="$directory/key.pem"
    SERVER_IP=127.0.0.1
    SERVER_URL_HOST=127.0.0.1
    PROXY_NAME=HY2
    write_fresh_server_config "$directory/server.json"
    write_anytls_client
    write_vless_client
    write_hy2_clients
    write_snell_clients
  ' _ "$INSTALL_SCRIPT" "$schema_dir"

  assert_succeeds "all generated server and client configs should pass the current Alpha schema" \
    bash -c '
      binary=$1
      shift
      for config in "$@"; do
        "$binary" check -c "$config"
      done
    ' _ "$SING_BOX_TEST_BIN" \
      "$schema_dir/server.json" \
      "$schema_dir/output/anytls.json" \
      "$schema_dir/output/vless.json" \
      "$schema_dir/output/hy2.json" \
      "$schema_dir/output/snell5.json" \
      "$schema_dir/output/snell6.json"
}

test_directory_loading() {
  local config_dir="$TEST_TMP/service-config"
  local credential_name
  mkdir -p "$config_dir"
  printf '{"outbounds":[{"type":"direct"}]}\n' > "$config_dir/config.json"
  credential_name="$(env -u WARP_CREDENTIALS_FILE_OVERRIDE bash -c '
    script=$1; set --; source "$script"; basename "$WARP_CREDENTIALS_FILE"
  ' _ "$INSTALL_SCRIPT")"
  write_test_credentials "$config_dir/$credential_name"
  if [[ -n "$SING_BOX_TEST_BIN" && -x "$SING_BOX_TEST_BIN" ]]; then
    assert_succeeds "service directory loading must ignore WARP credentials" \
      "$SING_BOX_TEST_BIN" check -C "$config_dir"
  fi
  rm -f "$config_dir/$credential_name"
  write_test_credentials "$config_dir/sbox-warp-credentials.json"
  assert_succeeds "legacy credentials should migrate without changing their contents" \
    env WARP_CREDENTIALS_FILE_OVERRIDE="$config_dir/sbox-warp-credentials.credentials" bash -c '
      script=$1; set --; source "$script"
      legacy="$(dirname "$WARP_CREDENTIALS_FILE")/sbox-warp-credentials.json"
      digest="$(sha256sum "$legacy" | cut -d " " -f 1)"
      warp_migrate_legacy_credentials
      [[ ! -e "$legacy" ]]
      [[ "$(sha256sum "$WARP_CREDENTIALS_FILE" | cut -d " " -f 1)" == "$digest" ]]
      [[ "$OSTYPE" == cygwin* || "$(stat -c %a "$WARP_CREDENTIALS_FILE")" == 600 ]]
      warp_migrate_legacy_credentials
    ' _ "$INSTALL_SCRIPT"
  if [[ -n "$SING_BOX_TEST_BIN" && -x "$SING_BOX_TEST_BIN" ]]; then
    assert_succeeds "directory loading should work after migrating legacy credentials" \
      "$SING_BOX_TEST_BIN" check -C "$config_dir"
  fi
  assert_succeeds "different legacy credentials must never overwrite current credentials" \
    env WARP_CREDENTIALS_FILE_OVERRIDE="$config_dir/sbox-warp-credentials.credentials" bash -c '
      script=$1; set --; source "$script"
      legacy="$(dirname "$WARP_CREDENTIALS_FILE")/sbox-warp-credentials.json"
      printf "different\n" > "$legacy"
      digest="$(sha256sum "$WARP_CREDENTIALS_FILE" | cut -d " " -f 1)"
      if warp_migrate_legacy_credentials; then exit 1; fi
      [[ -f "$legacy" ]]
      [[ "$(sha256sum "$WARP_CREDENTIALS_FILE" | cut -d " " -f 1)" == "$digest" ]]
      rm "$legacy"
    ' _ "$INSTALL_SCRIPT"
  assert_succeeds "old backup credentials should restore directly to the safe filename" \
    env WARP_CREDENTIALS_FILE_OVERRIDE="$config_dir/sbox-warp-credentials.credentials" bash -c '
      script=$1; set --; source "$script"
      backup="$(mktemp -d)"
      cp "$WARP_CREDENTIALS_FILE" "$backup/sbox-warp-credentials.json"
      rm "$WARP_CREDENTIALS_FILE"
      restore_file_from_backup "$backup" "$WARP_CREDENTIALS_FILE"
      cmp -s "$WARP_CREDENTIALS_FILE" "$backup/sbox-warp-credentials.json"
      [[ ! -e "$(dirname "$WARP_CREDENTIALS_FILE")/sbox-warp-credentials.json" ]]
      rm -r "$backup"
    ' _ "$INSTALL_SCRIPT"
}

case "$TEST_GROUP" in
  directory)
    test_directory_loading
    ;;
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
  integration)
    test_integration
    ;;
  hardening)
    test_hardening
    ;;
  schema)
    test_protocol_schema
    ;;
  all)
    test_directory_loading
    test_normalization
    test_credentials
    test_config
    test_transaction
    test_integration
    test_hardening
    test_protocol_schema
    ;;
  *)
    fail "unknown test group: $TEST_GROUP"
    ;;
esac

printf 'PASS: %d assertions (%s)\n' "$PASS_COUNT" "$TEST_GROUP"
