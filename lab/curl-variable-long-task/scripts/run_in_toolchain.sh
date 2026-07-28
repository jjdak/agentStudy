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

runtime=$(runtime_backend)
if [ "$runtime" = docker ]; then
    security_args=()
    while IFS= read -r security_arg; do
        security_args+=("$security_arg")
    done < <(container_common_args)
    tty_args=()
    if [ -t 0 ] && [ -t 1 ]; then
        tty_args=(-t)
    fi
    exec docker run --rm -i \
        ${tty_args[@]+"${tty_args[@]}"} \
        "${security_args[@]}" \
        --user "$(id -u):$(id -g)" \
        --env HOME=/home/agent \
        --env LANG=C.UTF-8 \
        --env GIT_CONFIG_COUNT=1 \
        --env GIT_CONFIG_KEY_0=safe.directory \
        --env GIT_CONFIG_VALUE_0=/workspace \
        --workdir /workspace \
        --mount "type=bind,src=$workspace,dst=/workspace" \
        "$IMAGE_REF" "$@"
else
    set_bwrap_command
    bwrap_args=()
    while IFS= read -r bwrap_arg; do
        bwrap_args+=("$bwrap_arg")
    done < <(bwrap_common_args "$workspace")
    exec "${BWRAP_COMMAND[@]}" \
        "${bwrap_args[@]}" \
        --setenv GIT_CONFIG_COUNT 1 \
        --setenv GIT_CONFIG_KEY_0 safe.directory \
        --setenv GIT_CONFIG_VALUE_0 /workspace \
        /usr/bin/prlimit --nproc="$LAB_CONTAINER_PIDS" -- "$@"
fi
