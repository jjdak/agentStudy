#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -ge 1 ] || die "usage: $0 RUN_ID [MODEL_LABEL]"
run_id=$1
model_label=${2:-unspecified}
validate_run_id "$run_id"
run_dir="$RUNS_DIR/$run_id"
workspace="$run_dir/workspace"
[ -f "$run_dir/metadata.json" ] || die "run metadata not found: $run_id"

expected_head=$(jq -r .baseline_head "$run_dir/metadata.json")
actual_head=$(git -C "$workspace" rev-parse HEAD)
[ "$actual_head" = "$expected_head" ] \
    || die "Agent changed the baseline commit or history; expected $expected_head, got $actual_head"
expected_tree=$(jq -r .baseline_tree "$run_dir/metadata.json")
[ "$(git -C "$workspace" rev-parse HEAD^{tree})" = "$expected_tree" ] \
    || die "baseline Git tree no longer matches run metadata"
expected_exclude=$(jq -r .exclude_sha256 "$run_dir/metadata.json")
[ "$expected_exclude" != null ] \
    && [ "$(sha256_file "$workspace/.git/info/exclude")" = "$expected_exclude" ] \
    || die "Agent changed .git/info/exclude; refusing to collect an incomplete patch"

(
    cd "$workspace"
    git add --intent-to-add --all
    git diff --binary HEAD -- . ':(exclude).agent/**' >"$run_dir/candidate.patch"
    git diff --stat HEAD -- . ':(exclude).agent/**' >"$run_dir/candidate.stat"
    git diff --name-status HEAD -- . ':(exclude).agent/**' >"$run_dir/candidate.files"
)

patch_bytes=$(wc -c <"$run_dir/candidate.patch" | tr -d ' ')
[ "$patch_bytes" -gt 0 ] || die "candidate patch is empty"
[ "$patch_bytes" -le "$LAB_MAX_PATCH_BYTES" ] \
    || die "candidate patch is too large: $patch_bytes bytes"

jq --arg model "$model_label" \
    --arg collected_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg patch_sha256 "$(sha256_file "$run_dir/candidate.patch")" \
    --argjson patch_bytes "$patch_bytes" \
    '. + {model:$model,collected_at:$collected_at,
          patch_sha256:$patch_sha256,patch_bytes:$patch_bytes}' \
    "$run_dir/metadata.json" >"$run_dir/metadata.json.tmp"
mv "$run_dir/metadata.json.tmp" "$run_dir/metadata.json"

printf 'patch: %s\n' "$run_dir/candidate.patch"
printf 'SHA-256: %s\n' "$(sha256_file "$run_dir/candidate.patch")"
printf 'bytes: %s\n' "$patch_bytes"
