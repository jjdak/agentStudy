#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAB_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=../config.env
source "$LAB_ROOT/config.env"

DEMO_DIR="$LAB_ROOT/.demo"
DEMO_RUNS_DIR="$LAB_ROOT/demo-runs"
SOURCE_ARCHIVE="$DEMO_DIR/fmt-${LAB_BASE_COMMIT}.tar.gz"
REFERENCE_PATCH="$LAB_ROOT/answers/reference.patch"
SMOKE_SOURCE="$LAB_ROOT/demo/fmt_smoke.cc"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die "missing SHA-256 tool: install sha256sum or shasum"
    fi
}

validate_run_id() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
        || die "run ID must match [A-Za-z0-9][A-Za-z0-9._-]{0,63}"
}

workspace_for() {
    printf '%s/%s/workspace\n' "$DEMO_RUNS_DIR" "$1"
}

check_host() {
    local missing=()
    local command_name
    for command_name in bash curl git tar c++; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        printf 'Missing commands: %s\n' "${missing[*]}" >&2
        printf 'Ubuntu/Debian: sudo apt-get install build-essential curl git tar\n' >&2
        return 1
    fi
    sha256_file "$LAB_ROOT/config.env" >/dev/null
    printf 'host demo check: PASS\n'
    printf 'compiler: %s\n' "$(c++ --version | sed -n '1p')"
}

prepare() {
    check_host
    mkdir -p "$DEMO_DIR"
    if [ ! -f "$SOURCE_ARCHIVE" ]; then
        local partial="$SOURCE_ARCHIVE.$$.part"
        if ! curl -L --fail --show-error --output "$partial" "$DEMO_SOURCE_URL"; then
            rm -f "$partial"
            die "fmt source download failed"
        fi
        mv "$partial" "$SOURCE_ARCHIVE"
    fi
    local actual
    actual=$(sha256_file "$SOURCE_ARCHIVE")
    [ "$actual" = "$DEMO_SOURCE_SHA256" ] \
        || die "source SHA-256 mismatch: expected $DEMO_SOURCE_SHA256, got $actual"
    printf 'fmt source ready: %s\n' "$SOURCE_ARCHIVE"
}

new_run() {
    local run_id=$1
    validate_run_id "$run_id"
    prepare

    local run_dir="$DEMO_RUNS_DIR/$run_id"
    local workspace="$run_dir/workspace"
    [ ! -e "$run_dir" ] || die "demo run already exists: $run_id"
    mkdir -p "$workspace"
    tar -xzf "$SOURCE_ARCHIVE" --strip-components=1 -C "$workspace"

    git -C "$workspace" init --quiet
    git -C "$workspace" config user.name "Agent Study Demo"
    git -C "$workspace" config user.email "demo@example.invalid"
    git -C "$workspace" config commit.gpgsign false
    git -C "$workspace" add --all --force
    git -C "$workspace" commit --quiet -m "demo baseline: $LAB_TASK_ID"
    cp "$LAB_ROOT/task/demo_task.md" "$workspace/TASK.md"
    printf '\nTASK.md\nbuild-demo/\n' >>"$workspace/.git/info/exclude"

    printf 'demo run created: %s\n' "$run_dir"
    printf 'workspace: %s\n' "$workspace"
    printf 'task: %s/TASK.md\n' "$workspace"
    printf 'start Codex here: codex -C %q\n' "$workspace"
    printf 'test from this Lab: ./scripts/demo.sh test %q\n' "$run_id"
}

test_run() {
    local run_id=$1
    validate_run_id "$run_id"
    local workspace
    workspace=$(workspace_for "$run_id")
    [ -d "$workspace/.git" ] || die "demo run not found: $run_id"

    mkdir -p "$workspace/build-demo"
    c++ -std=c++11 -DFMT_HEADER_ONLY -pthread \
        -I"$workspace/include" \
        "$SMOKE_SOURCE" \
        -o "$workspace/build-demo/fmt-smoke"
    "$workspace/build-demo/fmt-smoke"
}

answer() {
    local run_id=$1
    local mode=${2:---show}
    validate_run_id "$run_id"
    local workspace
    workspace=$(workspace_for "$run_id")
    [ -d "$workspace/.git" ] || die "demo run not found: $run_id"
    case "$mode" in
        --show)
            printf 'reference answer: %s\n\n' "$REFERENCE_PATCH"
            sed -n '1,240p' "$REFERENCE_PATCH"
            ;;
        --apply)
            git -C "$workspace" apply --check "$REFERENCE_PATCH" \
                || die "reference patch does not apply cleanly; use a fresh run or inspect your changes"
            git -C "$workspace" apply "$REFERENCE_PATCH"
            printf 'reference answer applied to %s\n' "$workspace"
            printf 'next: ./scripts/demo.sh test %s\n' "$run_id"
            ;;
        *) die "answer mode must be --show or --apply" ;;
    esac
}

usage() {
    cat <<'EOF'
Usage:
  ./scripts/demo.sh check
  ./scripts/demo.sh prepare
  ./scripts/demo.sh new RUN_ID
  ./scripts/demo.sh test RUN_ID
  ./scripts/demo.sh answer RUN_ID [--show|--apply]

This teaching path uses the host compiler directly. It does not require Docker,
Python, SWE-bench, hidden tests, or filesystem isolation.
EOF
}

command_name=${1:-help}
case "$command_name" in
    check) [ "$#" -eq 1 ] || die "usage: $0 check"; check_host ;;
    prepare) [ "$#" -eq 1 ] || die "usage: $0 prepare"; prepare ;;
    new) [ "$#" -eq 2 ] || die "usage: $0 new RUN_ID"; new_run "$2" ;;
    test) [ "$#" -eq 2 ] || die "usage: $0 test RUN_ID"; test_run "$2" ;;
    answer)
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || die "usage: $0 answer RUN_ID [--show|--apply]"
        answer "$2" "${3:---show}"
        ;;
    help|-h|--help) usage ;;
    *) usage >&2; die "unknown demo command: $command_name" ;;
esac
