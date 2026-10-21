#!/usr/bin/env bash
set -euo pipefail

run_local_main() {
  local source_path script_dir
  source_path="${BASH_SOURCE[0]}"
  [[ -f "$source_path" ]] || return 1
  script_dir="$(cd "$(dirname "$source_path")" && pwd -P)"
  [[ -f "$script_dir/install.sh" ]] || return 1
  exec bash "$script_dir/install.sh" "$@"
}

echo "提示：reality.sh 已合并到统一安装脚本 install.sh。" >&2
run_local_main "$@" || true

temporary_script="$(mktemp)"
trap 'rm -f "$temporary_script"' EXIT
curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors \
  --connect-timeout 10 --max-time 60 \
  -o "$temporary_script" \
  https://raw.githubusercontent.com/akaagiao1/sbox-reality/main/install.sh
bash "$temporary_script" "$@"
