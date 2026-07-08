#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROJECT="$ROOT/project"
ORACLE="$ROOT/oracle"
RESULT_ROOT="$ROOT/results/latest"
WORK_ROOT="$ROOT/.work"

CLANG=${CLANG:-$(command -v clang)}
CPPCHECK=${CPPCHECK:-$(command -v cppcheck || true)}
CMAKE=${CMAKE:-$(command -v cmake)}
CTEST=${CTEST:-$(command -v ctest)}

find_gnu_gcc() {
    local candidate
    for candidate in gcc-16 gcc-15 gcc-14 gcc-13 gcc-12; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done
    command -v gcc
}

GCC=${GCC:-$(find_gnu_gcc)}

for required_tool in "$CMAKE" "$CTEST" "$CLANG" "$GCC" "$CPPCHECK"; do
    if [ -z "$required_tool" ] || [ ! -x "$required_tool" ]; then
        echo "missing required tool; install CMake/CTest, Clang, GNU GCC and cppcheck" >&2
        exit 2
    fi
done

if "$GCC" --version | head -n 1 | grep -qi 'Apple clang'; then
    echo "GNU GCC is required; macOS /usr/bin/gcc is Apple Clang" >&2
    exit 2
fi

rm -rf "$RESULT_ROOT" "$WORK_ROOT"
mkdir -p "$RESULT_ROOT/logs" "$WORK_ROOT"

# Keep user-level CMake/package registries and tool caches out of the experiment.
TOOL_HOME="$WORK_ROOT/tool-home"
mkdir -p "$TOOL_HOME"
export HOME="$TOOL_HOME"

SUMMARY="$RESULT_ROOT/summary.csv"
printf '%s\n' 'candidate,scope,gcc_build,clang_build,public_tests,static_analysis,hidden_tests,sanitizer,fuzz_smoke,accepted' >"$SUMMARY"

run_gate() {
    local log_file=$1
    shift
    if "$@" >"$log_file" 2>&1; then
        printf 'PASS'
    else
        printf 'FAIL'
    fi
}

