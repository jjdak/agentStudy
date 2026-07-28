#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    die "usage: $0 RUN_ID [DESTINATION]"
fi
run_id=$1
validate_run_id "$run_id"
run_dir="$RUNS_DIR/$run_id"
[ -d "$run_dir/workspace/.agent" ] || die "run not found: $run_id"
[ -f "$run_dir/candidate.patch" ] || die "candidate patch is missing; run collect_patch.sh first"
[ -f "$run_dir/result.json" ] || die "result is missing; run evaluate.sh first"

destination=${2:-$LAB_ROOT/reports/$run_id}
[ ! -e "$destination" ] || die "destination already exists: $destination"
destination_parent=$(dirname "$destination")
mkdir -p "$destination_parent"
publish_tmp="$destination_parent/.${run_id}.publish.$$"
trap 'rm -rf "$publish_tmp"' EXIT
mkdir -p "$publish_tmp/agent-state" "$publish_tmp/evaluation"

for artifact in metadata.json run-notes.md process-report.md result-report.md \
    candidate.patch candidate.stat candidate.files result.json; do
    [ -f "$run_dir/$artifact" ] || die "run artifact is missing: $artifact"
    cp "$run_dir/$artifact" "$publish_tmp/$artifact"
done

for artifact in REPO_MAP.md SPEC.md DESIGN.md TASKS.md STATUS.md; do
    cp "$run_dir/workspace/.agent/$artifact" "$publish_tmp/agent-state/$artifact"
done

for artifact in 01-patch.log 02-build.log 03-black-box.log \
    05-regression-tests.log 06-full-regression.log summary.json \
    artifacts.sha256; do
    [ -f "$run_dir/evaluation/$artifact" ] || continue
    cp "$run_dir/evaluation/$artifact" "$publish_tmp/evaluation/$artifact"
done

printf '%s\n' \
    '# Hidden evaluator log intentionally excluded' \
    '' \
    'The raw hidden-test log and hidden test files are not published. The signed' \
    'summary and original artifact checksum manifest are retained for audit.' \
    >"$publish_tmp/evaluation/HIDDEN_LOG_NOT_PUBLISHED.md"

(
    cd "$publish_tmp"
    find . -type f ! -name publish-manifest.sha256 -print \
        | LC_ALL=C sort \
        | while IFS= read -r artifact; do
            printf '%s  %s\n' "$(sha256_file "$artifact")" "${artifact#./}"
        done >publish-manifest.sha256
)

mv "$publish_tmp" "$destination"
trap - EXIT
printf 'publishable run report: %s\n' "$destination"
printf 'Review process-report.md and run-notes.md for secrets before git add.\n'
