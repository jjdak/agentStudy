#!/usr/bin/env bash

set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    die "usage: $0 RUN_ID [--full]"
fi
run_id=$1
option=${2:-}
[ -z "$option" ] || [ "$option" = --full ] || die "unknown option: $option"
validate_run_id "$run_id"
require_prepared
run_dir="$RUNS_DIR/$run_id"
[ -f "$run_dir/candidate.patch" ] || die "collect the candidate patch first"

rm -rf "$run_dir/evaluation"
if [ "$option" = --full ]; then
    "$SCRIPT_DIR/score_patch.sh" "$run_dir/candidate.patch" "$run_dir/evaluation" --full
else
    "$SCRIPT_DIR/score_patch.sh" "$run_dir/candidate.patch" "$run_dir/evaluation"
fi
score_exit=$?

jq -s '.[0] * {evaluation:.[1]}' \
    "$run_dir/metadata.json" "$run_dir/evaluation/summary.json" \
    >"$run_dir/result.json"
cat "$run_dir/result.json"
exit "$score_exit"
