# Task: add command-line variables and option expansion to curl

Implement a complete user-facing variable facility in this curl snapshot. This is a repository-scale task: it crosses command parsing, generated option metadata, ownership/cleanup, documentation, build integration and tests.

## Required behavior

1. Add `--variable <name=value>` and `--variable <name@file>`. A file name of `-` reads the value from standard input.
2. Add environment import forms:
   - `--variable %name` requires the environment variable to exist;
   - `--variable %name=default` and `%name@default-file` use the fallback only when it does not exist.
3. A later assignment of the same name replaces the earlier value.
4. For every long command-line option whose argument is a string, accept an `--expand-<option>` form. Expand `{{name}}` references in that option argument; an unknown variable expands to an empty string.
5. `\{{name}}` is literal `{{name}}`. Invalid names, overlong names and unbalanced braces must be handled without unsafe reads or writes and with behavior consistent with curl's command-line error conventions.
6. Support left-to-right transformation chains written with colons:
   - `trim`: remove leading and trailing whitespace;
   - `json`: JSON-string escape the value without adding surrounding quotes;
   - `url`: percent-encode the value;
   - `b64`: Base64-encode the value.
7. Reject unknown transformations. Reject an unencoded NUL byte when expansion would insert it into a command-line string.
8. Integrate help text and standalone option documentation. Preserve existing command-line behavior, including config files and `--next`.
9. Correctly own and release all variable data. Do not add a dependency or change a public libcurl API/ABI.

Examples use a local URL only to make `--write-out` execute:

```console
curl --variable name=world --expand-write-out 'hello {{name}}' -o /dev/null file:///dev/null
curl --variable 'text=  a b  ' --expand-write-out '{{text:trim:url}}' -o /dev/null file:///dev/null
```

## Working contract

- Work only in this repository snapshot. Do not use the network, a remote, hidden tests, an upstream patch, release code or another run's files. Do not commit, change branches, rewrite history, alter remotes or edit `.git/info/exclude`; staging is allowed.
- You may modify source, build metadata, documentation and repository tests. Do not disable existing tests, sanitizers or warnings.
- Use `.agent/REPO_MAP.md`, `SPEC.md`, `DESIGN.md`, `TASKS.md` and `STATUS.md` as durable state. Update `STATUS.md` before a context reset or handoff.
- First map the repository and turn the requirements into a specification. Then make small work packages with observable completion checks. Implement only after the affected components and build integration are understood.
- Use the provided toolchain wrapper for commands. It has no network and can see only this workspace. Do not attempt to access Docker or host paths directly.
- Run focused checks after each work package. Before completion, build from a clean build directory and run all relevant public tests you can afford.
- A command attempt is not a passing check. Record command, exit status and result. If a required check cannot run, report it as unverified.
- Do not claim that independent or hidden evaluation passed; you cannot see or run it.

## Completion report

Report:

1. the implemented behavior and main design decisions;
2. files and subsystems changed;
3. exact build/test commands and exit status;
4. checks not run and why;
5. remaining risks and the next highest-value verification.
