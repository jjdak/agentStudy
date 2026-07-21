#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_prepared
destination=${1:-$LAB_ROOT/offline-bundles/${LAB_TASK_ID}-$(date -u +%Y%m%dT%H%M%SZ)}
[ ! -e "$destination" ] || die "destination already exists: $destination"
mkdir -p "$destination"

cp "$SOURCE_ARCHIVE" "$destination/source.tar.gz"
cp "$GOLD_PATCH" "$destination/reference.patch"
cp "$LAB_ROOT/config.env" "$destination/config.env"
cp "$RUNTIME_DIR/toolchain/image-id.txt" "$destination/image-id.txt"
cp "$RUNTIME_DIR/toolchain/packages.tsv" "$destination/packages.tsv"
docker save --output "$destination/toolchain-image.tar" "$IMAGE_REF"

(
    cd "$destination"
    for artifact in config.env image-id.txt packages.tsv reference.patch source.tar.gz toolchain-image.tar; do
        printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"
    done >bundle-manifest.sha256
)

printf 'offline bundle: %s\n' "$destination"
printf 'Copy this directory together with the agentStudy repository.\n'
