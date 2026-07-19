#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -eq 1 ] || die "usage: $0 <new-bundle-directory>"
BUNDLE_DIR=$1

require_linux_x86_64
require_docker
require_prepared

for command_name in sha256sum find sort xargs; do
    require_command "$command_name"
done

case "$BUNDLE_DIR" in
    ""|/|.|..) die "refusing unsafe bundle directory: $BUNDLE_DIR" ;;
esac
[ ! -e "$BUNDLE_DIR" ] || die "bundle path already exists: $BUNDLE_DIR"

mkdir -p "$BUNDLE_DIR/wheelhouse"
mkdir -p "$BUNDLE_DIR/licenses"
chmod 700 "$BUNDLE_DIR"

cp "$HARNESS_ARCHIVE" "$BUNDLE_DIR/swebench-harness.tar.gz"
cp "$DATASET_FILE" "$BUNDLE_DIR/swebench-multilingual-test.parquet"
cp "$LAB_ROOT/requirements.lock" "$BUNDLE_DIR/requirements.lock"
cp "$LAB_ROOT/config.env" "$BUNDLE_DIR/config.env"
cp "$LAB_ROOT/THIRD_PARTY_NOTICES.md" "$BUNDLE_DIR/THIRD_PARTY_NOTICES.md"
cp "$LAB_ROOT/licenses/SWE-bench-LICENSE" "$BUNDLE_DIR/licenses/SWE-bench-LICENSE"
cp "$LAB_ROOT/licenses/fmt-LICENSE" "$BUNDLE_DIR/licenses/fmt-LICENSE"

docker save "$IMAGE_REF" --output "$BUNDLE_DIR/instance-image.tar"

export PIP_DISABLE_PIP_VERSION_CHECK=1
"$VENV_DIR/bin/python" -m pip download \
    --requirement "$LAB_ROOT/requirements.lock" \
    --dest "$BUNDLE_DIR/wheelhouse"

{
    printf 'task_id=%s\n' "$LAB_TASK_ID"
    printf 'target=linux/x86_64\n'
    printf 'python=3.11\n'
    printf 'harness_commit=%s\n' "$LAB_HARNESS_COMMIT"
    printf 'dataset_revision=%s\n' "$LAB_DATASET_REVISION"
    printf 'image=%s\n' "$IMAGE_REF"
    printf 'image_digest=%s\n' "$LAB_IMAGE_DIGEST"
    printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$BUNDLE_DIR/BUNDLE_INFO.txt"

(
    cd "$BUNDLE_DIR"
    find . -type f ! -name 'MANIFEST.sha256*' -print0 \
        | sort -z \
        | xargs -0 sha256sum >MANIFEST.sha256.tmp
    mv MANIFEST.sha256.tmp MANIFEST.sha256
)

chmod -R u+rwX,go-rwx "$BUNDLE_DIR"

printf 'offline bundle created: %s\n' "$BUNDLE_DIR"
printf 'verify before transfer: (cd %q && sha256sum -c MANIFEST.sha256)\n' "$BUNDLE_DIR"
