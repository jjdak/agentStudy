# Demo task: fix zero padding for `inf` and `nan`

This is a teaching exercise based on `fmtlib__fmt-2310`. The repository is a
clean fmt snapshot from before the fix.

## Problem

The `0` option enables sign-aware zero padding for finite numeric values, but
the documentation says it has no effect on infinity and NaN:

```cpp
fmt::format("{:+06}", 12)   // "+00012" (keep this behavior)
fmt::format("{:+06}", NAN)  // currently "00+nan", should be "  +nan"
```

Explicit alignment must still work:

```text
{:<+06}  -> "+nan  "
{:^+06}  -> " +nan "
{:>+06}  -> "  +nan"
```

## Suggested workflow

1. Reproduce the failure before editing.
2. Trace parsing of the zero option and formatting of non-finite values.
3. Make the smallest maintainable change.
4. Run the demo smoke test and inspect the diff.
5. Explain the root cause and why finite values are unchanged.

This demo intentionally has no hidden tests or isolation requirement. The
reference answer is available from the Lab's `scripts/demo.sh answer` command;
try the task first if you want the debugging practice.
