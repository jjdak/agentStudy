#!/usr/bin/env bash

set -euo pipefail
tool_name=$(basename "$0")
toolchain_dir=$(cd "$(dirname "$0")/.." && pwd)
rootfs_dir="$toolchain_dir/rootfs"
loader="$rootfs_dir/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
library_path="$rootfs_dir/lib/x86_64-linux-gnu:$rootfs_dir/usr/lib/x86_64-linux-gnu"

case "$tool_name" in
    git)
        tool_path=/usr/bin/git
        export GIT_CONFIG_NOSYSTEM=1
        export GIT_CONFIG_GLOBAL=/dev/null
        export GIT_EXEC_PATH="$rootfs_dir/usr/lib/git-core"
        export GIT_TEMPLATE_DIR="$rootfs_dir/usr/share/git-core/templates"
        ;;
    jq) tool_path=/usr/bin/jq ;;
    *) printf 'error: unsupported portable host tool: %s\n' "$tool_name" >&2; exit 1 ;;
esac

[ -x "$loader" ] || {
    printf 'error: portable loader is missing: %s\n' "$loader" >&2
    exit 1
}
[ -x "$rootfs_dir$tool_path" ] || {
    printf 'error: portable tool is missing: %s\n' "$rootfs_dir$tool_path" >&2
    exit 1
}
exec "$loader" --library-path "$library_path" "$rootfs_dir$tool_path" "$@"
