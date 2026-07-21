# Long-task experiment report

## Fixed inputs

| Field | Value |
|---|---|
| Run ID | |
| Agent / version | |
| Model / exact version | |
| Source SHA-256 | |
| Prompt SHA-256 | |
| Toolchain image ID | |
| Network and permission policy | |
| Context/tool/time budget | |

## Quantitative result

| Metric | Result | Evidence |
|---|---:|---|
| Patch applies | | `01-patch.log` |
| Sanitizer build | | `02-build.log` |
| External black-box checks | | `03-black-box.log` |
| Upstream hidden tests | | `04-hidden-tests.log` |
| Selected regressions | | `05-regression-tests.log` |
| Full regression | | `06-full-regression.log` or not run |
| `resolved` | | `summary.json` |
| Evaluation wall time | | `summary.json` |
| Candidate test files ignored | | `summary.json` |
| Agent wall time / calls / cost | | run notes or client telemetry |
| Human interventions | | run notes |
| Human review time | | run notes |

## Process observations

- Did the Agent map the correct modules before implementation?
- Which requirement or cross-module dependency was first missed?
- How many times did it repeat the same repository search or failed approach?
- Could a new session resume from `STATUS.md` without rereading the whole repository?
- Which claims in the completion report were and were not supported by actual commands?
- Did independent scoring disagree with the Agent's own conclusion? Why?

## Manual review

- Scope and unnecessary changes:
- Ownership, cleanup and error propagation:
- Compatibility and maintainability:
- Test quality added by the Agent (not used as the scoring oracle):
- Remaining risks:
- Accept / reject decision and reason:

## Cross-run comparison

Compare only runs with identical source, prompt, harness, permissions, budgets and image ID. Report all repetitions, including failures; do not select only the best run.
