# Demo 实际运行结果

> 结果由 `scripts/run_demo.sh` 生成；详细证据见 `logs/`。

| 候选版本 | 范围 | GCC | Clang | 公开测试 | 静态分析 | 隐藏测试 | ASan/UBSan | fuzz-smoke | 最终接受 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `buggy` | PASS | FAIL | PASS | FAIL | PASS | FAIL | FAIL | FAIL | FAIL |
| `agent-one-shot-1` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-one-shot-2` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-public-test-loop-1` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-public-test-loop-2` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-reliable-flow-1` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-reliable-flow-2` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `strategy-a-one-shot` | PASS | FAIL | PASS | PASS | PASS | FAIL | FAIL | FAIL | FAIL |
| `strategy-b-public-tests` | PASS | FAIL | PASS | PASS | PASS | FAIL | FAIL | FAIL | FAIL |
| `strategy-c-reliable` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

## 环境

```text
cmake version 3.31.6
gcc-16 (Homebrew GCC 16.1.0) 16.1.0
Apple clang version 17.0.0 (clang-1700.6.4.2)
Cppcheck 2.21.0
```
