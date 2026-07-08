# 子 Agent Prompt 策略实验报告

实验日期：2026-07-08

## 1. 实验目的

本次实验验证 `prompts/` 中三种 Coding Agent 使用策略在同一个 C 缺陷修复任务上的实际效果：

- `01_one_shot.md`：一句话修复；
- `02_public_test_loop.md`：允许基于公开测试反复修复；
- `03_reliable_flow.md`：要求根因分析、修改边界、自查和风险披露。

与 `strategy-a/b/c` 这三个固定教学候选不同，本次实验使用真实子 Agent 独立生成修复结果，再由主 Agent 统一运行隐藏验证器和质量门禁。

## 2. 实验设计

每种策略运行 2 次，共 6 个子 Agent：

| 策略 | 运行编号 | 工作区 | 输出候选 |
|---|---|---|---|
| one-shot | 1 | `/private/tmp/cpp-agent-prompt-runs/one-shot-1/project` | `candidates/agent-one-shot-1/` |
| one-shot | 2 | `/private/tmp/cpp-agent-prompt-runs/one-shot-2/project` | `candidates/agent-one-shot-2/` |
| public-test-loop | 1 | `/private/tmp/cpp-agent-prompt-runs/public-test-loop-1/project` | `candidates/agent-public-test-loop-1/` |
| public-test-loop | 2 | `/private/tmp/cpp-agent-prompt-runs/public-test-loop-2/project` | `candidates/agent-public-test-loop-2/` |
| reliable-flow | 1 | `/private/tmp/cpp-agent-prompt-runs/reliable-flow-1/project` | `candidates/agent-reliable-flow-1/` |
| reliable-flow | 2 | `/private/tmp/cpp-agent-prompt-runs/reliable-flow-2/project` | `candidates/agent-reliable-flow-2/` |

对子 Agent 的限制：

- 只能阅读各自工作区内的 `PROMPT.md` 和 `project/`；
- 只能修改 `project/src/safe_ops.c`；
- 禁止查看 `oracle/`、`scripts/run_demo.sh`、`results/`、`candidates/`、隐藏测试、fuzz-smoke 或其它策略结果；
- 子 Agent 不运行隐藏验证；
- 主 Agent 不修改子 Agent 产出的修复，只负责收集和评分。

受当前工具环境限制，隔离方式是“目录隔离 + 指令约束”，不是强沙箱。更严格实验应把公开项目复制到独立容器或单独仓库，并从文件系统层面禁止访问 oracle。

## 3. 统一验证流程

主 Agent 将 6 份 `safe_ops.c` 放入 `candidates/agent-*/src/safe_ops.c` 后，运行：

```sh
CMAKE=/private/tmp/cmake-python/bin/cmake \
CTEST=/private/tmp/cmake-python/bin/ctest \
PYTHONPATH=/private/tmp/cmake-python \
demo/cpp-agent-repair/scripts/run_demo.sh
```

验证脚本会自动遍历 `candidates/*`，并对每个候选执行：

1. 修改范围检查；
2. GNU GCC 构建；
3. Clang 构建；
4. 公开 CTest；
5. cppcheck；
6. 隐藏回归测试；
7. ASan/UBSan；
8. 确定性 fuzz-smoke；
9. 生成 `summary.csv`、`REPORT.md` 和逐项日志。

## 4. 量化结果

完整日志见 [results/latest/REPORT.md](latest/REPORT.md) 和 [results/latest/logs/](latest/logs/)。

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

## 5. 观察结论

### 5.1 在当前小型 Demo 上，三种真实 prompt 策略没有拉开最终正确率差距

6 个真实子 Agent 输出全部通过隐藏测试、Sanitizer 和 fuzz-smoke。原因很可能是：

- Demo 代码规模很小；
- 函数命名和公开源码给出了较强语义线索；
- 当前 Coding Agent 能通过静态阅读主动识别隐藏风险；
- 每个子 Agent 都被告知只能改 `safe_ops.c`，减少了搜索空间。

