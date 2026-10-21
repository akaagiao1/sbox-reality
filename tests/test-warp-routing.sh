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

case "$TEST_GROUP" in
  normalization)
    test_normalization
    ;;
  credentials)
    test_credentials
    ;;
  all)
    test_normalization
    test_credentials
    ;;
  config|transaction|integration)
    fail "test group not implemented yet: $TEST_GROUP"
    ;;
  *)
    fail "unknown test group: $TEST_GROUP"
    ;;
esac

printf 'PASS: %d assertions (%s)\n' "$PASS_COUNT" "$TEST_GROUP"
