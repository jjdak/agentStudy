#!/usr/bin/env bash

set -euo pipefail

if [ "${1:-}" = --internal ]; then
    shift
    rootfs=$1
    workspace=$2
    portable_home=$3
    portable_tmp=$4
    command_text=$5
    shift 5

    mount --make-rprivate /
    mount --bind "$rootfs" "$rootfs"
    mount -o remount,bind,ro "$rootfs"
    mount --bind "$workspace" "$rootfs/workspace"
    mount --bind "$portable_home" "$rootfs/home/agent"
    mount --bind "$portable_tmp" "$rootfs/tmp"
    for device in null zero random urandom; do
        mount --bind "/dev/$device" "$rootfs/dev/$device"
    done
    mount -t proc proc "$rootfs/proc"
    for bind_spec in "$@"; do
        IFS=: read -r source destination mode <<<"$bind_spec"
        [ "${mode:-ro}" = ro ] || exit 64
        mount --bind "$source" "$rootfs$destination"
        mount -o remount,bind,ro "$rootfs$destination"
    done
    chroot "$rootfs" /usr/sbin/ip link set lo up
    exec chroot "$rootfs" /usr/bin/env -i \
        HOME=/home/agent \
        LANG=C.UTF-8 \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        ASAN_OPTIONS=detect_leaks=1:halt_on_error=1:abort_on_error=1 \
        UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
        /bin/bash -lc "ulimit -f 262144; cd /workspace && $command_text"
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -ge 3 ] || die "internal usage: backend_portable.sh WORKSPACE INTERACTIVE COMMAND [BIND...]"
workspace=$1
interactive=$2
command_text=$3
shift 3
[ "$interactive" = true ] || [ "$interactive" = false ] \
    || die "invalid interactive flag: $interactive"
require_backend

portable_tmp=$(mktemp -d "$PORTABLE_DIR/tmp.XXXXXX")
trap 'rm -rf "$portable_tmp"' EXIT
mkdir -p "$portable_tmp/home" "$portable_tmp/tmp"

unshare --user --map-root-user --mount --pid --fork --net \
    "$0" --internal "$PORTABLE_ROOTFS" "$workspace" \
    "$portable_tmp/home" "$portable_tmp/tmp" "$command_text" "$@"
