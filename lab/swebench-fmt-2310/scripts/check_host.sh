#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

require_linux_x86_64
require_python_311
require_docker

for command_name in curl git jq tar sha256sum awk sed find sort xargs timeout; do
    require_command "$command_name"
done

printf 'host: %s %s\n' "$(uname -s)" "$(uname -m)"
printf 'python: %s\n' "$("$LAB_PYTHON" --version 2>&1)"
printf 'docker: %s\n' "$(docker version --format '{{.Client.Version}} client / {{.Server.Version}} server')"
printf 'task: %s\n' "$LAB_TASK_ID"
printf 'image: %s@%s\n' "$LAB_IMAGE_REPOSITORY" "$LAB_IMAGE_DIGEST"
printf 'filesystem free: '
df -h "$LAB_ROOT" | awk 'NR == 2 {print $4}'
printf 'docker usage:\n'
docker system df

printf '\nhost checks passed\n'
