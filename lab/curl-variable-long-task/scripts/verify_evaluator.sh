#!/usr/bin/env bash

set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_scoring_assets
self_check="$EVALUATOR_DIR/self-check"
rm -rf "$self_check" "$EVALUATOR_DIR/VERIFIED.json"
mkdir -p "$self_check"
: >"$self_check/empty.patch"

printf 'control 1/2: unmodified baseline must build but fail correctness gates\n'
"$SCRIPT_DIR/score_patch.sh" "$self_check/empty.patch" "$self_check/negative"
negative_exit=$?
negative_build=$(jq -r .build_passed "$self_check/negative/summary.json")
negative_resolved=$(jq -r .resolved "$self_check/negative/summary.json")
if [ "$negative_exit" -eq 0 ] || [ "$negative_build" != true ] || [ "$negative_resolved" != false ]; then
    die "negative control invalid: expected build=true and resolved=false"
fi

printf 'control 2/2: trusted reference patch must pass every required gate\n'
"$SCRIPT_DIR/score_patch.sh" "$GOLD_PATCH" "$self_check/gold"
gold_exit=$?
gold_resolved=$(jq -r .resolved "$self_check/gold/summary.json")
if [ "$gold_exit" -ne 0 ] || [ "$gold_resolved" != true ]; then
    die "gold control failed; inspect $self_check/gold"
fi

jq -n \
    --arg verified_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg source_sha256 "$LAB_SOURCE_SHA256" \
    --arg gold_patch_sha256 "$LAB_GOLD_PATCH_SHA256" \
    --arg oracle_sha256 "$(sha256_file "$EVALUATOR_DIR/black_box_tests.sh")" \
    --arg hidden_manifest_sha256 "$(sha256_file "$EVALUATOR_DIR/hidden-tests.sha256")" \
    --arg image_id "$(image_id)" \
    '{verified_at:$verified_at,source_sha256:$source_sha256,
      gold_patch_sha256:$gold_patch_sha256,oracle_sha256:$oracle_sha256,
      hidden_manifest_sha256:$hidden_manifest_sha256,image_id:$image_id,
      controls:{negative:{build_passed:true,resolved:false},gold:{resolved:true}}}' \
    >"$EVALUATOR_DIR/VERIFIED.json"

printf 'evaluator verification: PASS\n'
cat "$EVALUATOR_DIR/VERIFIED.json"
