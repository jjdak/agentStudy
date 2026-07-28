#!/usr/bin/env bash

set -euo pipefail

UV_VERSION=0.11.32
UV_INSTALL_ROOT=/opt/swebench-uv-python
UV_BIN_DIR=/usr/local/bin
CONFIGURE_DOCKER_PROXY=0

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: ./scripts/bootstrap_host.sh [--docker-proxy-from-env]

Install the host dependencies for this lab on Debian or Ubuntu.
Run this script as your normal login user; it invokes sudo when needed.

Options:
  --docker-proxy-from-env  Configure the Docker systemd service with the current
                           HTTP_PROXY, HTTPS_PROXY, and NO_PROXY values.
EOF
}

case "${1:-}" in
    "")
        ;;
    --docker-proxy-from-env)
        CONFIGURE_DOCKER_PROXY=1
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

[ "$(uname -s)" = "Linux" ] || die "this lab intentionally requires Linux"
case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "this lab requires x86_64; current architecture: $(uname -m)" ;;
esac

[ -r /etc/os-release ] || die "cannot identify the Linux distribution"
# shellcheck source=/dev/null
source /etc/os-release
case "${ID:-}" in
    debian|ubuntu)
        ;;
    *)
        case " ${ID_LIKE:-} " in
            *" debian "*) ;;
            *) die "automatic installation supports Debian/Ubuntu only; current distribution: ${PRETTY_NAME:-unknown}" ;;
        esac
        ;;
esac

if [ "$EUID" -eq 0 ]; then
    AS_ROOT=()
else
    command -v sudo >/dev/null 2>&1 || die "sudo is required; install it or run this script as root"
    AS_ROOT=(sudo)
fi

apt_get() {
    "${AS_ROOT[@]}" apt-get \
        -o Acquire::Retries=5 \
        -o Acquire::http::Timeout=30 \
        -o Acquire::https::Timeout=30 \
        "$@"
}

printf 'Installing host packages for %s...\n' "${PRETTY_NAME:-Debian/Ubuntu}"
apt_get update

packages=(
    ca-certificates
    coreutils
    curl
    findutils
    gawk
    git
    jq
    sed
    tar
)
apt_get install -y "${packages[@]}"

apt_has_candidate() {
    local package_metadata

    package_metadata=$(apt-cache show --no-all-versions "$1" 2>/dev/null || true)
    [ -n "$package_metadata" ]
}

docker_daemon_reachable() {
    command -v docker >/dev/null 2>&1 \
        && "${AS_ROOT[@]}" docker info >/dev/null 2>&1
}

docker_service_installed() {
    command -v systemctl >/dev/null 2>&1 \
        && systemctl cat docker.service >/dev/null 2>&1
}

systemd_escape_environment() {
    local value=$1

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//%/%%}
    printf '%s' "$value"
}

configure_docker_proxy_from_env() {
    local docker_http_proxy
    local docker_https_proxy
    local docker_no_proxy
    local proxy_config

    docker_http_proxy=${HTTP_PROXY:-${http_proxy:-}}
    docker_https_proxy=${HTTPS_PROXY:-${https_proxy:-}}
    docker_no_proxy=${NO_PROXY:-${no_proxy:-}}
    [ -n "$docker_http_proxy" ] || [ -n "$docker_https_proxy" ] \
        || die "--docker-proxy-from-env requires HTTP_PROXY or HTTPS_PROXY"

    proxy_config=$(mktemp)
    trap 'rm -f -- "$proxy_config"' EXIT
    {
        printf '[Service]\n'
        if [ -n "$docker_http_proxy" ]; then
            printf 'Environment="HTTP_PROXY=%s"\n' \
                "$(systemd_escape_environment "$docker_http_proxy")"
        fi
        if [ -n "$docker_https_proxy" ]; then
            printf 'Environment="HTTPS_PROXY=%s"\n' \
                "$(systemd_escape_environment "$docker_https_proxy")"
        fi
        if [ -n "$docker_no_proxy" ]; then
            printf 'Environment="NO_PROXY=%s"\n' \
                "$(systemd_escape_environment "$docker_no_proxy")"
        fi
    } >"$proxy_config"

    "${AS_ROOT[@]}" install -d -m 0755 /etc/systemd/system/docker.service.d
    "${AS_ROOT[@]}" install -m 0600 \
        "$proxy_config" /etc/systemd/system/docker.service.d/http-proxy.conf
    rm -f -- "$proxy_config"
    trap - EXIT

    "${AS_ROOT[@]}" systemctl daemon-reload
    "${AS_ROOT[@]}" systemctl restart docker
    printf 'Configured Docker daemon proxy from the current environment.\n'
}

