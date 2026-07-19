#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -ge 3 ] || die "usage: $0 <run-id> -- <command> [args...]"
RUN_ID=$1
shift
[ "$1" = "--" ] || die "expected -- before the command"
shift
validate_run_id "$RUN_ID"
[ "$#" -gt 0 ] || die "missing command"

if [ -n "${LAB_ALLOWED_RUN_ID:-}" ] && [ "$RUN_ID" != "$LAB_ALLOWED_RUN_ID" ]; then
    die "run ID is outside the allowed tool scope: $RUN_ID"
fi

require_linux_x86_64
require_docker
require_prepared

WORKSPACE="$RUNS_DIR/$RUN_ID/workspace"
[ -d "$WORKSPACE/.git" ] || die "run workspace not found: $WORKSPACE"

CONTAINER_CPUS=${LAB_CONTAINER_CPUS:-4}
CONTAINER_MEMORY=${LAB_CONTAINER_MEMORY:-8g}

docker run --rm \
    --network none \
    --read-only \
    --security-opt no-new-privileges \
    --cap-drop ALL \
    --pids-limit 512 \
    --cpus "$CONTAINER_CPUS" \
    --memory "$CONTAINER_MEMORY" \
    --user "$(id -u):$(id -g)" \
    --env XDG_CACHE_HOME=/tmp/cache \
    --tmpfs /tmp:rw,nosuid,nodev,size=2g \
    --tmpfs /root:rw,nosuid,nodev,size=64m \
    --volume "$WORKSPACE:/workspace:rw" \
    --workdir /workspace \
    "$IMAGE_REF" \
    "$@"
