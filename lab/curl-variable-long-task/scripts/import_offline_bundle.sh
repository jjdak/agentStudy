#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -eq 1 ] || die "usage: $0 BUNDLE_DIRECTORY"
bundle=$(cd "$1" && pwd)
require_linux_x86_64
for command_name in awk find git jq sed sha256sum sort tar timeout; do
    require_command "$command_name"
done

required=(bundle-manifest.sha256 config.env evaluator.tar.gz packages.tsv
    reference.patch rootfs.tar.gz source.tar.gz toolchain-identity.json)
for artifact in "${required[@]}"; do
    [ -f "$bundle/$artifact" ] || die "bundle artifact missing: $artifact"
done
(
    cd "$bundle"
    sha256sum -c bundle-manifest.sha256 >/dev/null
) || die "bundle SHA-256 verification failed"

cmp -s "$bundle/config.env" "$LAB_ROOT/config.env" \
    || die "bundle config does not match this lab revision"
verify_sha256 "$bundle/source.tar.gz" "$LAB_SOURCE_SHA256"
verify_sha256 "$bundle/reference.patch" "$LAB_GOLD_PATCH_SHA256"
[ "$(jq -r .format "$bundle/toolchain-identity.json")" = "$LAB_PORTABLE_FORMAT" ] \
    || die "unsupported portable bundle format"
[ "$(jq -r .rootfs_sha256 "$bundle/toolchain-identity.json")" \
    = "$(sha256_file "$bundle/rootfs.tar.gz")" ] \
    || die "rootfs identity mismatch"

staging="$RUNTIME_DIR/.portable-import.$$"
trap 'chmod -R u+w "$staging" 2>/dev/null || true; rm -rf "$staging"' EXIT
mkdir -p "$staging/portable/rootfs" \
    "$staging/downloads" "$staging/evaluator"
cp "$bundle/rootfs.tar.gz" "$staging/portable/rootfs.tar.gz"
cp "$bundle/toolchain-identity.json" "$staging/portable/toolchain-identity.json"
cp "$bundle/source.tar.gz" "$staging/downloads/$(basename "$SOURCE_ARCHIVE")"
cp "$bundle/reference.patch" "$staging/downloads/$(basename "$GOLD_PATCH")"
tar -xzf "$bundle/rootfs.tar.gz" -C "$staging/portable/rootfs"
tar -xzf "$bundle/evaluator.tar.gz" -C "$staging/evaluator"
mkdir -p "$staging/portable/rootfs/home/agent" \
    "$staging/portable/rootfs/workspace" \
    "$staging/portable/rootfs/opt/agentstudy"
: >"$staging/portable/rootfs/dev/null"
: >"$staging/portable/rootfs/dev/zero"
: >"$staging/portable/rootfs/dev/random"
: >"$staging/portable/rootfs/dev/urandom"
: >"$staging/portable/rootfs/opt/agentstudy/black_box_tests.sh"
chmod -R a-w "$staging/portable/rootfs"
(
    cd "$staging/portable"
    for artifact in rootfs.tar.gz toolchain-identity.json; do
        printf '%s  %s\n' "$(sha256_file "$artifact")" "$artifact"
    done >runtime-manifest.sha256
)

mkdir -p "$RUNTIME_DIR"
for target in portable downloads evaluator; do
    if [ -e "$RUNTIME_DIR/$target" ]; then
        mv "$RUNTIME_DIR/$target" "$RUNTIME_DIR/.${target}.previous.$$"
    fi
    mv "$staging/$target" "$RUNTIME_DIR/$target"
done
rm -rf "$staging"
trap - EXIT

LAB_BACKEND=portable "$SCRIPT_DIR/portable_doctor.sh"
LAB_BACKEND=portable "$SCRIPT_DIR/verify_evaluator.sh"
printf 'portable import and evaluator verification: PASS\n'
