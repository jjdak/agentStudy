#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAB_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=../config.env
source "$LAB_ROOT/config.env"

DEMO_DIR="$LAB_ROOT/.demo"
DEMO_RUNS_DIR="$LAB_ROOT/demo-runs"
SOURCE_ARCHIVE="$DEMO_DIR/curl-${LAB_BASE_COMMIT}.tar.gz"
REFERENCE_PATCH="$DEMO_DIR/curl-${LAB_GOLD_COMMIT}.patch"
VISIBLE_TEST="$LAB_ROOT/evaluator/black_box_tests.sh"

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
    for command_name in bash curl git tar cc make autoreconf autoconf automake \
        pkg-config perl; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done
    if ! command -v libtoolize >/dev/null 2>&1 \
        && ! command -v glibtoolize >/dev/null 2>&1; then
        missing+=(libtoolize)
    fi
    if [ "${#missing[@]}" -gt 0 ]; then
        printf 'Missing commands: %s\n' "${missing[*]}" >&2
        printf '%s\n' \
            'Ubuntu/Debian:' \
            '  sudo apt-get install build-essential autoconf automake libtool pkg-config perl curl git' \
            'macOS with Homebrew:' \
            '  brew install autoconf automake libtool pkg-config'
        return 1
    fi
    sha256_file "$LAB_ROOT/config.env" >/dev/null
    printf 'host demo check: PASS\n'
    printf 'compiler: %s\n' "$(cc --version | sed -n '1p')"
}

libtoolize_command() {
    if command -v libtoolize >/dev/null 2>&1; then
        command -v libtoolize
    else
        command -v glibtoolize
    fi
}

download_verified() {
    local url=$1
    local destination=$2
    local expected=$3
    if [ ! -f "$destination" ]; then
        local partial="$destination.$$.part"
        if ! curl -L --fail --show-error --output "$partial" "$url"; then
            rm -f "$partial"
            die "download failed: $url"
        fi
        mv "$partial" "$destination"
    fi
    local actual
    actual=$(sha256_file "$destination")
    [ "$actual" = "$expected" ] \
        || die "SHA-256 mismatch for $destination: expected $expected, got $actual"
}

prepare() {
    check_host
    mkdir -p "$DEMO_DIR"
    download_verified "$LAB_SOURCE_URL" "$SOURCE_ARCHIVE" "$LAB_SOURCE_SHA256"
    download_verified "$LAB_GOLD_PATCH_URL" "$REFERENCE_PATCH" "$LAB_GOLD_PATCH_SHA256"
    printf 'curl source ready: %s\n' "$SOURCE_ARCHIVE"
    printf 'visible reference answer: %s\n' "$REFERENCE_PATCH"
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

    mkdir -p "$workspace/.agent"
    cp "$LAB_ROOT/task/demo_task.md" "$workspace/TASK.md"
    for name in REPO_MAP SPEC DESIGN TASKS STATUS; do
        cp "$LAB_ROOT/templates/${name}.md" "$workspace/.agent/${name}.md"
    done
    printf '\nTASK.md\n.agent/\nbuild-demo/\n' >>"$workspace/.git/info/exclude"

    printf '%s\n' \
        "run_id=$run_id" \
        "base_commit=$LAB_BASE_COMMIT" \
        "reference_commit=$LAB_GOLD_COMMIT" \
        "created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        >"$run_dir/run-info.txt"

    printf 'demo run created: %s\n' "$run_dir"
    printf 'workspace: %s\n' "$workspace"
    printf 'task: %s/TASK.md\n' "$workspace"
    printf 'start Codex here: codex -C %q\n' "$workspace"
    printf 'test from this Lab: ./scripts/demo.sh test %q\n' "$run_id"
}

