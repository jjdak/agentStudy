#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -eq 1 ] || die "usage: $0 BUNDLE_DIRECTORY"
bundle=$(cd "$1" && pwd)
[ "$(uname -s)" = Linux ] || die "portable runtime requires Linux"
case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "portable runtime requires x86_64; current architecture: $(uname -m)" ;;
esac
for command_name in awk cmp find gzip sed sort tar; do
    require_command "$command_name"
done
require_sha256_tool
timeout_executable >/dev/null

for artifact in bundle-manifest.sha256 config.env packages.tsv reference.patch \
    rootfs-metadata.json rootfs.sha256 runtime.txt source.tar.gz \
    toolchain-rootfs.tar.gz; do
    [ -f "$bundle/$artifact" ] || die "bundle artifact missing: $artifact"
done
[ "$(cat "$bundle/runtime.txt")" = bwrap ] || die "bundle runtime is not bwrap"
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
verify_sha256 "$bundle/toolchain-rootfs.tar.gz" "$(cat "$bundle/rootfs.sha256")"

mkdir -p "$DOWNLOAD_DIR" "$TOOLCHAIN_DIR"
cp "$bundle/source.tar.gz" "$SOURCE_ARCHIVE"
cp "$bundle/reference.patch" "$GOLD_PATCH"
cp "$bundle/packages.tsv" "$TOOLCHAIN_DIR/packages.tsv"
cp "$bundle/toolchain-rootfs.tar.gz" "$ROOTFS_ARCHIVE"
cp "$bundle/rootfs.sha256" "$ROOTFS_SHA256_FILE"
cp "$bundle/rootfs-metadata.json" "$TOOLCHAIN_DIR/rootfs-metadata.json"

rootfs_tmp="$TOOLCHAIN_DIR/.rootfs.tmp.$$"
trap 'rm -rf "$rootfs_tmp"' EXIT
mkdir -p "$rootfs_tmp"
tar --no-same-owner -xzf "$ROOTFS_ARCHIVE" -C "$rootfs_tmp"
[ -x "$rootfs_tmp/usr/bin/bwrap" ] || die "portable bubblewrap is missing from rootfs"
[ -x "$rootfs_tmp/bin/bash" ] || die "portable Bash is missing from rootfs"
rm -rf "$ROOTFS_DIR"
mv "$rootfs_tmp" "$ROOTFS_DIR"
trap - EXIT

mkdir -p "$HOST_TOOL_DIR"
for tool_name in git jq; do
    cp "$SCRIPT_DIR/portable_tool.sh" "$HOST_TOOL_DIR/$tool_name"
    chmod 0555 "$HOST_TOOL_DIR/$tool_name"
done
PATH="$HOST_TOOL_DIR:$PATH"
export PATH
require_command git
require_command jq

export LAB_RUNTIME=bwrap
require_bwrap_runtime
"$SCRIPT_DIR/prepare_evaluator.sh"
"$SCRIPT_DIR/verify_evaluator.sh"
printf 'portable offline import and evaluator verification: PASS\n'
