#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

BACKEND=portable
require_linux_x86_64
for command_name in awk chroot df find findmnt git jq mount sha256sum tar timeout unshare; do
    require_command "$command_name"
done
require_backend

filesystem=$(df -T "$LAB_ROOT" | tail -1 | awk '{print $2}')
available_kib=$(df -Pk "$LAB_ROOT" | tail -1 | awk '{print $4}')
[ "$available_kib" -ge 4194304 ] \
    || die "portable lab requires at least 4 GiB free disk space"

mount_options=$(findmnt -no OPTIONS --target "$LAB_ROOT" 2>/dev/null || true)
case ",$mount_options," in
    *,noexec,*) die "portable lab is on a noexec filesystem" ;;
esac

timeout 30s unshare --user --map-root-user --mount --pid --fork --net \
    /bin/bash -c 'mount --make-rprivate /; mount --bind "$1" "$1"' \
    _ "$LAB_ROOT" \
    || die "unprivileged user/mount/network namespaces are unavailable"

probe=$(mktemp -d "$PORTABLE_DIR/doctor.XXXXXX")
trap 'rm -rf "$probe"' EXIT
printf 'int main(void) { return 0; }\n' >"$probe/asan.c"
"$SCRIPT_DIR/backend_portable.sh" "$probe" false \
    'set -euo pipefail
     gcc -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer -fno-pie \
       -no-pie /workspace/asan.c -o /workspace/asan
     /workspace/asan
     printf portable-ok > /workspace/result'
[ "$(cat "$probe/result")" = portable-ok ] \
    || die "rootless toolchain or ASan execution probe failed"

printf 'host: %s %s\n' "$(uname -s)" "$(uname -m)"
printf 'filesystem: %s\n' "$filesystem"
printf 'free disk KiB: %s\n' "$available_kib"
printf 'user namespaces: PASS\n'
printf 'network namespace: PASS\n'
printf 'ASan/UBSan smoke: PASS\n'
printf 'toolchain identity: %s\n' "$(toolchain_identity)"
printf 'portable doctor: PASS\n'
