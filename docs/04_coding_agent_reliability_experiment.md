# 04. 用一个可运行 Demo 理解 Coding Agent 可靠流程

> 适用场景：个人学习与演示
>
> 配套代码：[C/C++ Coding Agent 可靠性 Demo](../demo/cpp-agent-repair/README.md)
>
> 实际结果：[最近一次运行报告](../demo/cpp-agent-repair/results/latest/REPORT.md)
>
> 子 Agent 策略实验：[真实子 Agent Prompt 策略实验报告](../demo/cpp-agent-repair/results/agent_prompt_strategy_report.md)

## 1. 这个 Demo 要回答什么

前面的文档总结了很多原则：明确任务、限制权限、寻找根因、运行测试、检查 diff、使用 Sanitizer、保存证据。但只读原则很难形成直觉。

这个 Demo 用一个很小的 C 项目回答三个具体问题：

1. Agent 把公开测试修绿，是否代表代码真的正确？
2. 更完整的任务要求和验证流程，能发现哪些“一句话修复”遗漏的问题？
3. 如何让“已完成”变成可以从日志和工具输出中复查的结论？

它不是模型排行榜，也不是论文级评测。Demo 既包含固定候选补丁，用来稳定展示质量门禁的作用；也可以把候选补丁换成真实 Agent 输出，观察不同 prompt 策略的实际差异。

## 2. 重新定位：不要把 Demo 变成“难倒 Agent 的题”

这次真实子 Agent 实验带来了一个重要观察：强 Agent 在小型、局部、语义清晰的代码上，即使拿到很短的 prompt，也可能主动补全隐藏风险并修对全部问题。

所以，这个 Demo 不再试图证明“复杂 prompt 一定让功能正确率更高”。那个目标很容易被模型能力本身掩盖，也容易把学习者带向不断寻找更难题的方向。

新的定位是：

> 比较不同 prompt 策略是否让 Agent 的修复过程更可审计、更全面、更容易复盘，而不仅仅是比较最终是否通过测试。

具体比较对象从“能不能修对”扩展为：

- 是否说明根因，而不是只说明改了什么；
- 是否覆盖公开测试之外的边界和回归风险；
- 是否明确修改范围；
- 是否区分已经运行的检查和没有运行的检查；
- 是否暴露环境、工具链、Sanitizer 等验证不确定性；
- 是否能让人工 reviewer 快速判断“它是不是理解了问题”。

这更接近个人或工程使用 Agent 时真正关心的问题：强 Agent 可以很聪明，但我们仍然需要让它的聪明变得可控、可验证、可接管。

## 3. 项目结构

```text
demo/cpp-agent-repair/
├── project/                   # 发给 Agent 的带 Bug 项目
│   ├── include/safe_ops.h
│   ├── src/safe_ops.c
│   ├── tests/public_tests.c
│   └── CMakeLists.txt
├── prompts/                   # 三种 Agent 使用策略
│   ├── 01_one_shot.md
│   ├── 02_public_test_loop.md
│   └── 03_reliable_flow.md
├── candidates/                # 固定候选补丁夹具和真实 Agent 输出
│   ├── strategy-a-one-shot/
│   ├── strategy-b-public-tests/
│   └── strategy-c-reliable/
├── oracle/                    # 不应提供给被测 Agent
│   ├── hidden_tests.c
│   └── fuzz_smoke.c
├── scripts/run_demo.sh        # 独立验证入口
└── results/latest/            # 汇总、diff 和原始日志
```

这里的“隐藏”表示对被测 Agent 隐藏，不表示对学习者隐藏。你可以阅读 oracle 来理解为什么某个补丁失败。测试真实 Agent 时，应只把 `project/` 放进 Agent 工作区，把 oracle 和验证脚本留在沙箱外。

## 4. 带 Bug 的代码仓库

`safe_ops.c` 包含五类常见问题：

| 缺陷 | 初始问题 | 容易出现的表面修复 | 独立验证方法 |
|---|---|---|---|
| 逻辑错误 | 百分比上界返回 99 | 只改公开失败行 | 公开与边界测试 |
| 缓冲区越界 | 二进制复制多复制一个“终止符” | 扩大缓冲区或只挡住当前输入 | 边界哨兵 + ASan |
| 整数溢出 | `count * size + header` 未检查 | 只检查乘法，遗漏加法 | `SIZE_MAX` 边界测试 + UBSan |
| Use-after-free | `free()` 后读取节点值 | 去掉 `free()`，把 UAF 变成泄漏 | 链表状态测试 + ASan |
| 回归问题 | 用 `strlen()` 处理二进制 buffer | 公开文本测试通过 | 含 `\0` 的隐藏回归 + fuzz-smoke |

公开测试故意不完整：它明确暴露逻辑错误，只覆盖其余 API 的普通路径。这模拟了真实项目中“现有测试能复现用户问题，但没有穷尽边界和安全性质”的情况。

## 5. 三种 Agent 使用策略

### 5.1 策略 A：一句话修复

```text
这个 C 项目的测试失败了，请修复代码。完成后告诉我结果。
```

