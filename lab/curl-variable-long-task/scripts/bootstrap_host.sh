#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

host_os=$(uname -s)
host_arch=$(uname -m)

if [ "$host_os" = Darwin ]; then
    case "$host_arch" in
        arm64|aarch64|x86_64) ;;
        *) die "unsupported macOS architecture: $host_arch" ;;
    esac

    require_command brew
    missing_formulae=()
    command -v colima >/dev/null 2>&1 || missing_formulae+=(colima)
    command -v docker >/dev/null 2>&1 || missing_formulae+=(docker)
    command -v gtimeout >/dev/null 2>&1 || missing_formulae+=(coreutils)
    command -v jq >/dev/null 2>&1 || missing_formulae+=(jq)
    if [ "${#missing_formulae[@]}" -gt 0 ]; then
        printf 'Installing missing Homebrew formulae: %s\n' "${missing_formulae[*]}"
        brew install "${missing_formulae[@]}"
        hash -r
    fi

    if ! colima status >/dev/null 2>&1; then
        colima start \
            --cpu "$LAB_COLIMA_CPUS" \
            --memory "$LAB_COLIMA_MEMORY_GB" \
            --disk "$LAB_COLIMA_DISK_GB" \
            --arch aarch64 \
            --vm-type vz \
            --vz-rosetta
    fi
    export LAB_RUNTIME=docker
elif [ "$host_os" = Linux ]; then
    case "$host_arch" in
        x86_64|amd64) ;;
        *) die "Linux preparation requires x86_64; current architecture: $host_arch" ;;
    esac
else
    die "unsupported host: $host_os $host_arch"
fi

"$SCRIPT_DIR/check_host.sh"
