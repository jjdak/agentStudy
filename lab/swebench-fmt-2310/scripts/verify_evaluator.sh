#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_linux_x86_64
require_docker
require_prepared

GOLD_DIR="$EVALUATOR_DIR/gold-smoke"
REPORT_FILE="$GOLD_DIR/gold.lab-gold-smoke.json"

if [ -f "$REPORT_FILE" ] && jq -e '.resolved_instances == 1 and .error_instances == 0' "$REPORT_FILE" >/dev/null; then
    printf 'gold evaluator smoke test already passed: %s\n' "$REPORT_FILE"
    exit 0
fi

if [ -e "$GOLD_DIR" ]; then
    die "incomplete gold smoke directory exists; move it aside before retrying: $GOLD_DIR"
fi

mkdir -p "$GOLD_DIR"
chmod 700 "$EVALUATOR_DIR" "$GOLD_DIR"

(
    cd "$GOLD_DIR"
    export HF_DATASETS_OFFLINE=1
    export HF_HUB_OFFLINE=1
    export HF_HOME="$RUNTIME_DIR/hf-cache"
    timeout 45m "$VENV_DIR/bin/python" -m swebench.harness.run_evaluation \
        --dataset_name "$DATASET_FILE" \
        --instance_ids "$LAB_TASK_ID" \
        --predictions_path gold \
        --run_id lab-gold-smoke \
        --namespace swebench \
        --max_workers 1 \
        --timeout 1800 \
        --cache_level instance \
        >harness-output.log 2>&1
)

[ -f "$REPORT_FILE" ] || die "gold smoke report was not generated; inspect $GOLD_DIR/harness-output.log"
jq -e '.resolved_instances == 1 and .error_instances == 0' "$REPORT_FILE" >/dev/null \
    || die "official gold patch did not resolve the task; inspect $GOLD_DIR"

printf 'gold evaluator smoke test passed: %s\n' "$REPORT_FILE"