它没有说明：

- 允许修改什么；
- 是修复根因还是只让当前测试消失；
- 应运行哪些检查；
- 什么证据才能宣称完成。

固定候选 `strategy-a-one-shot` 只修复公开测试直接指出的百分比上界。公开测试会通过，另外四类问题仍然存在。

### 5.2 策略 B：让 Agent 运行现有测试

```text
请分析并修复这个 C 项目。允许修改 src/safe_ops.c，并运行项目现有的 CMake/CTest 测试。
测试通过后给出修改摘要和测试结果。
```

相比策略 A，它有修改范围和工具反馈，但验收标准仍是“现有测试通过”。固定候选 `strategy-b-public-tests` 修复了逻辑和复制错误，也增加了部分乘法检查，但遗漏：

- `header` 加法仍能溢出；
- 链表仍在 `free()` 后读取；
- 二进制数据仍交给 `strlen()`。

### 5.3 策略 C：任务合同与独立验证

可靠策略明确要求：

- 只修改 `src/safe_ops.c`；
- 先说明候选根因和验证计划；
- 分别检查乘法与加法溢出；
- 不把二进制 buffer 当字符串；
- 验证对象生命周期；
- 由独立脚本运行双编译器、隐藏回归、静态分析、ASan/UBSan 和 fuzz-smoke；
- 失败时不能宣称完成。

完整提示词见 [03_reliable_flow.md](../demo/cpp-agent-repair/prompts/03_reliable_flow.md)。

这里最重要的变化不是“提示词更长”，而是 prompt 把 Agent 的工作方式从“直接给答案”约束成“说明根因、控制范围、暴露风险、等待独立验证”。

## 6. 验证流水线

运行：

```sh
cd demo/cpp-agent-repair
./scripts/run_demo.sh
```

验证脚本对初始代码和 `candidates/*` 下的所有候选版本执行相同流程：

```mermaid
flowchart LR
    A["候选 safe_ops.c"] --> B["修改范围"]
    B --> C["GNU GCC 构建"]
    C --> D["Clang 构建"]
    D --> E["公开 CTest"]
    E --> F["cppcheck"]
    F --> G["隐藏回归"]
    G --> H["ASan / UBSan"]
    H --> I["10000 次 fuzz-smoke"]
    I --> J["生成 CSV、报告和日志"]
```

### 每一层证明什么

| 门禁 | 可以证明 | 不能单独证明 |
|---|---|---|
| 修改范围 | 候选目录只提供允许的源码文件 | 源码语义正确 |
| GCC/Clang | 两个编译器接受代码和警告策略 | 运行行为正确 |
| 公开测试 | 已知普通路径和报告问题通过 | 边界、安全和回归完整 |
| cppcheck | 固定规则没有报告对应静态问题 | 不存在所有漏洞 |
| 隐藏测试 | 预先设计的边界和回归通过 | 未测试输入全部正确 |
| ASan/UBSan | 本次运行未触发所覆盖的内存/UB 问题 | 没有未执行到的问题 |
| fuzz-smoke | 固定 10,000 组二进制输入满足参考性质 | 长时间 fuzz 也不会失败 |

所有 gate 通过仍然是“在这些明确检查下有证据接受”，不是数学意义上的绝对正确。

## 7. 如何阅读实际结果

最近一次运行结果保存在 [REPORT.md](../demo/cpp-agent-repair/results/latest/REPORT.md)。本次实际执行得到：

| 候选版本 | GCC | Clang | 公开测试 | cppcheck | 隐藏测试 | ASan/UBSan | fuzz-smoke | 接受 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `buggy` | FAIL | PASS | FAIL | PASS | FAIL | FAIL | FAIL | FAIL |
| `agent-one-shot-1` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-one-shot-2` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-public-test-loop-1` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-public-test-loop-2` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-reliable-flow-1` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `agent-reliable-flow-2` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `strategy-a-one-shot` | FAIL | PASS | PASS | PASS | FAIL | FAIL | FAIL | FAIL |
| `strategy-b-public-tests` | FAIL | PASS | PASS | PASS | FAIL | FAIL | FAIL | FAIL |
| `strategy-c-reliable` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

这次运行揭示了几个很直观的事实：

- 策略 A/B 都让公开测试变绿，但仍不能接受；
- GNU GCC 的严格告警直接发现了 Use-after-free，而本次 cppcheck 没有发现，说明静态工具之间也不能互相替代；
- 策略 B 的 Sanitizer 日志明确报告 `heap-use-after-free`，fuzz-smoke 则立即发现二进制计数回归；策略 C 才通过全部门禁。
- 真实子 Agent 的 6 次运行全部通过门禁，说明在当前小型 Demo 上，当前 Coding Agent 即使在 one-shot 条件下也能通过源码语义主动修复隐藏问题。
- 本轮真实实验没有证明 reliable-flow 的最终正确率更高，但 reliable-flow 的输出更容易审计：它明确列出根因、检查边界、未完成验证和环境风险。

