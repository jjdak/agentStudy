#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2034

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAB_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=../config.env
source "$LAB_ROOT/config.env"

RUNTIME_DIR="$LAB_ROOT/.runtime"
DOWNLOAD_DIR="$RUNTIME_DIR/downloads"
HARNESS_DIR="$RUNTIME_DIR/harness"
VENV_DIR="$RUNTIME_DIR/venv"
EVALUATOR_DIR="$RUNTIME_DIR/evaluator"
RUNS_DIR="$LAB_ROOT/runs"
DATASET_FILE="$DOWNLOAD_DIR/swebench-multilingual-test.parquet"
HARNESS_ARCHIVE="$DOWNLOAD_DIR/swebench-harness.tar.gz"
IMAGE_REF="${LAB_IMAGE_REPOSITORY}:${LAB_IMAGE_TAG}"
IMAGE_DIGEST_REF="${LAB_IMAGE_REPOSITORY}@${LAB_IMAGE_DIGEST}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_linux_x86_64() {
    [ "$(uname -s)" = "Linux" ] || die "this lab intentionally requires Linux"
    case "$(uname -m)" in
        x86_64|amd64) ;;
        *) die "this lab requires x86_64; current architecture: $(uname -m)" ;;
    esac
}

require_python_311() {
    require_command "$LAB_PYTHON"
    "$LAB_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)' \
        || die "$LAB_PYTHON must be Python 3.11"
}

require_docker() {
    require_command docker
    docker info >/dev/null 2>&1 || die "Docker daemon is not reachable"
}

require_prepared() {
    [ -x "$VENV_DIR/bin/python" ] || die "evaluator is not prepared; run scripts/prepare_online.sh or import_offline_bundle.sh"
    [ -f "$DATASET_FILE" ] || die "dataset is missing from .runtime"
    [ -d "$HARNESS_DIR/swebench" ] || die "SWE-bench harness is missing from .runtime"
    docker image inspect "$IMAGE_REF" >/dev/null 2>&1 || die "fixed task image is not loaded: $IMAGE_REF"
}

validate_run_id() {
    local run_id=$1
    [[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
        || die "run ID must match [A-Za-z0-9][A-Za-z0-9._-]{0,63}"
}

verify_sha256() {
    local file=$1
    local expected=$2
    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')
    [ "$actual" = "$expected" ] || die "SHA-256 mismatch for $file: expected $expected, got $actual"
}

download_verified() {
    local url=$1
    local destination=$2
    local expected=$3
    local partial="${destination}.$$.part"

    if [ -f "$destination" ]; then
        verify_sha256 "$destination" "$expected"
        return
    fi

    curl -L --fail --show-error --output "$partial" "$url"
    verify_sha256 "$partial" "$expected"
    mv "$partial" "$destination"
}
