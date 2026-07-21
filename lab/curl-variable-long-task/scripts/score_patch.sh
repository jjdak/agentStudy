#!/usr/bin/env bash

set -uo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    die "usage: $0 PATCH RESULT_DIR [--full]"
fi
patch_file=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
result_dir=$2
full_requested=false
if [ "${3:-}" = --full ]; then
    full_requested=true
elif [ "$#" -eq 3 ]; then
    die "unknown option: $3"
fi
[ -f "$patch_file" ] || die "patch not found: $patch_file"

require_scoring_assets
require_command jq
require_command timeout
mkdir -p "$result_dir"
result_dir=$(cd "$result_dir" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
source_tree="$work/source"
score_started_epoch=$(date +%s)

patch_applied=false
build_passed=false
black_box_passed=false
hidden_passed=false
regression_passed=false
full_passed=false
test_files_ignored=0
patch_exit=0
build_exit=125
black_box_exit=125
hidden_exit=125
regression_exit=125
full_exit=125
build_seconds=0
black_box_seconds=0
hidden_seconds=0
regression_seconds=0
full_seconds=0
LAST_STAGE_SECONDS=0

extract_base "$source_tree"
init_snapshot_repo "$source_tree"

if [ -s "$patch_file" ]; then
    (
        cd "$source_tree"
        git apply --index --whitespace=nowarn "$patch_file"
    ) >"$result_dir/01-patch.log" 2>&1
    patch_exit=$?
else
    printf 'empty control patch: baseline remains unchanged\n' >"$result_dir/01-patch.log"
fi

if [ "$patch_exit" -eq 0 ]; then
    patch_applied=true
    test_files_ignored=$(git -C "$source_tree" diff --cached --name-only HEAD -- tests \
        | awk 'NF {count++} END {print count+0}')

    # Candidate tests are useful during development but cannot define the score.
    git -C "$source_tree" restore --source=HEAD --staged --worktree -- tests
    git -C "$source_tree" clean -q -f -d -- tests
fi

mapfile -t security_args < <(container_common_args)
run_stage() {
    local timeout_seconds=$1
    local log_file=$2
    local command_text=$3
    shift 3
    local stage_started stage_exit
    stage_started=$(date +%s)
    timeout --foreground --kill-after=15s "${timeout_seconds}s" \
        docker run --rm \
        "${security_args[@]}" \
        --user "$(id -u):$(id -g)" \
        --env HOME=/home/agent \
        --env LANG=C.UTF-8 \
        --env ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:abort_on_error=1 \
        --env UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
        --workdir /workspace \
        --mount "type=bind,src=$source_tree,dst=/workspace" \
        "$@" \
        "$IMAGE_REF" bash -lc "$command_text" \
        >"$log_file" 2>&1
    stage_exit=$?
    LAST_STAGE_SECONDS=$(($(date +%s) - stage_started))
    return "$stage_exit"
}

if $patch_applied; then
    build_command=$(cat <<'EOF'
set -euo pipefail
autoreconf -fi
rm -rf build-lab
mkdir build-lab
cd build-lab
../configure \
  --disable-shared --enable-static \
  --without-ssl --without-libpsl --without-zlib --without-brotli \
  --without-zstd --without-libidn2 --disable-ldap --disable-ldaps \
  --disable-manual --disable-dependency-tracking \
  CFLAGS='-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer' \
  LDFLAGS='-fsanitize=address,undefined'
make -j4
cd ..
rm -rf build-cmake
cmake -S . -B build-cmake \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DBUILD_STATIC_CURL=ON \
  -DCURL_ENABLE_SSL=OFF -DCURL_USE_LIBPSL=OFF -DUSE_LIBIDN2=OFF \
  -DCURL_USE_LIBSSH2=OFF -DENABLE_MANUAL=OFF \
  -DCMAKE_DISABLE_FIND_PACKAGE_ZLIB=TRUE \
  -DCMAKE_C_FLAGS='-O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer' \
  -DCMAKE_EXE_LINKER_FLAGS='-fsanitize=address,undefined'
cmake --build build-cmake --parallel 4
EOF
)
    run_stage "$LAB_BUILD_TIMEOUT" "$result_dir/02-build.log" "$build_command"
    build_exit=$?
    build_seconds=$LAST_STAGE_SECONDS
    [ "$build_exit" -eq 0 ] && build_passed=true
fi

if $build_passed; then
    run_stage "$LAB_TEST_TIMEOUT" "$result_dir/03-black-box.log" \
        'CURL_BIN=/workspace/build-lab/src/curl /black_box_tests.sh' \
        --mount "type=bind,src=$EVALUATOR_DIR/black_box_tests.sh,dst=/black_box_tests.sh,readonly"
    black_box_exit=$?
    black_box_seconds=$LAST_STAGE_SECONDS
    [ "$black_box_exit" -eq 0 ] && black_box_passed=true

    for test_id in $LAB_HIDDEN_TESTS; do
        cp "$HIDDEN_TEST_DIR/test${test_id}" "$source_tree/tests/data/test${test_id}"
    done
    hidden_command="make -C build-lab test TFLAGS='-a -s $LAB_HIDDEN_TESTS'"
    run_stage "$LAB_TEST_TIMEOUT" "$result_dir/04-hidden-tests.log" "$hidden_command"
    hidden_exit=$?
    hidden_seconds=$LAST_STAGE_SECONDS
    [ "$hidden_exit" -eq 0 ] && hidden_passed=true

    regression_command="make -C build-lab test TFLAGS='-a -s $LAB_REGRESSION_TESTS'"
    run_stage "$LAB_TEST_TIMEOUT" "$result_dir/05-regression-tests.log" "$regression_command"
    regression_exit=$?
    regression_seconds=$LAST_STAGE_SECONDS
    [ "$regression_exit" -eq 0 ] && regression_passed=true

    if $full_requested; then
        run_stage "$LAB_TEST_TIMEOUT" "$result_dir/06-full-regression.log" \
            "make -C build-lab test TFLAGS='-a -s'"
        full_exit=$?
        full_seconds=$LAST_STAGE_SECONDS
        [ "$full_exit" -eq 0 ] && full_passed=true
    fi
fi

resolved=false
if $patch_applied && $build_passed && $black_box_passed \
    && $hidden_passed && $regression_passed; then
    if ! $full_requested || $full_passed; then
        resolved=true
    fi
fi

if $full_requested; then
    full_json=$full_passed
else
    full_json=null
fi

jq -n \
    --arg evaluated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg patch_sha256 "$(sha256_file "$patch_file")" \
    --arg image_ref "$IMAGE_REF" \
    --arg image_id "$(image_id)" \
    --argjson patch_applied "$patch_applied" \
    --argjson build_passed "$build_passed" \
    --argjson black_box_passed "$black_box_passed" \
    --argjson hidden_passed "$hidden_passed" \
    --argjson regression_passed "$regression_passed" \
    --argjson full_requested "$full_requested" \
    --argjson full_passed "$full_json" \
    --argjson test_files_ignored "$test_files_ignored" \
    --argjson patch_exit "$patch_exit" \
    --argjson build_exit "$build_exit" \
    --argjson black_box_exit "$black_box_exit" \
    --argjson hidden_exit "$hidden_exit" \
    --argjson regression_exit "$regression_exit" \
    --argjson full_exit "$full_exit" \
    --argjson total_seconds "$(($(date +%s) - score_started_epoch))" \
    --argjson build_seconds "$build_seconds" \
    --argjson black_box_seconds "$black_box_seconds" \
    --argjson hidden_seconds "$hidden_seconds" \
    --argjson regression_seconds "$regression_seconds" \
    --argjson full_seconds "$full_seconds" \
    --argjson resolved "$resolved" \
    '{evaluated_at:$evaluated_at,patch_sha256:$patch_sha256,
      image_ref:$image_ref,image_id:$image_id,
      patch_applied:$patch_applied,build_passed:$build_passed,
      black_box_passed:$black_box_passed,upstream_hidden_passed:$hidden_passed,
      regression_passed:$regression_passed,
      full_regression_requested:$full_requested,
      full_regression_passed:$full_passed,
      candidate_test_files_ignored:$test_files_ignored,
      exit_codes:{patch:$patch_exit,build:$build_exit,black_box:$black_box_exit,
                  hidden:$hidden_exit,regression:$regression_exit,full:$full_exit},
      durations_seconds:{total:$total_seconds,build:$build_seconds,
                         black_box:$black_box_seconds,hidden:$hidden_seconds,
                         regression:$regression_seconds,full:$full_seconds},
      resolved:$resolved}' >"$result_dir/summary.json"

(
    cd "$result_dir"
    for artifact in *.log summary.json; do
        [ -f "$artifact" ] || continue
        printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"
    done >artifacts.sha256
)

cat "$result_dir/summary.json"
$resolved
