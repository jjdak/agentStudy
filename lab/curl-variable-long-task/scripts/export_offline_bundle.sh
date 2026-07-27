#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$BACKEND" = docker ] \
    || die "portable bundles must be exported from the verified Docker backend"
require_prepared
destination=${1:-$LAB_ROOT/offline-bundles/${LAB_TASK_ID}-portable-$(date -u +%Y%m%dT%H%M%SZ)}
[ ! -e "$destination" ] || die "destination already exists: $destination"
staging="${destination}.tmp.$$"
container_id=
trap 'if [ -n "$container_id" ]; then docker rm -f "$container_id" >/dev/null 2>&1 || true; fi; rm -rf "$staging"' EXIT
mkdir -p "$staging"

cp "$LAB_ROOT/config.env" "$staging/config.env"
cp "$SOURCE_ARCHIVE" "$staging/source.tar.gz"
cp "$GOLD_PATCH" "$staging/reference.patch"
cp "$RUNTIME_DIR/toolchain/packages.tsv" "$staging/packages.tsv"

tar -C "$EVALUATOR_DIR" \
    --exclude=self-check --exclude='VERIFIED-*.json' \
    -czf "$staging/evaluator.tar.gz" .

container_id=$(docker create --platform linux/amd64 "$IMAGE_REF" /bin/true)
docker export "$container_id" | gzip -n >"$staging/rootfs.tar.gz"
docker rm "$container_id" >/dev/null
container_id=

rootfs_sha=$(sha256_file "$staging/rootfs.tar.gz")
identity=$(printf '%s\n%s\n%s\n' "$(image_id)" "$rootfs_sha" "$LAB_PORTABLE_FORMAT" \
    | sha256sum | awk '{print $1}')
jq -n \
    --arg identity "$identity" \
    --arg source_image_id "$(image_id)" \
    --arg rootfs_sha256 "$rootfs_sha" \
    --argjson format "$LAB_PORTABLE_FORMAT" \
    '{format:$format,identity:$identity,source_image_id:$source_image_id,
      rootfs_sha256:$rootfs_sha256,runtime:"rootless-userns"}' \
    >"$staging/toolchain-identity.json"

(
    cd "$staging"
    for artifact in config.env evaluator.tar.gz packages.tsv reference.patch \
        rootfs.tar.gz source.tar.gz toolchain-identity.json; do
        printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"
    done >bundle-manifest.sha256
)
mv "$staging" "$destination"
trap - EXIT

printf 'portable bundle: %s\n' "$destination"
printf 'All artifacts are covered by bundle-manifest.sha256.\n'
