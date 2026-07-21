#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

printf 'run_id\tmodel\tresolved\tbuild\tblack_box\thidden\tregression\tfull\ttest_files_ignored\teval_seconds\n'
[ -d "$RUNS_DIR" ] || exit 0
find "$RUNS_DIR" -mindepth 2 -maxdepth 2 -name result.json -print0 2>/dev/null \
    | sort -z \
    | while IFS= read -r -d '' result; do
        jq -r '[.run_id,.model,.evaluation.resolved,.evaluation.build_passed,
                .evaluation.black_box_passed,.evaluation.upstream_hidden_passed,
                .evaluation.regression_passed,
                (.evaluation.full_regression_passed // "not-run"),
                .evaluation.candidate_test_files_ignored,
                .evaluation.durations_seconds.total] | @tsv' "$result"
    done
