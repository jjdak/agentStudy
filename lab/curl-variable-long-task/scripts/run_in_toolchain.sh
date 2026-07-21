#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -ge 1 ] || die "usage: $0 RUN_ID [COMMAND [ARG...]]"
run_id=$1
shift
validate_run_id "$run_id"
require_prepared
workspace="$RUNS_DIR/$run_id/workspace"
[ -d "$workspace/.git" ] || die "run workspace does not exist: $run_id"

if [ "$#" -eq 0 ]; then
    set -- bash
fi

mapfile -t security_args < <(container_common_args)
tty_args=()
if [ -t 0 ] && [ -t 1 ]; then
    tty_args=(-t)
fi
exec docker run --rm -i \
    "${tty_args[@]}" \
    "${security_args[@]}" \
    --user "$(id -u):$(id -g)" \
    --env HOME=/home/agent \
    --env LANG=C.UTF-8 \
    --workdir /workspace \
    --mount "type=bind,src=$workspace,dst=/workspace" \
    "$IMAGE_REF" "$@"
