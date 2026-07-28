#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_supported_host
for command_name in awk cmp find git jq sed sort tar; do
    require_command "$command_name"
done
require_sha256_tool
timeout_bin=$(timeout_executable)
runtime=$(runtime_backend)
if [ "$runtime" = docker ]; then
    # A first-time online preparation or offline import may not have loaded the
    # fixed image yet. The run/scoring entry points perform that stronger check.
    require_docker
else
    require_bwrap_runtime
fi

printf 'host: %s %s\n' "$(uname -s)" "$(uname -m)"
printf 'runtime: %s\n' "$runtime"
if [ "$runtime" = docker ]; then
    docker_os=$(docker info --format '{{.OSType}}')
    docker_arch=$(docker info --format '{{.Architecture}}')
    printf 'docker: %s\n' "$(docker version --format '{{.Server.Version}}')"
    printf 'docker server: %s/%s\n' "$docker_os" "$docker_arch"
else
    printf 'bubblewrap: %s\n' "$("${BWRAP_COMMAND[@]}" --version)"
    printf 'rootfs SHA-256: %s\n' "$(cat "$ROOTFS_SHA256_FILE")"
fi
printf 'timeout: %s\n' "$timeout_bin"
printf 'workspace filesystem: %s\n' "$(workspace_filesystem_type)"
printf 'host check: PASS\n'