因此，本次实验不能证明 `reliable-flow` 在正确率上优于其它 prompt。它只能说明：在这个小任务中，三种策略都足以产出可接受修复。

### 5.2 继续比较“是否修对”意义有限，应转向比较思考路径和输出完整性

如果只看 `PASS/FAIL`，三种真实 prompt 策略在本轮实验中没有差异。但从子 Agent 的最终说明看，策略之间仍有明显过程差异：

| 比较维度 | one-shot | public-test-loop | reliable-flow |
|---|---|---|---|
| 输出长度 | 较短 | 中等 | 较长 |
| 信息组织 | 修改点列表 | 修改点 + 公开测试结果 | 根因 → 修复 → 检查 → 剩余风险 |
| 根因表达 | 能说明修了什么，但偏结果描述 | 能说明修了什么，并强调公开测试通过 | 明确把每个问题映射到根因 |
| 验证边界 | 主要报告公开测试 | 公开测试为主，偶尔尝试额外检查 | 明确区分已运行、未运行和未完成检查 |
| 风险披露 | 较少 | 有少量环境/检查说明 | 明确披露工具链和 Sanitizer 风险 |
| 人工复盘成本 | reviewer 需要自己反推 Agent 是否理解根因 | 中等 | 最低，最终说明接近工程复盘 |

这说明：当强 Agent 都能修对时，prompt 的价值不一定体现在最终正确率，而体现在它是否诱导 Agent 留下足够完整、诚实、结构化的思考痕迹。

### 5.3 reliable-flow 的优势主要体现在“可审计过程”而非本轮正确率

`reliable-flow` 子 Agent 的最终说明更接近工程复盘：

- 明确列出根因到修复的映射；
- 记录了修改边界；
- 区分了公开检查和未运行检查；
- 发现并披露 `/usr/bin/gcc` 在 macOS 上实际是 AppleClang，不是真正 GNU GCC；
- 没有把未完成的 sanitizer 尝试描述成通过。

这类过程信息不能替代隐藏验证，但能帮助人工 reviewer 更快判断“Agent 是否真的理解了修改”。

### 5.4 教学夹具仍然有价值

固定候选 `strategy-a-one-shot` 和 `strategy-b-public-tests` 仍然失败，说明验证流水线能够筛掉：

- 只修公开测试失败行的补丁；
- 让公开测试通过但遗漏整数溢出、Use-after-free、二进制回归的补丁。

也就是说，真实子 Agent 结果展示“当前 Agent 在小任务上可以很强”，固定候选展示“为什么仍然需要独立质量门禁”。二者回答的是不同问题。

## 6. 本次实验对个人学习的启发

如果只是想学习 Agent 使用方法，不要急着寻找更难的题目。这个 Demo 已经能支持三个层次的练习：

1. 先跑固定候选，理解公开测试、隐藏测试、Sanitizer 和 fuzz-smoke 各自发现什么；
2. 再像本次一样用真实 Agent 生成候选，观察 prompt 是否影响修复质量和自述质量；
3. 最后重点比较 Agent 输出是否全面：根因是否清楚、风险是否披露、验证是否诚实、reviewer 是否容易接管。

当前结果提示：对于简单、局部、语义清晰的缺陷，prompt 策略可能不是最终正确率的主要瓶颈；但 prompt 仍会影响 Agent 的工作方式，尤其是证据链、风险声明和复盘质量。

## 7. 后续改进方向

- 每种策略增加到 5～10 次运行，观察稳定性；
- 记录模型版本、温度、耗时、工具调用次数和 token 成本；
- 使用容器或单独仓库实现硬隔离；
- 将隐藏验证失败作为“受控反馈”，比较一轮修复与多轮 CEGIS 式修复差异；
- 对子 Agent 输出做盲审：只看 diff 和日志，不看策略名。
- 给每次子 Agent 输出增加过程评分，例如根因完整性、风险覆盖、验证诚实度、修改范围自查和 reviewer 接管成本。
