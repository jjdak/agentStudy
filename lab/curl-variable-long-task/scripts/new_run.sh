#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_prepared
run_id=${1:-$(date -u +%Y%m%dT%H%M%SZ)}
validate_run_id "$run_id"
final_run_dir="$RUNS_DIR/$run_id"
[ ! -e "$final_run_dir" ] || die "run already exists: $run_id"
mkdir -p "$RUNS_DIR"
run_dir="$RUNS_DIR/.${run_id}.tmp.$$"
trap 'rm -rf "$run_dir"' EXIT

mkdir -p "$run_dir"
extract_base "$run_dir/workspace"
init_snapshot_repo "$run_dir/workspace"
baseline_head=$(git -C "$run_dir/workspace" rev-parse HEAD)
baseline_tree=$(git -C "$run_dir/workspace" rev-parse HEAD^{tree})

mkdir -p "$run_dir/workspace/.agent"
cp "$LAB_ROOT/task/agent_task.md" "$run_dir/workspace/.agent/TASK.md"
for name in REPO_MAP SPEC DESIGN TASKS STATUS; do
    cp "$LAB_ROOT/templates/${name}.md" "$run_dir/workspace/.agent/${name}.md"
done
cp "$LAB_ROOT/templates/run-notes.md" "$run_dir/run-notes.md"
cp "$LAB_ROOT/templates/result-report.md" "$run_dir/result-report.md"
printf '\n.agent/\nbuild-lab/\nbuild-cmake/\n' >>"$run_dir/workspace/.git/info/exclude"
exclude_sha256=$(sha256_file "$run_dir/workspace/.git/info/exclude")

jq -n \
    --arg run_id "$run_id" \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg task_id "$LAB_TASK_ID" \
    --arg base_commit "$LAB_BASE_COMMIT" \
    --arg source_sha256 "$LAB_SOURCE_SHA256" \
    --arg prompt_sha256 "$(sha256_file "$LAB_ROOT/task/agent_task.md")" \
    --arg image_ref "$IMAGE_REF" \
    --arg image_id "$(image_id)" \
    --arg baseline_head "$baseline_head" \
    --arg baseline_tree "$baseline_tree" \
    --arg exclude_sha256 "$exclude_sha256" \
    '{run_id:$run_id,created_at:$created_at,task_id:$task_id,
      base_commit:$base_commit,source_sha256:$source_sha256,
      prompt_sha256:$prompt_sha256,image_ref:$image_ref,image_id:$image_id,
      baseline_head:$baseline_head,baseline_tree:$baseline_tree,
      exclude_sha256:$exclude_sha256}' \
    >"$run_dir/metadata.json"

mv "$run_dir" "$final_run_dir"
trap - EXIT
run_dir=$final_run_dir

printf 'run created: %s\n' "$run_id"
printf 'Agent-visible workspace: %s\n' "$run_dir/workspace"
printf 'Task contract: %s\n' "$run_dir/workspace/.agent/TASK.md"
printf 'Tool wrapper: %s %s <command...>\n' "$SCRIPT_DIR/run_in_toolchain.sh" "$run_id"