configure_and_build() {
    local workspace=$1
    local build_dir="$workspace/build-demo"
    mkdir -p "$build_dir"

    # A long-task patch can change generated metadata and shared struct layouts.
    # Reusing objects from the previous candidate can otherwise produce false
    # crashes, so the teaching test favors a clean result over build speed.
    if [ -f "$build_dir/Makefile" ]; then
        printf 'Cleaning previous objects... '
        if make -C "$build_dir" clean >"$build_dir/clean.log" 2>&1; then
            printf 'PASS\n'
        else
            tail -n 80 "$build_dir/clean.log" >&2
            die "clean failed; full log: $build_dir/clean.log"
        fi
    fi

    # Re-run generation and configure so a candidate patch that changes
    # Makefile.am, configure.ac, or generated option metadata is picked up.
    printf 'Generating Autotools files... '
    local libtoolize_bin
    libtoolize_bin=$(libtoolize_command)
    if (
        cd "$workspace"
        LIBTOOLIZE="$libtoolize_bin" autoreconf -fi
    ) >"$build_dir/autoreconf.log" 2>&1; then
        printf 'PASS\n'
    else
        tail -n 80 "$build_dir/autoreconf.log" >&2
        die "Autotools generation failed; full log: $build_dir/autoreconf.log"
    fi

    printf 'Configuring minimal host build... '
    if (
        cd "$build_dir"
        ../configure \
            --disable-shared \
            --enable-static \
            --without-ssl \
            --without-libpsl \
            --without-zlib \
            --without-brotli \
            --without-zstd \
            --without-libidn2 \
            --without-libssh2 \
            --disable-ldap \
            --disable-ldaps \
            --disable-manual
    ) >"$build_dir/configure.log" 2>&1; then
        printf 'PASS\n'
    else
        tail -n 80 "$build_dir/configure.log" >&2
        die "configure failed; full log: $build_dir/configure.log"
    fi

    local jobs=${DEMO_JOBS:-2}
    printf 'Building curl with %s job(s)... ' "$jobs"
    if make -C "$build_dir" -j "$jobs" >"$build_dir/build.log" 2>&1; then
        printf 'PASS\n'
    else
        tail -n 120 "$build_dir/build.log" >&2
        die "build failed; full log: $build_dir/build.log"
    fi
}

test_run() {
    local run_id=$1
    local mode=${2:---quick}
    validate_run_id "$run_id"
    local workspace
    workspace=$(workspace_for "$run_id")
    [ -d "$workspace/.git" ] || die "demo run not found: $run_id"

    check_host
    configure_and_build "$workspace"
    CURL_BIN="$workspace/build-demo/src/curl" "$VISIBLE_TEST"

    case "$mode" in
        --quick) ;;
        --regression)
            printf 'Running 8 selected upstream regression tests... '
            if make -C "$workspace/build-demo" test \
                TFLAGS="-a -s $LAB_REGRESSION_TESTS" \
                >"$workspace/build-demo/regression.log" 2>&1; then
                printf 'PASS\n'
                tail -n 12 "$workspace/build-demo/regression.log"
            else
                tail -n 120 "$workspace/build-demo/regression.log" >&2
                die "regression tests failed; full log: $workspace/build-demo/regression.log"
            fi
            ;;
        *) die "test mode must be --quick or --regression" ;;
    esac
}

answer() {
    local run_id=$1
    local mode=${2:---show}
    validate_run_id "$run_id"
    local workspace
    workspace=$(workspace_for "$run_id")
    [ -d "$workspace/.git" ] || die "demo run not found: $run_id"
    [ -f "$REFERENCE_PATCH" ] || die "reference answer is missing; run: $0 prepare"

    case "$mode" in
        --show)
            printf 'reference answer: %s\n\n' "$REFERENCE_PATCH"
            cat "$REFERENCE_PATCH"
            ;;
        --apply)
            git -C "$workspace" apply --check --whitespace=nowarn "$REFERENCE_PATCH" \
                || die "reference patch does not apply cleanly; use a fresh run or inspect your changes"
            git -C "$workspace" apply --whitespace=nowarn "$REFERENCE_PATCH"
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
  ./scripts/demo.sh test RUN_ID [--quick|--regression]
  ./scripts/demo.sh answer RUN_ID [--show|--apply]

This teaching path builds curl directly on the host. It does not require
Docker, Bubblewrap, hidden tests, or filesystem isolation.
EOF
}

command_name=${1:-help}
case "$command_name" in
    check) [ "$#" -eq 1 ] || die "usage: $0 check"; check_host ;;
    prepare) [ "$#" -eq 1 ] || die "usage: $0 prepare"; prepare ;;
    new) [ "$#" -eq 2 ] || die "usage: $0 new RUN_ID"; new_run "$2" ;;
    test)
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || die "usage: $0 test RUN_ID [--quick|--regression]"
        test_run "$2" "${3:---quick}"
        ;;
    answer)
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || die "usage: $0 answer RUN_ID [--show|--apply]"
        answer "$2" "${3:---show}"
        ;;
    help|-h|--help) usage ;;
    *) usage >&2; die "unknown demo command: $command_name" ;;
esac
