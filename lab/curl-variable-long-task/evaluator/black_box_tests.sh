#!/usr/bin/env bash

set -euo pipefail

: "${CURL_BIN:?set CURL_BIN to the curl executable under test}"
[ -x "$CURL_BIN" ] || { printf 'not executable: %s\n' "$CURL_BIN" >&2; exit 2; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
empty_url="file://$tmp/empty"
: >"$tmp/empty"
passed=0

fail() {
    printf 'FAIL %s: %s\n' "$1" "$2" >&2
    exit 1
}

expect_output() {
    local name=$1
    local expected=$2
    shift 2
    local actual
    if ! actual=$("$CURL_BIN" -sS -o /dev/null "$@" "$empty_url" 2>"$tmp/stderr"); then
        fail "$name" "command failed: $(tr '\n' ' ' <"$tmp/stderr")"
    fi
    [ "$actual" = "$expected" ] || fail "$name" "expected [$expected], got [$actual]"
    passed=$((passed + 1))
    printf 'PASS %s\n' "$name"
}

expect_failure() {
    local name=$1
    shift
    if "$CURL_BIN" -sS -o /dev/null "$@" "$empty_url" >"$tmp/stdout" 2>"$tmp/stderr"; then
        fail "$name" "command unexpectedly succeeded"
    fi
    passed=$((passed + 1))
    printf 'PASS %s\n' "$name"
}

"$CURL_BIN" --help all | grep -q -- '--variable' \
    || fail help "--variable is absent from --help all"
passed=$((passed + 1)); printf 'PASS help\n'

expect_output simple hello --variable name=hello --expand-write-out '{{name}}'
expect_output missing 'ab' --expand-write-out 'a{{not_set}}b'
expect_output overwrite two --variable value=one --variable value=two --expand-write-out '{{value}}'

export AGENTSTUDY_PRESENT='from-env'
expect_output env-present from-env --variable %AGENTSTUDY_PRESENT --expand-write-out '{{AGENTSTUDY_PRESENT}}'
unset AGENTSTUDY_ABSENT || true
expect_output env-fallback fallback --variable %AGENTSTUDY_ABSENT=fallback --expand-write-out '{{AGENTSTUDY_ABSENT}}'
expect_failure env-required --variable %AGENTSTUDY_ABSENT --expand-write-out '{{AGENTSTUDY_ABSENT}}'

printf '  a b  \n' >"$tmp/value.txt"
expect_output file-trim 'a b' --variable "value@$tmp/value.txt" --expand-write-out '{{value:trim}}'
expect_output transform-chain 'a%20b' --variable "value@$tmp/value.txt" --expand-write-out '{{value:trim:url}}'
expect_output json 'a\"b' --variable 'value=a"b' --expand-write-out '{{value:json}}'
expect_output base64 YWJj --variable value=abc --expand-write-out '{{value:b64}}'
expect_failure bad-transform --variable value=abc --expand-write-out '{{value:unknown}}'

printf 'stdin-value' | "$CURL_BIN" -sS -o /dev/null \
    --variable value@- --expand-write-out '{{value}}' "$empty_url" >"$tmp/stdin.out"
[ "$(cat "$tmp/stdin.out")" = stdin-value ] || fail stdin "stdin import mismatch"
passed=$((passed + 1)); printf 'PASS stdin\n'

printf 'target' >"$tmp/expanded.txt"
actual=$("$CURL_BIN" -sS --variable "path=$tmp/expanded.txt" --expand-url 'file://{{path}}')
[ "$actual" = target ] || fail expand-url "expected [target], got [$actual]"
passed=$((passed + 1)); printf 'PASS expand-url\n'

printf 'x\0y' >"$tmp/nul.bin"
expect_failure raw-nul --variable "value@$tmp/nul.bin" --expand-write-out '{{value}}'

printf 'black-box tests: PASS (%d checks)\n' "$passed"
