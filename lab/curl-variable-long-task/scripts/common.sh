#!/usr/bin/env bash
# shellcheck disable=SC2034

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAB_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# shellcheck source=../config.env
source "$LAB_ROOT/config.env"

RUNTIME_DIR="$LAB_ROOT/.runtime"
DOWNLOAD_DIR="$RUNTIME_DIR/downloads"
SOURCE_ARCHIVE="$DOWNLOAD_DIR/curl-${LAB_BASE_COMMIT}.tar.gz"
GOLD_PATCH="$DOWNLOAD_DIR/curl-${LAB_GOLD_COMMIT}.patch"
EVALUATOR_DIR="$RUNTIME_DIR/evaluator"
HIDDEN_TEST_DIR="$EVALUATOR_DIR/hidden-tests"
RUNS_DIR="$LAB_ROOT/runs"
IMAGE_REF="${LAB_IMAGE_REPOSITORY}:${LAB_IMAGE_TAG}"
TOOLCHAIN_DIR="$RUNTIME_DIR/toolchain"
ROOTFS_ARCHIVE="$TOOLCHAIN_DIR/rootfs.tar.gz"
ROOTFS_DIR="$TOOLCHAIN_DIR/rootfs"
ROOTFS_SHA256_FILE="$TOOLCHAIN_DIR/rootfs.sha256"
HOST_TOOL_DIR="$TOOLCHAIN_DIR/host-bin"
if [ -d "$HOST_TOOL_DIR" ]; then
    PATH="$HOST_TOOL_DIR:$PATH"
    export PATH
fi

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

verify_sha256() {
    local file=$1
    local expected=$2
    local actual
    actual=$(sha256_file "$file")
    [ "$actual" = "$expected" ] \
        || die "SHA-256 mismatch for $file: expected $expected, got $actual"
}

download_verified() {
    local url=$1
    local destination=$2
    local expected=$3
    local partial="${destination}.$$.part"

    mkdir -p "$(dirname "$destination")"
    if [ -f "$destination" ]; then
        verify_sha256 "$destination" "$expected"
        return
    fi

    curl -L --fail --show-error --output "$partial" "$url"
    verify_sha256 "$partial" "$expected"
    mv "$partial" "$destination"
}

require_supported_host() {
    local host_os host_arch
    host_os=$(uname -s)
    host_arch=$(uname -m)
    case "$host_os/$host_arch" in
        Linux/x86_64|Linux/amd64|Darwin/arm64|Darwin/aarch64|Darwin/x86_64) ;;
        *) die "unsupported host: $host_os $host_arch; use Linux x86_64 or macOS with a Linux Docker engine" ;;
    esac
}

require_docker() {
    local docker_error
    require_command docker
    if ! docker_error=$(docker info 2>&1 >/dev/null); then
        if [ -S /var/run/docker.sock ] && [ ! -w /var/run/docker.sock ]; then
            die "Docker socket permission denied for $(id -un); ask an administrator to add this user to the docker group and log in again"
        fi
        die "Docker daemon is not reachable: ${docker_error%%$'\n'*}"
    fi
    [ "$(docker info --format '{{.OSType}}')" = linux ] \
        || die "Docker server must use a Linux engine"
}

require_sha256_tool() {
    if ! command -v sha256sum >/dev/null 2>&1 \
        && ! command -v shasum >/dev/null 2>&1; then
        die "missing SHA-256 tool: install sha256sum or shasum"
    fi
}

timeout_executable() {
    if command -v timeout >/dev/null 2>&1; then
        command -v timeout
    elif command -v gtimeout >/dev/null 2>&1; then
        command -v gtimeout
    else
        die "missing GNU timeout (macOS: brew install coreutils)"
    fi
}

workspace_filesystem_type() {
    if [ "$(uname -s)" = Darwin ]; then
        df "$LAB_ROOT" | tail -1 | awk '{print $1}'
    else
        df -T "$LAB_ROOT" | tail -1 | awk '{print $2}'
    fi
}

lab_mktemp() {
    # Docker Desktop and Colima share the repository path, but a macOS
    # /var/folders path returned by bare mktemp is not necessarily visible
    # inside the Linux VM.
    mkdir -p "$RUNTIME_DIR/tmp"
    mktemp -d "$RUNTIME_DIR/tmp/lab.XXXXXX"
}

