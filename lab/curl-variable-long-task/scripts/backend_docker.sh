#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -ge 3 ] || die "internal usage: backend_docker.sh WORKSPACE INTERACTIVE COMMAND [BIND...]"
workspace=$1
interactive=$2
command_text=$3
shift 3

mapfile -t security_args < <(container_common_args)
docker_args=(run --rm "${security_args[@]}")
if [ "$interactive" = true ]; then
    docker_args+=(-i)
    [ -t 0 ] && [ -t 1 ] && docker_args+=(-t)
fi
docker_args+=(
    --user "$(id -u):$(id -g)"
    --env HOME=/home/agent
    --env LANG=C.UTF-8
    --env ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:abort_on_error=1
    --env UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1
    --workdir /workspace
    --mount "type=bind,src=$workspace,dst=/workspace"
)
for bind_spec in "$@"; do
    IFS=: read -r source destination mode <<<"$bind_spec"
    mount_arg="type=bind,src=$source,dst=$destination"
    [ "${mode:-}" = ro ] && mount_arg+=",readonly"
    docker_args+=(--mount "$mount_arg")
done

exec docker "${docker_args[@]}" "$IMAGE_REF" bash -lc \
    "ulimit -f 262144; $command_text"
