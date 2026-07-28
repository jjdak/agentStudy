#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

export LAB_RUNTIME=docker
require_prepared
[ -f "$ROOTFS_ARCHIVE" ] || die "portable rootfs is missing; run scripts/prepare_portable_runtime.sh"
[ -f "$ROOTFS_SHA256_FILE" ] || die "portable rootfs checksum is missing"
[ -f "$TOOLCHAIN_DIR/rootfs-metadata.json" ] || die "portable rootfs metadata is missing"
verify_sha256 "$ROOTFS_ARCHIVE" "$(cat "$ROOTFS_SHA256_FILE")"

destination=${1:-$LAB_ROOT/offline-bundles/${LAB_TASK_ID}-portable-$(date -u +%Y%m%dT%H%M%SZ)}
[ ! -e "$destination" ] || die "destination already exists: $destination"
mkdir -p "$destination"

cp "$SOURCE_ARCHIVE" "$destination/source.tar.gz"
cp "$GOLD_PATCH" "$destination/reference.patch"
cp "$LAB_ROOT/config.env" "$destination/config.env"
cp "$TOOLCHAIN_DIR/packages.tsv" "$destination/packages.tsv"
cp "$ROOTFS_ARCHIVE" "$destination/toolchain-rootfs.tar.gz"
cp "$ROOTFS_SHA256_FILE" "$destination/rootfs.sha256"
cp "$TOOLCHAIN_DIR/rootfs-metadata.json" "$destination/rootfs-metadata.json"
printf 'bwrap\n' >"$destination/runtime.txt"

(
    cd "$destination"
    for artifact in config.env packages.tsv reference.patch rootfs-metadata.json \
        rootfs.sha256 runtime.txt source.tar.gz toolchain-rootfs.tar.gz; do
        printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"
    done >bundle-manifest.sha256
)

printf 'portable offline bundle: %s\n' "$destination"
printf 'The target requires Linux x86_64, unprivileged user namespaces, Bash, common base utilities, tar and GNU timeout.\n'
printf 'Copy this directory together with the agentStudy repository.\n'
