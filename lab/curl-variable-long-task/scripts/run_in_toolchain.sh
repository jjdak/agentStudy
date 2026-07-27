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

printf -v command_text '%q ' "$@"
backend_run "$workspace" true "$command_text"