真实子 Agent 实验的完整记录见 [agent_prompt_strategy_report.md](../demo/cpp-agent-repair/results/agent_prompt_strategy_report.md)。学习时应区分两类结果：固定候选用于稳定展示质量门禁；真实 Agent 候选用于观察 prompt 策略在当前模型和任务上的实际效果。

### 从思考路径和全面性比较，而不是只看 PASS/FAIL

本轮 6 个真实子 Agent 都通过了最终门禁，但它们的输出质量并不完全一样。可以按下面的维度阅读：

| 维度 | one-shot | public-test-loop | reliable-flow |
|---|---|---|---|
| 最终功能结果 | 通过 | 通过 | 通过 |
| 修复说明 | 能列出改动点 | 能列出改动点和公开测试结果 | 能建立“根因 → 修复”的映射 |
| 验证意识 | 主要报告公开测试 | 主要围绕公开测试迭代 | 区分公开检查、未运行检查和独立验证 |
| 风险披露 | 较少 | 有时提到未完成检查 | 明确记录工具链风险、Sanitizer 未完成等边界 |
| reviewer 接管成本 | 需要 reviewer 自己反推根因 | 中等 | 最低，信息结构最接近工程复盘 |
| 防止虚假完成 | 依赖外部验证器 | 依赖外部验证器 | prompt 本身也要求不能夸大验证结论 |

因此，这个 Demo 的结论不是“可靠 prompt 才能修对”，而是：

> 在强 Agent 也能修对的情况下，可靠 prompt 的价值主要体现在过程质量：它让输出更全面、更诚实、更方便人审查。

学习时不要只看汇总表。打开：

```text
results/latest/logs/<candidate>/candidate.diff
results/latest/logs/<candidate>/public-tests.log
results/latest/logs/<candidate>/hidden-tests.log
results/latest/logs/<candidate>/sanitizer.log
results/latest/logs/<candidate>/fuzz-smoke.log
```

然后回答：哪个版本第一次让公开测试通过？哪个版本第一次真正处理了 Use-after-free？哪一层发现了二进制输入回归？如果只看 Agent 的完成说明，会接受哪个错误补丁？

## 8. 用真实 Agent 重做实验

固定候选只是让 Demo 可重复。要观察真实 Agent：

1. 为每次运行复制一份干净 `project/`；
2. 只让 Agent 看到该副本和对应策略提示词；
3. 不让 Agent 读取 `oracle/`、已有 candidates 和结果；
4. 保存模型、Agent 版本、提示词、耗时和最终 `safe_ops.c`；
5. 把文件放入新的 `candidates/<run-id>/src/safe_ops.c`；
6. 由 Agent 会话之外的脚本运行相同验证；
7. 至少重复三次，因为模型输出具有随机性。

建议记录两张表。第一张仍然记录工具验证结果：

| run | 策略 | 公开测试 | 隐藏测试 | Sanitizer | fuzz | 越界修改 | 耗时 |
|---|---|---:|---:|---:|---:|---:|---:|

第二张专门记录过程质量：

| run | 策略 | 是否说明根因 | 是否覆盖 5 类风险 | 是否说明验证边界 | 是否披露不确定性 | reviewer 复盘难度 |
|---|---|---:|---:|---:|---:|---|

这里的目标不是做严格模型评测，而是训练自己看懂 Agent 输出：它是只给了一个看似完成的答案，还是留下了足够证据让你放心接管。

## 9. 如何判断 prompt 是否真的更好

不要只问“结果是否 PASS”。对于强模型，很多简单任务都会 PASS。更有用的问题是：

1. 它有没有先定位根因，再修改代码？
2. 它有没有解释为什么修改发生在这里，而不是在报错表现处打补丁？
3. 它有没有主动检查公开测试没覆盖的边界？
4. 它有没有把“我运行过的检查”和“还没验证的风险”分开？
5. 它有没有限制修改范围，避免顺手改测试、改接口、改无关文件？
6. 它有没有在工具卡住或环境异常时如实说明，而不是把尝试说成通过？
7. 它的最终说明是否足够让另一个人继续 review？

如果一个 prompt 能稳定诱导 Agent 输出这些信息，即使最终功能正确率没有明显差异，它仍然是更适合工程使用的 prompt。

## 10. 当前 Demo 的边界

- 固定候选补丁是教学夹具，不是模型效果数据；
- oracle 与项目位于同一 Git 仓库，只有目录隔离；测试真实 Agent 时需要沙箱或独立目录；
- fuzz-smoke 是固定随机种子的属性测试，不等价于长时间 libFuzzer/AFL++；
- macOS 上使用 ASan/UBSan，未单独启用 LeakSanitizer；
- Demo 代码很小，不能代表大型遗留项目、并发问题或复杂构建系统。

这些限制是刻意的：当前目标不是找到一个难倒模型的题，而是把可靠流程变成一个能运行、能观察、能复盘的学习工具。理解它之后，重点应该放在如何布置任务、如何记录证据、如何审查 Agent 的思考路径，而不是继续追求更复杂的样例。
