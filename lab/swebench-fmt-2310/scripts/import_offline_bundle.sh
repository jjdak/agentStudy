#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -eq 1 ] || die "usage: $0 <bundle-directory>"
BUNDLE_DIR=$1

require_linux_x86_64
require_python_311
require_docker

for command_name in cmp git jq tar sha256sum timeout; do
    require_command "$command_name"
done

[ -d "$BUNDLE_DIR" ] || die "bundle directory not found: $BUNDLE_DIR"
[ -f "$BUNDLE_DIR/MANIFEST.sha256" ] || die "bundle manifest not found"
[ ! -e "$RUNTIME_DIR" ] || die ".runtime already exists; import into a clean lab copy or move it aside"

(
    cd "$BUNDLE_DIR"
    sha256sum -c MANIFEST.sha256
)

for required_file in \
    swebench-harness.tar.gz \
    swebench-multilingual-test.parquet \
    requirements.lock \
    instance-image.tar; do
    [ -f "$BUNDLE_DIR/$required_file" ] || die "bundle file missing: $required_file"
done

cmp -s "$BUNDLE_DIR/requirements.lock" "$LAB_ROOT/requirements.lock" \
    || die "bundle requirements.lock does not match this lab version"
cmp -s "$BUNDLE_DIR/config.env" "$LAB_ROOT/config.env" \
    || die "bundle config.env does not match this lab version"

mkdir -p "$DOWNLOAD_DIR" "$HARNESS_DIR" "$EVALUATOR_DIR" "$RUNTIME_DIR/hf-cache"
chmod 700 "$RUNTIME_DIR" "$DOWNLOAD_DIR" "$HARNESS_DIR" "$EVALUATOR_DIR"

cp "$BUNDLE_DIR/swebench-harness.tar.gz" "$HARNESS_ARCHIVE"
cp "$BUNDLE_DIR/swebench-multilingual-test.parquet" "$DATASET_FILE"
verify_sha256 "$HARNESS_ARCHIVE" "$LAB_HARNESS_SHA256"
verify_sha256 "$DATASET_FILE" "$LAB_DATASET_SHA256"

tar -xzf "$HARNESS_ARCHIVE" --strip-components=1 -C "$HARNESS_DIR"
"$LAB_PYTHON" -m venv "$VENV_DIR"

export PIP_DISABLE_PIP_VERSION_CHECK=1
"$VENV_DIR/bin/python" -m pip install \
    --no-index \
    --find-links "$BUNDLE_DIR/wheelhouse" \
    --requirement "$LAB_ROOT/requirements.lock"
"$VENV_DIR/bin/python" -m pip install \
    --no-index \
    --find-links "$BUNDLE_DIR/wheelhouse" \
    --no-deps \
    "$HARNESS_DIR"

docker load --input "$BUNDLE_DIR/instance-image.tar"
docker image inspect "$IMAGE_REF" >/dev/null 2>&1 \
    || die "loaded bundle does not contain expected image tag: $IMAGE_REF"

printf '%s\n' "$LAB_HARNESS_COMMIT" >"$RUNTIME_DIR/HARNESS_COMMIT"
printf '%s\n' "$LAB_DATASET_REVISION" >"$RUNTIME_DIR/DATASET_REVISION"

"$SCRIPT_DIR/verify_evaluator.sh"

printf 'offline import complete\n'
printf 'next: %s/scripts/new_run.sh run-001\n' "$LAB_ROOT"