verify_toolchain_architecture() {
    local image_arch runtime_arch
    image_arch=$(docker image inspect --format '{{.Architecture}}' "$IMAGE_REF")
    [ "$image_arch" = amd64 ] \
        || die "toolchain image must be linux/amd64; reported: $image_arch"
    runtime_arch=$(docker run --rm --platform linux/amd64 --network none \
        "$IMAGE_REF" uname -m)
    [ "$runtime_arch" = x86_64 ] || [ "$runtime_arch" = amd64 ] \
        || die "Docker cannot execute linux/amd64 containers; reported: $runtime_arch"
}

runtime_backend() {
    local requested
    requested=${LAB_RUNTIME:-$LAB_RUNTIME_DEFAULT}
    case "$requested" in
        auto)
            case "$(uname -s)/$(uname -m)" in
                Linux/x86_64|Linux/amd64)
                    if [ -d "$ROOTFS_DIR" ] && [ -f "$ROOTFS_SHA256_FILE" ]; then
                        printf 'bwrap\n'
                        return
                    fi
                    ;;
            esac
            if command -v docker >/dev/null 2>&1 \
                && docker info >/dev/null 2>&1; then
                printf 'docker\n'
                return
            fi
            die "no usable runtime: import a portable bundle or start Docker"
            ;;
        docker|bwrap) printf '%s\n' "$requested" ;;
        *) die "LAB_RUNTIME must be auto, docker, or bwrap; got: $requested" ;;
    esac
}

set_bwrap_command() {
    BWRAP_COMMAND=()
    if command -v bwrap >/dev/null 2>&1; then
        BWRAP_COMMAND=("$(command -v bwrap)")
        return
    fi

    local loader binary library_path
    loader="$ROOTFS_DIR/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
    binary="$ROOTFS_DIR/usr/bin/bwrap"
    library_path="$ROOTFS_DIR/lib/x86_64-linux-gnu:$ROOTFS_DIR/usr/lib/x86_64-linux-gnu"
    [ -x "$loader" ] || die "portable dynamic loader is missing: $loader"
    [ -x "$binary" ] || die "portable bubblewrap is missing: $binary"
    BWRAP_COMMAND=("$loader" --library-path "$library_path" "$binary")
}

bwrap_common_args() {
    local workspace=$1
    printf '%s\n' \
        --unshare-all \
        --die-with-parent \
        --new-session \
        --hostname agentstudy \
        --cap-drop ALL \
        --uid 0 \
        --gid 0 \
        --ro-bind "$ROOTFS_DIR" / \
        --dev /dev \
        --proc /proc \
        --tmpfs /tmp \
        --tmpfs /home \
        --tmpfs /run \
        --bind "$workspace" /workspace \
        --chdir /workspace \
        --clearenv \
        --setenv HOME /home/agent \
        --setenv LANG en_US.UTF-8 \
        --setenv LC_ALL en_US.UTF-8 \
        --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
}

require_bwrap_runtime() {
    [ "$(uname -s)" = Linux ] || die "Bubblewrap runtime requires a Linux host"
    case "$(uname -m)" in
        x86_64|amd64) ;;
        *) die "portable rootfs requires Linux x86_64; current architecture: $(uname -m)" ;;
    esac
    [ -f "$ROOTFS_ARCHIVE" ] || die "portable rootfs archive is missing; import or prepare a portable bundle"
    [ -d "$ROOTFS_DIR" ] || die "portable rootfs is not extracted; import or prepare a portable bundle"
    [ -f "$ROOTFS_SHA256_FILE" ] || die "portable rootfs checksum is missing"
    verify_sha256 "$ROOTFS_ARCHIVE" "$(cat "$ROOTFS_SHA256_FILE")"
    set_bwrap_command
    local probe
    probe=$("${BWRAP_COMMAND[@]}" \
        --unshare-all \
        --die-with-parent \
        --ro-bind "$ROOTFS_DIR" / \
        --dev /dev \
        --proc /proc \
        --tmpfs /tmp \
        --chdir / \
        /usr/bin/uname -m) \
        || die "Bubblewrap cannot create the required unprivileged namespaces"
    [ "$probe" = x86_64 ] || [ "$probe" = amd64 ] \
        || die "portable runtime is not x86_64; reported: $probe"
}

require_runtime() {
    case "$(runtime_backend)" in
        docker)
            require_docker
            docker image inspect "$IMAGE_REF" >/dev/null 2>&1 \
                || die "fixed toolchain image is not loaded: $IMAGE_REF"
            verify_toolchain_architecture
            ;;
        bwrap) require_bwrap_runtime ;;
    esac
}

