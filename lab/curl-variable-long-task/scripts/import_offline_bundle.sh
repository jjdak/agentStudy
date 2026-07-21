#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -eq 1 ] || die "usage: $0 BUNDLE_DIRECTORY"
bundle=$(cd "$1" && pwd)
"$SCRIPT_DIR/check_host.sh"

for artifact in bundle-manifest.sha256 config.env image-id.txt packages.tsv \
    reference.patch source.tar.gz toolchain-image.tar; do
    [ -f "$bundle/$artifact" ] || die "bundle artifact missing: $artifact"
done
(
    cd "$bundle"
    while read -r expected artifact; do
        [ "$(sha256_file "$artifact")" = "$expected" ] \
            || die "bundle SHA-256 mismatch: $artifact"
    done <bundle-manifest.sha256
)

cmp -s "$bundle/config.env" "$LAB_ROOT/config.env" \
    || die "bundle config does not match this lab revision"
verify_sha256 "$bundle/source.tar.gz" "$LAB_SOURCE_SHA256"
verify_sha256 "$bundle/reference.patch" "$LAB_GOLD_PATCH_SHA256"

mkdir -p "$DOWNLOAD_DIR" "$RUNTIME_DIR/toolchain"
cp "$bundle/source.tar.gz" "$SOURCE_ARCHIVE"
cp "$bundle/reference.patch" "$GOLD_PATCH"
cp "$bundle/image-id.txt" "$RUNTIME_DIR/toolchain/image-id.txt"
cp "$bundle/packages.tsv" "$RUNTIME_DIR/toolchain/packages.tsv"
docker load --input "$bundle/toolchain-image.tar"
[ "$(image_id)" = "$(cat "$bundle/image-id.txt")" ] \
    || die "loaded toolchain image ID does not match the bundle"

"$SCRIPT_DIR/prepare_evaluator.sh"
"$SCRIPT_DIR/verify_evaluator.sh"
printf 'offline import and evaluator verification: PASS\n'
