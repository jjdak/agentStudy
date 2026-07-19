#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

[ "$#" -eq 1 ] || die "usage: $0 <run-id>"
RUN_ID=$1
validate_run_id "$RUN_ID"

require_linux_x86_64
require_docker
require_prepared

RUN_DIR="$RUNS_DIR/$RUN_ID"
WORKSPACE="$RUN_DIR/workspace"

[ ! -e "$RUN_DIR" ] || die "run already exists; choose a new ID: $RUN_DIR"
mkdir -p "$WORKSPACE"

# Stream a clean source snapshot from the trusted task image. Excluding .git
# prevents access to upstream history, tags, remotes, and the original fix.
docker run --rm --network none --entrypoint /bin/tar "$IMAGE_REF" \
    --exclude=.git -C /testbed -cf - . \
    | tar -C "$WORKSPACE" -xf -

git -C "$WORKSPACE" init --quiet
git -C "$WORKSPACE" config user.name "Agent Study Baseline"
git -C "$WORKSPACE" config user.email "agent-study@example.invalid"
# Force-add files that were tracked upstream even if an upstream .gitignore
# pattern also matches them; the exported snapshot no longer has its index.
git -C "$WORKSPACE" add --all --force
GIT_AUTHOR_DATE=2020-01-01T00:00:00Z \
GIT_COMMITTER_DATE=2020-01-01T00:00:00Z \
    git -C "$WORKSPACE" commit --quiet -m "baseline: $LAB_TASK_ID"

[ -z "$(git -C "$WORKSPACE" remote)" ] || die "workspace unexpectedly contains a Git remote"
[ "$(git -C "$WORKSPACE" rev-list --count HEAD)" = "1" ] || die "workspace history was not reduced to one baseline commit"

cp "$LAB_ROOT/task/agent_task.md" "$RUN_DIR/agent_task.md"
cp "$LAB_ROOT/templates/run-notes.md" "$RUN_DIR/run-notes.md"

PROMPT_SHA=$(sha256sum "$RUN_DIR/agent_task.md" | awk '{print $1}')
WORKSPACE_BASELINE=$(git -C "$WORKSPACE" rev-parse HEAD)
CREATED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
    --arg run_id "$RUN_ID" \
    --arg task_id "$LAB_TASK_ID" \
    --arg created_at "$CREATED_AT" \
    --arg upstream_base_commit "$LAB_BASE_COMMIT" \
    --arg workspace_baseline "$WORKSPACE_BASELINE" \
    --arg prompt_sha256 "$PROMPT_SHA" \
    --arg harness_commit "$LAB_HARNESS_COMMIT" \
    --arg dataset_revision "$LAB_DATASET_REVISION" \
    --arg image_digest "$LAB_IMAGE_DIGEST" \
    '{
        run_id: $run_id,
        task_id: $task_id,
        created_at: $created_at,
        upstream_base_commit: $upstream_base_commit,
        workspace_baseline: $workspace_baseline,
        prompt_sha256: $prompt_sha256,
        harness_commit: $harness_commit,
        dataset_revision: $dataset_revision,
        image_digest: $image_digest,
        model_name_or_path: null,
        patch_sha256: null,
        evaluation: null
    }' >"$RUN_DIR/metadata.json"

chmod -R u+rwX,go-rwx "$RUN_DIR"

printf 'run created: %s\n' "$RUN_DIR"
printf 'give the Agent only this workspace: %s\n' "$WORKSPACE"
printf 'use this fixed task text: %s\n' "$RUN_DIR/agent_task.md"
printf 'do not expose: %s or sibling runs\n' "$RUNTIME_DIR"