toolchain_id() {
    case "$(runtime_backend)" in
        docker) image_id ;;
        bwrap) cat "$ROOTFS_SHA256_FILE" ;;
    esac
}

runtime_ref() {
    case "$(runtime_backend)" in
        docker) printf '%s\n' "$IMAGE_REF" ;;
        bwrap) printf 'rootfs:%s\n' "$(cat "$ROOTFS_SHA256_FILE")" ;;
    esac
}

require_downloads() {
    [ -f "$SOURCE_ARCHIVE" ] || die "source archive is missing; run scripts/prepare_online.sh"
    [ -f "$GOLD_PATCH" ] || die "trusted reference patch is missing; run scripts/prepare_online.sh"
    verify_sha256 "$SOURCE_ARCHIVE" "$LAB_SOURCE_SHA256"
    verify_sha256 "$GOLD_PATCH" "$LAB_GOLD_PATCH_SHA256"
}

require_scoring_assets() {
    require_supported_host
    require_downloads
    require_runtime
    [ -x "$EVALUATOR_DIR/black_box_tests.sh" ] \
        || die "evaluator assets are missing; run scripts/prepare_online.sh"
    [ -f "$EVALUATOR_DIR/hidden-tests.sha256" ] \
        || die "hidden tests are missing; run scripts/prepare_online.sh"
    while read -r expected test_file; do
        [ "$(sha256_file "$HIDDEN_TEST_DIR/$test_file")" = "$expected" ] \
            || die "hidden test integrity check failed: $test_file"
    done <"$EVALUATOR_DIR/hidden-tests.sha256"
}

require_prepared() {
    require_scoring_assets
    [ -f "$EVALUATOR_DIR/VERIFIED.json" ] \
        || die "evaluator controls have not passed; run scripts/verify_evaluator.sh"
    require_command jq
    [ "$(jq -r .oracle_sha256 "$EVALUATOR_DIR/VERIFIED.json")" \
        = "$(sha256_file "$EVALUATOR_DIR/black_box_tests.sh")" ] \
        || die "black-box oracle changed after evaluator verification"
    [ "$(jq -r .hidden_manifest_sha256 "$EVALUATOR_DIR/VERIFIED.json")" \
        = "$(sha256_file "$EVALUATOR_DIR/hidden-tests.sha256")" ] \
        || die "hidden-test manifest changed after evaluator verification"
    [ "$(jq -r .runtime "$EVALUATOR_DIR/VERIFIED.json")" = "$(runtime_backend)" ] \
        || die "runtime changed after evaluator verification"
    [ "$(jq -r .toolchain_id "$EVALUATOR_DIR/VERIFIED.json")" = "$(toolchain_id)" ] \
        || die "toolchain changed after evaluator verification"
    [ "$(jq -r .config_sha256 "$EVALUATOR_DIR/VERIFIED.json")" \
        = "$(sha256_file "$LAB_ROOT/config.env")" ] \
        || die "config.env changed after evaluator verification"
}

validate_run_id() {
    local run_id=$1
    [[ "$run_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
        || die "run ID must match [A-Za-z0-9][A-Za-z0-9._-]{0,63}"
}

extract_base() {
    local destination=$1
    mkdir -p "$destination"
    tar -xzf "$SOURCE_ARCHIVE" -C "$destination" --strip-components=1
}

init_snapshot_repo() {
    local destination=$1
    (
        cd "$destination"
        git init -q
        git config user.name "agentStudy evaluator"
        git config user.email "evaluator@invalid"
        git add --all --force
        env GIT_AUTHOR_DATE=2023-07-25T00:00:00Z \
            GIT_COMMITTER_DATE=2023-07-25T00:00:00Z \
            git commit -q -m "trusted curl baseline ${LAB_BASE_COMMIT}"
    )
}

image_id() {
    docker image inspect --format '{{.Id}}' "$IMAGE_REF"
}

container_common_args() {
    printf '%s\n' \
        --platform linux/amd64 \
        --network none \
        --read-only \
        --ipc none \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        --pids-limit "$LAB_CONTAINER_PIDS" \
        --cpus "$LAB_CONTAINER_CPUS" \
        --memory "$LAB_CONTAINER_MEMORY" \
        --tmpfs /tmp:rw,nosuid,nodev,noexec,size=1g \
        --tmpfs /home/agent:rw,nosuid,nodev,size=256m
}
