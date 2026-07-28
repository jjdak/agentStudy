# Demo task: add command-line variables to curl

This is a large teaching exercise based on curl's command-line variable
feature. The snapshot predates the implementation.

## Goal

Implement enough of the feature to make steady, observable progress across a
large C repository:

- `--variable name=value`;
- environment and file imports;
- `--expand-<option>` with `{{name}}`;
- `trim`, `json`, `url`, and `b64` transformations;
- help, standalone documentation, build integration, ownership, and cleanup.

The full behavioral contract remains in `.agent/SPEC.md`. Use the other
`.agent/*.md` files to record the repository map, design, work packages, and
status between sessions.

## Suggested learning path

1. Run the visible black-box test before editing and record the failure.
2. Map option generation, command parsing, transfer configuration, cleanup,
   documentation, and tests.
3. Split the implementation into work packages.
4. Build and run the visible checks after each coherent change.
5. Compare your design and patch with the upstream reference implementation.

This demo intentionally does not hide the oracle or reference answer. From the
Lab directory:

```bash
./scripts/demo.sh test demo-large
./scripts/demo.sh answer demo-large --show
```

There is no Docker, network isolation, hidden scoring, or requirement to treat
the result as a model benchmark. The purpose is to practice long-task state and
cross-module engineering.
