#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

export LAB_RUNTIME=docker
require_supported_host
require_prepared
require_command gzip

mkdir -p "$TOOLCHAIN_DIR"
archive_tmp="$ROOTFS_ARCHIVE.$$.tmp"
export_tmp="$TOOLCHAIN_DIR/rootfs.$$.tar"
rootfs_tmp="$TOOLCHAIN_DIR/.rootfs.tmp.$$"
container_id=
cleanup() {
    rm -f "$archive_tmp"
    rm -f "$export_tmp"
    rm -rf "$rootfs_tmp"
    if [ -n "$container_id" ]; then
        docker rm -f "$container_id" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

container_id=$(docker create --platform linux/amd64 "$IMAGE_REF" /bin/true)
docker export --output "$export_tmp" "$container_id"
docker rm "$container_id" >/dev/null
container_id=
gzip -9 -c "$export_tmp" >"$archive_tmp"
rm -f "$export_tmp"

mkdir -p "$rootfs_tmp"
tar --no-same-owner -xzf "$archive_tmp" -C "$rootfs_tmp"
[ -x "$rootfs_tmp/usr/bin/bwrap" ] \
    || die "toolchain rootfs does not contain /usr/bin/bwrap"
[ -x "$rootfs_tmp/bin/bash" ] \
    || die "toolchain rootfs does not contain /bin/bash"

mv "$archive_tmp" "$ROOTFS_ARCHIVE"
rm -rf "$ROOTFS_DIR"
mv "$rootfs_tmp" "$ROOTFS_DIR"
rootfs_sha256=$(sha256_file "$ROOTFS_ARCHIVE")
printf '%s\n' "$rootfs_sha256" >"$ROOTFS_SHA256_FILE"

jq -n \
    --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg image_ref "$IMAGE_REF" \
    --arg image_id "$(image_id)" \
    --arg rootfs_sha256 "$rootfs_sha256" \
    --arg bwrap_version "$(docker run --rm --platform linux/amd64 "$IMAGE_REF" bwrap --version)" \
    '{created_at:$created_at,image_ref:$image_ref,image_id:$image_id,
      rootfs_sha256:$rootfs_sha256,bwrap_version:$bwrap_version}' \
    >"$TOOLCHAIN_DIR/rootfs-metadata.json"

trap - EXIT
printf 'portable rootfs: %s\n' "$ROOTFS_ARCHIVE"
printf 'rootfs SHA-256: %s\n' "$rootfs_sha256"
printf 'extracted rootfs: %s\n' "$ROOTFS_DIR"
printf 'On Linux x86_64, verify with: LAB_RUNTIME=bwrap %s/verify_evaluator.sh\n' "$SCRIPT_DIR"
