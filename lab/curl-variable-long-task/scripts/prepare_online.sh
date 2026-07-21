#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

"$SCRIPT_DIR/check_host.sh"
mkdir -p "$DOWNLOAD_DIR" "$RUNTIME_DIR/toolchain"

download_verified "$LAB_SOURCE_URL" "$SOURCE_ARCHIVE" "$LAB_SOURCE_SHA256"
download_verified "$LAB_GOLD_PATCH_URL" "$GOLD_PATCH" "$LAB_GOLD_PATCH_SHA256"

docker build --platform linux/amd64 \
    --build-arg "BASE_IMAGE=$LAB_BASE_IMAGE" \
    --tag "$IMAGE_REF" \
    "$LAB_ROOT/docker"

[ "$(docker image inspect --format '{{.Architecture}}' "$IMAGE_REF")" = amd64 ] \
    || die "built image is not linux/amd64"
image_id >"$RUNTIME_DIR/toolchain/image-id.txt"
docker run --rm --platform linux/amd64 --network none "$IMAGE_REF" \
    dpkg-query -W -f='${Package}\t${Version}\n' \
    | sort >"$RUNTIME_DIR/toolchain/packages.tsv"

"$SCRIPT_DIR/prepare_evaluator.sh"
"$SCRIPT_DIR/verify_evaluator.sh"

printf '\nPreparation complete. The toolchain and evaluator controls are verified.\n'
printf 'Create a fresh run with: %s/new_run.sh\n' "$SCRIPT_DIR"
