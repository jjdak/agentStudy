#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LAB_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
# shellcheck source=../config.env
source "$LAB_ROOT/config.env"

DEMO_DIR="$LAB_ROOT/.demo"
DEMO_RUNS_DIR="$LAB_ROOT/demo-runs"
SOURCE_ARCHIVE="$DEMO_DIR/fmt-${LAB_BASE_COMMIT}.tar.gz"
REFERENCE_PATCH="$LAB_ROOT/answers/reference.patch"
SMOKE_SOURCE="$LAB_ROOT/demo/fmt_tuple_join_smoke.cc"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die "缺少 SHA-256 工具：请安装 sha256sum 或 shasum"
    fi
}

validate_run_id() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
        || die "run ID 必须匹配 [A-Za-z0-9][A-Za-z0-9._-]{0,63}"
}

workspace_for() {
    printf '%s/%s/workspace\n' "$DEMO_RUNS_DIR" "$1"
}

check_host() {
    local missing=()
    local command_name
    for command_name in bash curl git tar c++; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        printf '缺少命令：%s\n' "${missing[*]}" >&2
        printf 'Ubuntu/Debian：sudo apt-get install build-essential curl git tar\n' >&2
        return 1
    fi
    sha256_file "$LAB_ROOT/config.env" >/dev/null
    printf '宿主机 Demo 环境检查：PASS\n'
    printf '编译器：%s\n' "$(c++ --version | sed -n '1p')"
}

prepare() {
    check_host
    mkdir -p "$DEMO_DIR"
    if [ ! -f "$SOURCE_ARCHIVE" ]; then
        local partial="$SOURCE_ARCHIVE.$$.part"
        if ! curl -L --fail --show-error --output "$partial" "$DEMO_SOURCE_URL"; then
            rm -f "$partial"
            die "fmt 源码下载失败"
        fi
        mv "$partial" "$SOURCE_ARCHIVE"
    fi
    local actual
    actual=$(sha256_file "$SOURCE_ARCHIVE")
    [ "$actual" = "$DEMO_SOURCE_SHA256" ] \
        || die "源码 SHA-256 不匹配：期望 $DEMO_SOURCE_SHA256，实际 $actual"
    printf 'fmt 源码已准备：%s\n' "$SOURCE_ARCHIVE"
}

new_run() {
    local run_id=$1
    validate_run_id "$run_id"
    prepare

    local run_dir="$DEMO_RUNS_DIR/$run_id"
    local workspace="$run_dir/workspace"
    [ ! -e "$run_dir" ] || die "Demo run 已存在：$run_id"
    mkdir -p "$workspace"
    tar -xzf "$SOURCE_ARCHIVE" --strip-components=1 -C "$workspace"

    git -C "$workspace" init --quiet
    git -C "$workspace" config user.name "Agent Study Demo"
    git -C "$workspace" config user.email "demo@example.invalid"
    git -C "$workspace" config commit.gpgsign false
    git -C "$workspace" add --all --force
    git -C "$workspace" commit --quiet -m "demo baseline: $LAB_TASK_ID"
    cp "$LAB_ROOT/task/demo_task.md" "$workspace/TASK.md"
    printf '\nTASK.md\nbuild-demo/\n' >>"$workspace/.git/info/exclude"

    printf 'Demo run 已创建：%s\n' "$run_dir"
    printf 'workspace：%s\n' "$workspace"
    printf '任务入口：%s/TASK.md\n' "$workspace"
    printf '启动 Codex：codex -C %q\n' "$workspace"
    printf '运行测试：./scripts/demo.sh test %q\n' "$run_id"
}

test_run() {
    local run_id=$1
    validate_run_id "$run_id"
    local workspace
    workspace=$(workspace_for "$run_id")
    [ -d "$workspace/.git" ] || die "找不到 Demo run：$run_id"

    mkdir -p "$workspace/build-demo"
    c++ -std=c++11 -DFMT_HEADER_ONLY -pthread \
        -I"$workspace/include" \
        "$SMOKE_SOURCE" \
        -o "$workspace/build-demo/fmt-tuple-join-smoke"
    "$workspace/build-demo/fmt-tuple-join-smoke"
}

answer() {
    local run_id=$1
    local mode=${2:---show}
    validate_run_id "$run_id"
    local workspace
    workspace=$(workspace_for "$run_id")
    [ -d "$workspace/.git" ] || die "找不到 Demo run：$run_id"
    case "$mode" in
        --show)
            printf '公开参考答案：%s\n\n' "$REFERENCE_PATCH"
            sed -n '1,260p' "$REFERENCE_PATCH"
            ;;
        --apply)
            git -C "$workspace" apply --check "$REFERENCE_PATCH" \
                || die "参考补丁无法干净应用；请使用新 run 或先检查当前修改"
            git -C "$workspace" apply "$REFERENCE_PATCH"
            printf '参考答案已应用到 %s\n' "$workspace"
            printf '下一步：./scripts/demo.sh test %s\n' "$run_id"
            ;;
        *) die "answer 模式必须是 --show 或 --apply" ;;
    esac
}

usage() {
    cat <<'EOF'
用法：
  ./scripts/demo.sh check
  ./scripts/demo.sh prepare
  ./scripts/demo.sh new RUN_ID
  ./scripts/demo.sh test RUN_ID
  ./scripts/demo.sh answer RUN_ID [--show|--apply]

本教学路径直接使用宿主机 C++ 编译器，不需要 Docker、Python、SWE-bench、
隐藏测试或文件系统隔离。
EOF
}

command_name=${1:-help}
case "$command_name" in
    check) [ "$#" -eq 1 ] || die "用法：$0 check"; check_host ;;
    prepare) [ "$#" -eq 1 ] || die "用法：$0 prepare"; prepare ;;
    new) [ "$#" -eq 2 ] || die "用法：$0 new RUN_ID"; new_run "$2" ;;
    test) [ "$#" -eq 2 ] || die "用法：$0 test RUN_ID"; test_run "$2" ;;
    answer)
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || die "用法：$0 answer RUN_ID [--show|--apply]"
        answer "$2" "${3:---show}"
        ;;
    help|-h|--help) usage ;;
    *) usage >&2; die "未知 Demo 命令：$command_name" ;;
esac
