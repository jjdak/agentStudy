# Coding Agent task: `fmtlib__fmt-2310`

You are working in a clean snapshot of the `fmtlib/fmt` repository before the issue was fixed.

## Problem statement

### Numeric zero fill is applied to inf/nan

From the documentation:

> Preceding the width field by a zero (`0`) character enables sign-aware zero-padding for numeric types. It forces the padding to be placed after the sign or base (if any) but before the digits. This is used for printing fields in the form `+000000120`. This option is only valid for numeric types and it has no effect on formatting of infinity and NaN.

```cpp
fmt::print("'{:+06}'\n", NAN);
// output: '00+nan'
```

## Working requirements

1. Inspect the repository and reproduce or locate the behavior before editing.
2. Explain the relevant formatting path and the first point where behavior diverges from the documented rule.
3. Implement the smallest maintainable fix that preserves existing finite-number formatting.
4. Do not access the network, Git remotes, tags, upstream history, reference patches, hidden tests, or other runs.
5. Do not delete, skip, weaken, or special-case tests to obtain a pass. Do not change public behavior unrelated to this issue.
6. Run the most relevant public tests available in the repository. Distinguish checks actually run from checks not run.
7. Do not commit or push.

## Final report

Return:

- root cause and affected code path;
- files changed and why;
- commands run with outcomes;
- checks not run and why;
- remaining risks or assumptions.

The final patch will be evaluated outside your workspace with the fixed SWE-bench test oracle. Do not claim that hidden evaluation passed.
