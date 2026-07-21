#!/usr/bin/env bash
# shellcheck disable=SC2034

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAB_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=../config.env
source "$LAB_ROOT/config.env"

RUNTIME_DIR="$LAB_ROOT/.runtime"
DOWNLOAD_DIR="$RUNTIME_DIR/downloads"
SOURCE_ARCHIVE="$DOWNLOAD_DIR/curl-${LAB_BASE_COMMIT}.tar.gz"
GOLD_PATCH="$DOWNLOAD_DIR/curl-${LAB_GOLD_COMMIT}.patch"
EVALUATOR_DIR="$RUNTIME_DIR/evaluator"
HIDDEN_TEST_DIR="$EVALUATOR_DIR/hidden-tests"
RUNS_DIR="$LAB_ROOT/runs"
IMAGE_REF="${LAB_IMAGE_REPOSITORY}:${LAB_IMAGE_TAG}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

verify_sha256() {
    local file=$1
    local expected=$2
    local actual
    actual=$(sha256_file "$file")
    [ "$actual" = "$expected" ] \
        || die "SHA-256 mismatch for $file: expected $expected, got $actual"
}

download_verified() {
    local url=$1
    local destination=$2
    local expected=$3
    local partial="${destination}.$$.part"

    mkdir -p "$(dirname "$destination")"
    if [ -f "$destination" ]; then
        verify_sha256 "$destination" "$expected"
        return
    fi

    curl -L --fail --show-error --output "$partial" "$url"
    verify_sha256 "$partial" "$expected"
    mv "$partial" "$destination"
}

require_linux_x86_64() {
    [ "$(uname -s)" = "Linux" ] || die "this lab requires Linux (WSL2 is supported)"
    case "$(uname -m)" in
        x86_64|amd64) ;;
        *) die "this lab requires x86_64; current architecture: $(uname -m)" ;;
    esac
}

require_docker() {
    require_command docker
    docker info >/dev/null 2>&1 || die "Docker daemon is not reachable"
}

require_downloads() {
    [ -f "$SOURCE_ARCHIVE" ] || die "source archive is missing; run scripts/prepare_online.sh"
    [ -f "$GOLD_PATCH" ] || die "trusted reference patch is missing; run scripts/prepare_online.sh"
    verify_sha256 "$SOURCE_ARCHIVE" "$LAB_SOURCE_SHA256"
    verify_sha256 "$GOLD_PATCH" "$LAB_GOLD_PATCH_SHA256"
}

require_scoring_assets() {
    require_linux_x86_64
    require_downloads
    require_docker
    docker image inspect "$IMAGE_REF" >/dev/null 2>&1 \
        || die "fixed toolchain image is not loaded: $IMAGE_REF"
    [ -x "$EVALUATOR_DIR/black_box_tests.sh" ] \
        || die "evaluator assets are missing; run scripts/prepare_online.sh"
    [ -f "$EVALUATOR_DIR/hidden-tests.sha256" ] \
        || die "hidden tests are missing; run scripts/prepare_online.sh"
    while read -r expected test_file; do
        [ "$(sha256_file "$HIDDEN_TEST_DIR/$test_file")" = "$expected" ] \
            || die "hidden test integrity check failed: $test_file"
    done <"$EVALUATOR_DIR/hidden-tests.sha256"
}

require_prepared() {
    require_scoring_assets
    [ -f "$EVALUATOR_DIR/VERIFIED.json" ] \
        || die "evaluator controls have not passed; run scripts/verify_evaluator.sh"
    require_command jq
    [ "$(jq -r .oracle_sha256 "$EVALUATOR_DIR/VERIFIED.json")" \
        = "$(sha256_file "$EVALUATOR_DIR/black_box_tests.sh")" ] \
        || die "black-box oracle changed after evaluator verification"
    [ "$(jq -r .hidden_manifest_sha256 "$EVALUATOR_DIR/VERIFIED.json")" \
        = "$(sha256_file "$EVALUATOR_DIR/hidden-tests.sha256")" ] \
        || die "hidden-test manifest changed after evaluator verification"
    [ "$(jq -r .image_id "$EVALUATOR_DIR/VERIFIED.json")" = "$(image_id)" ] \
        || die "toolchain image changed after evaluator verification"
}

validate_run_id() {
    local run_id=$1
    [[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
        || die "run ID must match [A-Za-z0-9][A-Za-z0-9._-]{0,63}"
}

extract_base() {
    local destination=$1
    mkdir -p "$destination"
    tar -xzf "$SOURCE_ARCHIVE" -C "$destination" --strip-components=1
}

init_snapshot_repo() {
    local destination=$1
    (
        cd "$destination"
        git init -q
        git config user.name "agentStudy evaluator"
        git config user.email "evaluator@invalid"
        git add --all --force
        env GIT_AUTHOR_DATE=2023-07-25T00:00:00Z \
            GIT_COMMITTER_DATE=2023-07-25T00:00:00Z \
            git commit -q -m "trusted curl baseline ${LAB_BASE_COMMIT}"
    )
}

image_id() {
    docker image inspect --format '{{.Id}}' "$IMAGE_REF"
}

container_common_args() {
    printf '%s\n' \
        --platform linux/amd64 \
        --network none \
        --read-only \
        --ipc none \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        --pids-limit "$LAB_CONTAINER_PIDS" \
        --cpus "$LAB_CONTAINER_CPUS" \
        --memory "$LAB_CONTAINER_MEMORY" \
        --tmpfs /tmp:rw,nosuid,nodev,noexec,size=1g \
        --tmpfs /home/agent:rw,nosuid,nodev,size=256m
}
