#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -eq 2 ] || die "usage: $0 <run-id> <model-name-or-path>"
RUN_ID=$1
MODEL_NAME=$2
validate_run_id "$RUN_ID"
[ -n "$MODEL_NAME" ] || die "model name must not be empty"

RUN_DIR="$RUNS_DIR/$RUN_ID"
WORKSPACE="$RUN_DIR/workspace"
PATCH_FILE="$RUN_DIR/patch.diff"
PREDICTION_FILE="$RUN_DIR/prediction.json"

[ -d "$WORKSPACE/.git" ] || die "run workspace not found: $WORKSPACE"
[ ! -e "$PATCH_FILE" ] || die "patch already collected; create a new run instead of overwriting $PATCH_FILE"

# Intent-to-add makes new files visible to git diff without staging their contents.
git -C "$WORKSPACE" add --intent-to-add --all --force
git -C "$WORKSPACE" diff --binary HEAD -- . >"$PATCH_FILE"

[ -s "$PATCH_FILE" ] || die "Agent produced an empty patch"

PATCH_SHA=$(sha256sum "$PATCH_FILE" | awk '{print $1}')
COLLECTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

git -C "$WORKSPACE" diff --stat HEAD -- . >"$RUN_DIR/diff-stat.txt"
git -C "$WORKSPACE" status --short >"$RUN_DIR/workspace-status.txt"

jq -n \
    --arg instance_id "$LAB_TASK_ID" \
    --arg model_name_or_path "$MODEL_NAME" \
    --rawfile model_patch "$PATCH_FILE" \
    '[{
        instance_id: $instance_id,
        model_name_or_path: $model_name_or_path,
        model_patch: $model_patch
    }]' >"$PREDICTION_FILE"

jq \
    --arg model "$MODEL_NAME" \
    --arg patch_sha "$PATCH_SHA" \
    --arg collected_at "$COLLECTED_AT" \
    '.model_name_or_path = $model
     | .patch_sha256 = $patch_sha
     | .patch_collected_at = $collected_at' \
    "$RUN_DIR/metadata.json" >"$RUN_DIR/metadata.json.tmp"
mv "$RUN_DIR/metadata.json.tmp" "$RUN_DIR/metadata.json"

printf 'patch: %s\n' "$PATCH_FILE"
printf 'SHA-256: %s\n' "$PATCH_SHA"
printf 'prediction: %s\n\n' "$PREDICTION_FILE"
cat "$RUN_DIR/diff-stat.txt"