verify_candidate() {
    local name=$1
    local candidate_dir=$2
    local work="$WORK_ROOT/$name"
    local logs="$RESULT_ROOT/logs/$name"
    mkdir -p "$logs"
    cp -R "$PROJECT" "$work"

    local scope=PASS
    if [ "$name" != "buggy" ]; then
        if [ ! -f "$candidate_dir/src/safe_ops.c" ] ||
           [ "$(find "$candidate_dir" -type f | wc -l | tr -d ' ')" != "1" ]; then
            scope=FAIL
        else
            cp "$candidate_dir/src/safe_ops.c" "$work/src/safe_ops.c"
        fi
    fi

    diff -u "$PROJECT/src/safe_ops.c" "$work/src/safe_ops.c" >"$logs/candidate.diff" || true

    local gcc_build
    gcc_build=$(run_gate "$logs/gcc-build.log" "$CMAKE" -S "$work" -B "$work/build-gcc" -DCMAKE_C_COMPILER="$GCC")
    if [ "$gcc_build" = PASS ]; then
        gcc_build=$(run_gate "$logs/gcc-compile.log" "$CMAKE" --build "$work/build-gcc")
    fi

    local clang_build
    clang_build=$(run_gate "$logs/clang-build.log" "$CMAKE" -S "$work" -B "$work/build-clang" -DCMAKE_C_COMPILER="$CLANG")
    if [ "$clang_build" = PASS ]; then
        clang_build=$(run_gate "$logs/clang-compile.log" "$CMAKE" --build "$work/build-clang")
    fi

    local public_tests=FAIL
    if [ "$clang_build" = PASS ]; then
        public_tests=$(run_gate "$logs/public-tests.log" "$CTEST" --test-dir "$work/build-clang" --output-on-failure)
    fi

    local static_analysis
    static_analysis=$(run_gate "$logs/cppcheck.log" "$CPPCHECK" --enable=warning,performance,portability --error-exitcode=1 --suppress=missingIncludeSystem -I "$work/include" "$work/src")

    local hidden_tests
    hidden_tests=$(run_gate "$logs/hidden-compile.log" "$CLANG" -std=c17 -Wall -Wextra -Wpedantic -Werror -I "$work/include" "$work/src/safe_ops.c" "$ORACLE/hidden_tests.c" -o "$work/hidden_tests")
    if [ "$hidden_tests" = PASS ]; then
        hidden_tests=$(run_gate "$logs/hidden-tests.log" "$work/hidden_tests")
    fi

    local sanitizer
    sanitizer=$(run_gate "$logs/sanitizer-compile.log" "$GCC" -std=c17 -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined -I "$work/include" "$work/src/safe_ops.c" "$ORACLE/hidden_tests.c" -o "$work/sanitizer_tests")
    if [ "$sanitizer" = PASS ]; then
        sanitizer=$(run_gate "$logs/sanitizer.log" env ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 "$work/sanitizer_tests")
    fi

    local fuzz_smoke
    fuzz_smoke=$(run_gate "$logs/fuzz-compile.log" "$GCC" -std=c17 -g -O1 -fno-omit-frame-pointer -fsanitize=address,undefined -I "$work/include" "$work/src/safe_ops.c" "$ORACLE/fuzz_smoke.c" -o "$work/fuzz_smoke")
    if [ "$fuzz_smoke" = PASS ]; then
        fuzz_smoke=$(run_gate "$logs/fuzz-smoke.log" env ASAN_OPTIONS=abort_on_error=1:symbolize=0:detect_leaks=0 "$work/fuzz_smoke")
    fi

    local accepted=PASS
    local gate
    for gate in "$scope" "$gcc_build" "$clang_build" "$public_tests" "$static_analysis" "$hidden_tests" "$sanitizer" "$fuzz_smoke"; do
        if [ "$gate" = FAIL ]; then
            accepted=FAIL
        fi
    done

    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$name" "$scope" "$gcc_build" "$clang_build" "$public_tests" \
        "$static_analysis" "$hidden_tests" "$sanitizer" "$fuzz_smoke" "$accepted" >>"$SUMMARY"
}

verify_candidate buggy ""

while IFS= read -r candidate_dir; do
    verify_candidate "$(basename "$candidate_dir")" "$candidate_dir"
done < <(find "$ROOT/candidates" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort)

# Remove the local workspace path before reports are committed or shared.
while IFS= read -r log_file; do
    sed -e "s|$ROOT|<demo-root>|g" -e 's/[[:space:]]*$//' "$log_file" >"$log_file.redacted"
    mv "$log_file.redacted" "$log_file"
done < <(find "$RESULT_ROOT/logs" -type f)

{
    printf '# Demo 实际运行结果\n\n'
    printf '> 结果由 `scripts/run_demo.sh` 生成；详细证据见 `logs/`。\n\n'
    printf '| 候选版本 | 范围 | GCC | Clang | 公开测试 | 静态分析 | 隐藏测试 | ASan/UBSan | fuzz-smoke | 最终接受 |\n'
    printf '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n'
    tail -n +2 "$SUMMARY" | while IFS=, read -r name scope gcc clang public static hidden sanitizer fuzz accepted; do
        printf '| `%s` | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
            "$name" "$scope" "$gcc" "$clang" "$public" "$static" "$hidden" "$sanitizer" "$fuzz" "$accepted"
    done
    printf '\n## 环境\n\n```text\n'
    "$CMAKE" --version | head -n 1
    "$GCC" --version | head -n 1
    "$CLANG" --version | head -n 1
    if [ -n "$CPPCHECK" ]; then "$CPPCHECK" --version; fi
    printf '```\n'
} >"$RESULT_ROOT/REPORT.md"

cat "$RESULT_ROOT/REPORT.md"
