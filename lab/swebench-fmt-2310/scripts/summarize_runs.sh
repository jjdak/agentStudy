#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

printf 'run_id\tmodel\tcompleted\tresolved\tharness_exit\tpatch_sha256\tstarted_at\tfinished_at\n'

if [ ! -d "$RUNS_DIR" ]; then
    exit 0
fi

while IFS= read -r summary; do
    jq -r '[
        .run_id,
        .model_name_or_path,
        .completed,
        .resolved,
        .harness_exit,
        .patch_sha256,
        .started_at,
        .finished_at
    ] | @tsv' "$summary"
done < <(find "$RUNS_DIR" -mindepth 3 -maxdepth 3 -type f -path '*/evaluation/summary.json' | LC_ALL=C sort)
