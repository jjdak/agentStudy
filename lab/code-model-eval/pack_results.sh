#!/usr/bin/env bash
set -euo pipefail

[ "$#" -eq 1 ] || { echo "usage: $0 RESULTS_DIRECTORY" >&2; exit 2; }
result_dir=$(realpath "$1")
[ -f "$result_dir/manifest.json" ] || { echo "manifest.json not found" >&2; exit 2; }
archive="${result_dir%/}.tar.gz"
tar -czf "$archive" -C "$(dirname "$result_dir")" "$(basename "$result_dir")"
sha256sum "$archive" >"$archive.sha256"
printf '%s\n%s\n' "$archive" "$archive.sha256"
