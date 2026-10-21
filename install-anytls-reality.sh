#!/usr/bin/env bash
set -euo pipefail

run_local_main() {
  local source_path script_dir
  source_path="${BASH_SOURCE[0]}"
  [[ -f "$source_path" ]] || return 1
  script_dir="$(cd "$(dirname "$source_path")" && pwd -P)"
  [[ -f "$script_dir/install.sh" ]] || return 1
  exec bash "$script_dir/install.sh" --mode anytls "$@"
}

run_local_main "$@" || true

temporary_script="$(mktemp)"
trap 'rm -f "$temporary_script"' EXIT
install_ref="${SBOX_REALITY_INSTALL_REF:-main}"
expected_sha256="${SBOX_REALITY_INSTALL_SHA256:-}"
[[ "$install_ref" =~ ^[A-Za-z0-9._/-]+$ ]] || {
  echo "错误：SBOX_REALITY_INSTALL_REF 格式无效" >&2
  exit 1
}
curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
  --connect-timeout 10 --max-time 60 \
  -o "$temporary_script" \
  "https://raw.githubusercontent.com/akaagiao1/sbox-reality/${install_ref}/install.sh"
if [[ -n "$expected_sha256" ]]; then
  printf '%s  %s\n' "$expected_sha256" "$temporary_script" | sha256sum -c - >/dev/null || {
    echo "错误：install.sh SHA-256 校验失败" >&2
    exit 1
  }
fi
bash "$temporary_script" --mode anytls "$@"
