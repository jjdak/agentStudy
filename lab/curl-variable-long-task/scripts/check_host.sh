#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_linux_x86_64
require_docker
for command_name in awk cmp curl find git jq sed sha256sum sort tar timeout; do
    require_command "$command_name"
done

docker_arch=$(docker info --format '{{.Architecture}}')
[ "$docker_arch" = "x86_64" ] || [ "$docker_arch" = "amd64" ] \
    || die "Docker engine must run linux/amd64 containers; reported: $docker_arch"

printf 'host: %s %s\n' "$(uname -s)" "$(uname -m)"
printf 'docker: %s\n' "$(docker version --format '{{.Server.Version}}')"
printf 'docker architecture: %s\n' "$docker_arch"
printf 'workspace filesystem: %s\n' "$(df -T "$LAB_ROOT" | tail -1 | awk '{print $2}')"
printf 'host check: PASS\n'
