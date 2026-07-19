#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -eq 1 ] || die "usage: $0 <run-id>"
RUN_ID=$1
validate_run_id "$RUN_ID"

require_linux_x86_64
require_docker
require_prepared
require_command timeout

RUN_DIR="$RUNS_DIR/$RUN_ID"
PREDICTION_FILE="$RUN_DIR/prediction.json"
EVAL_DIR="$RUN_DIR/evaluation"
SUMMARY_FILE="$EVAL_DIR/summary.json"

[ -f "$PREDICTION_FILE" ] || die "prediction not found; run collect_patch.sh first"
[ ! -e "$EVAL_DIR" ] || die "evaluation already exists; use a new run ID instead of overwriting $EVAL_DIR"

MODEL_NAME=$(jq -er '.[0].model_name_or_path' "$PREDICTION_FILE")
PATCH_SHA=$(sha256sum "$RUN_DIR/patch.diff" | awk '{print $1}')
HARNESS_RUN_ID="lab-${RUN_ID}"
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$EVAL_DIR"
chmod 700 "$EVAL_DIR"

set +e
(
    cd "$EVAL_DIR"
    export HF_DATASETS_OFFLINE=1
    export HF_HUB_OFFLINE=1
    export HF_HOME="$RUNTIME_DIR/hf-cache"
    timeout 45m "$VENV_DIR/bin/python" -m swebench.harness.run_evaluation \
        --dataset_name "$DATASET_FILE" \
        --instance_ids "$LAB_TASK_ID" \
        --predictions_path "$PREDICTION_FILE" \
        --run_id "$HARNESS_RUN_ID" \
        --namespace swebench \
        --max_workers 1 \
        --timeout 1800 \
        --cache_level instance \
        >harness-output.log 2>&1
)
HARNESS_EXIT=$?
set -e

FINISHED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

REPORT_FILE=$(find "$EVAL_DIR" -maxdepth 1 -type f -name "*.${HARNESS_RUN_ID}.json" -print -quit)
if [ -z "$REPORT_FILE" ]; then
    jq -n \
        --arg run_id "$RUN_ID" \
        --arg task_id "$LAB_TASK_ID" \
        --arg model "$MODEL_NAME" \
        --arg patch_sha256 "$PATCH_SHA" \
        --arg started_at "$STARTED_AT" \
        --arg finished_at "$FINISHED_AT" \
        --argjson harness_exit "$HARNESS_EXIT" \
        '{
            run_id: $run_id,
            task_id: $task_id,
            model_name_or_path: $model,
            patch_sha256: $patch_sha256,
            started_at: $started_at,
            finished_at: $finished_at,
            harness_exit: $harness_exit,
            completed: false,
            resolved: false,
            error: "SWE-bench report was not generated"
        }' >"$SUMMARY_FILE"
else
    jq \
        --arg run_id "$RUN_ID" \
        --arg task_id "$LAB_TASK_ID" \
        --arg model "$MODEL_NAME" \
        --arg patch_sha256 "$PATCH_SHA" \
        --arg started_at "$STARTED_AT" \
        --arg finished_at "$FINISHED_AT" \
        --argjson harness_exit "$HARNESS_EXIT" \
        '. + {
            run_id: $run_id,
            task_id: $task_id,
            model_name_or_path: $model,
            patch_sha256: $patch_sha256,
            started_at: $started_at,
            finished_at: $finished_at,
            harness_exit: $harness_exit,
            completed: (.completed_instances == 1),
            resolved: (.resolved_instances == 1)
        }' "$REPORT_FILE" >"$SUMMARY_FILE"
fi

jq --slurpfile evaluation "$SUMMARY_FILE" \
    '.evaluation = $evaluation[0]' \
    "$RUN_DIR/metadata.json" >"$RUN_DIR/metadata.json.tmp"
mv "$RUN_DIR/metadata.json.tmp" "$RUN_DIR/metadata.json"

jq . "$SUMMARY_FILE"
printf '\nharness output: %s\n' "$EVAL_DIR/harness-output.log"

[ "$HARNESS_EXIT" -eq 0 ] || exit "$HARNESS_EXIT"
