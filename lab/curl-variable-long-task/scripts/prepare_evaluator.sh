#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_downloads
require_command git
require_command tar

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

rm -rf "$EVALUATOR_DIR"
mkdir -p "$HIDDEN_TEST_DIR"
extract_base "$tmp/source"
init_snapshot_repo "$tmp/source"
(
    cd "$tmp/source"
    git apply --index --whitespace=nowarn "$GOLD_PATCH"
)

for test_id in $LAB_HIDDEN_TESTS; do
    source_file="$tmp/source/tests/data/test${test_id}"
    [ -f "$source_file" ] || die "reference patch did not create test${test_id}"
    cp "$source_file" "$HIDDEN_TEST_DIR/test${test_id}"
done

cp "$LAB_ROOT/evaluator/black_box_tests.sh" "$EVALUATOR_DIR/black_box_tests.sh"
chmod 0555 "$EVALUATOR_DIR/black_box_tests.sh"
chmod 0444 "$HIDDEN_TEST_DIR"/*
(
    cd "$HIDDEN_TEST_DIR"
    for test_file in test*; do
        printf '%s  %s\n' "$(sha256_file "$test_file")" "$test_file"
    done >"$EVALUATOR_DIR/hidden-tests.sha256"
)
chmod 0444 "$EVALUATOR_DIR/hidden-tests.sha256"

printf 'evaluator assets prepared: %s\n' "$EVALUATOR_DIR"
printf 'hidden tests: %s\n' "$LAB_HIDDEN_TESTS"
