#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

"$SCRIPT_DIR/check_host.sh"

mkdir -p "$DOWNLOAD_DIR" "$EVALUATOR_DIR" "$RUNTIME_DIR/pip-cache" "$RUNTIME_DIR/hf-cache"
chmod 700 "$RUNTIME_DIR" "$DOWNLOAD_DIR" "$EVALUATOR_DIR"

download_verified "$LAB_HARNESS_URL" "$HARNESS_ARCHIVE" "$LAB_HARNESS_SHA256"
download_verified "$LAB_DATASET_URL" "$DATASET_FILE" "$LAB_DATASET_SHA256"

if [ ! -d "$HARNESS_DIR" ]; then
    mkdir -p "$HARNESS_DIR"
    tar -xzf "$HARNESS_ARCHIVE" --strip-components=1 -C "$HARNESS_DIR"
fi

[ -f "$HARNESS_DIR/swebench/__init__.py" ] || die "invalid harness extraction: $HARNESS_DIR"

if [ ! -d "$VENV_DIR" ]; then
    "$LAB_PYTHON" -m venv "$VENV_DIR"
fi

export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_CACHE_DIR="$RUNTIME_DIR/pip-cache"
"$VENV_DIR/bin/python" -m pip install --requirement "$LAB_ROOT/requirements.lock"
"$VENV_DIR/bin/python" -m pip install --no-deps "$HARNESS_DIR"

docker pull "$IMAGE_DIGEST_REF"
docker tag "$IMAGE_DIGEST_REF" "$IMAGE_REF"

repo_digests=$(docker image inspect "$IMAGE_DIGEST_REF" --format '{{json .RepoDigests}}')
printf '%s\n' "$repo_digests" | jq -e --arg expected "${LAB_IMAGE_REPOSITORY}@${LAB_IMAGE_DIGEST}" \
    'index($expected) != null' >/dev/null \
    || die "pulled image digest does not match config.env"

printf '%s\n' "$LAB_HARNESS_COMMIT" >"$RUNTIME_DIR/HARNESS_COMMIT"
printf '%s\n' "$LAB_DATASET_REVISION" >"$RUNTIME_DIR/DATASET_REVISION"

"$SCRIPT_DIR/verify_evaluator.sh"

printf '\npreparation complete\n'
printf 'runtime: %s\n' "$RUNTIME_DIR"
printf 'next: %s/scripts/new_run.sh run-001\n' "$LAB_ROOT"
