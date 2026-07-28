#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$(uname -s)" = Linux ] || die "portable runtime requires Linux"
case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "portable runtime requires x86_64; current architecture: $(uname -m)" ;;
esac
for command_name in awk cmp find gzip sed sort tar unshare; do
    require_command "$command_name"
done
require_sha256_tool
timeout_bin=$(timeout_executable)

if ! unshare --user --map-root-user --net true; then
    die "unprivileged user/network namespaces are unavailable; Bubblewrap cannot run"
fi

printf 'host: %s %s\n' "$(uname -s)" "$(uname -m)"
printf 'kernel: %s\n' "$(uname -r)"
printf 'timeout: %s\n' "$timeout_bin"
printf 'workspace filesystem: %s\n' "$(workspace_filesystem_type)"
df -h "$LAB_ROOT"
printf 'portable host check: PASS\n'