if ! docker_daemon_reachable \
    && { ! command -v docker >/dev/null 2>&1 || ! docker_service_installed; }; then
    if apt_has_candidate docker-ce; then
        printf 'Docker CLI is present, but Docker Engine is missing; installing docker-ce...\n'
        apt_get install -y docker-ce
    else
        printf 'Docker Engine is missing; installing docker.io...\n'
        apt_get install -y docker.io
    fi
fi

has_python_311() {
    command -v python3.11 >/dev/null 2>&1 \
        && python3.11 -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)'
}

has_usable_python_311() {
    local test_dir

    has_python_311 || return 1
    test_dir=$(mktemp -d)
    if python3.11 -m venv "$test_dir" >/dev/null 2>&1; then
        rm -rf -- "$test_dir"
        return 0
    fi
    rm -rf -- "$test_dir"
    return 1
}

install_python_with_uv() {
    local installer
    local uv_path

    uv_path=$(command -v uv || true)
    if [ -z "$uv_path" ]; then
        installer=$(mktemp)
        trap 'rm -f -- "$installer"' EXIT
        curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" -o "$installer"
        "${AS_ROOT[@]}" env UV_UNMANAGED_INSTALL="$UV_BIN_DIR" sh "$installer"
        rm -f -- "$installer"
        trap - EXIT
        uv_path="$UV_BIN_DIR/uv"
    fi

    printf 'APT does not provide Python 3.11; installing it with uv %s...\n' "$UV_VERSION"
    "${AS_ROOT[@]}" env \
        UV_PYTHON_INSTALL_DIR="$UV_INSTALL_ROOT" \
        UV_PYTHON_BIN_DIR="$UV_BIN_DIR" \
        "$uv_path" python install 3.11
}

if ! has_usable_python_311; then
    if apt_has_candidate python3.11 && apt_has_candidate python3.11-venv; then
        apt_get install -y python3.11 python3.11-venv
    else
        install_python_with_uv
    fi
fi

hash -r
has_usable_python_311 \
    || die "Python 3.11 installation completed, but python3.11 cannot create a virtual environment"

if ! docker_daemon_reachable; then
    if command -v systemctl >/dev/null 2>&1 && docker_service_installed; then
        "${AS_ROOT[@]}" systemctl enable --now docker \
            || die "Docker Engine is installed, but its daemon could not be started"
    elif command -v service >/dev/null 2>&1; then
        "${AS_ROOT[@]}" service docker start \
            || die "Docker Engine is installed, but its daemon could not be started"
    else
        die "Docker Engine is installed, but no supported service manager could start it"
    fi
fi
docker_daemon_reachable || die "Docker daemon is still not reachable after startup"

if [ "$CONFIGURE_DOCKER_PROXY" -eq 1 ]; then
    configure_docker_proxy_from_env
    docker_daemon_reachable || die "Docker daemon is not reachable after applying its proxy configuration"
fi

login_user=$(id -un)
if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    login_user=$SUDO_USER
fi

docker_group_changed=0
if [ "$login_user" != root ]; then
    case " $(id -nG "$login_user") " in
        *" docker "*)
            ;;
        *)
            "${AS_ROOT[@]}" usermod -aG docker "$login_user"
            docker_group_changed=1
            ;;
    esac
fi

printf '\nHost dependencies installed.\n'
printf 'python: %s\n' "$(python3.11 --version 2>&1)"
printf 'docker: %s\n' "$(docker --version)"

if [ "$docker_group_changed" -eq 1 ]; then
    printf '\nDocker group membership was added for %s.\n' "$login_user"
    printf 'Log out and back in, then run:\n'
    printf '  ./scripts/check_host.sh\n'
    printf '  ./scripts/prepare_online.sh\n'
else
    printf '\nNext:\n'
    printf '  ./scripts/check_host.sh\n'
    printf '  ./scripts/prepare_online.sh\n'
fi
