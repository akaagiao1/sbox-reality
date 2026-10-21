#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
INSTALL_SCRIPT="$ROOT_DIR/install.sh"
TEST_GROUP="${1:-all}"
PASS_COUNT=0

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

case "$TEST_GROUP" in
  normalization)
    test_normalization
    ;;
  all)
    test_normalization
    ;;
  credentials|config|transaction|integration)
    fail "test group not implemented yet: $TEST_GROUP"
    ;;
  *)
    fail "unknown test group: $TEST_GROUP"
    ;;
esac

printf 'PASS: %d assertions (%s)\n' "$PASS_COUNT" "$TEST_GROUP"
