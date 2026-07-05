# 04. 用一个可运行 Demo 理解 Coding Agent 可靠流程

> 适用场景：个人学习与演示
>
> 配套代码：[C/C++ Coding Agent 可靠性 Demo](../demo/cpp-agent-repair/README.md)
>
> 实际结果：[最近一次运行报告](../demo/cpp-agent-repair/results/latest/REPORT.md)

## 1. 这个 Demo 要回答什么

前面的文档总结了很多原则：明确任务、限制权限、寻找根因、运行测试、检查 diff、使用 Sanitizer、保存证据。但只读原则很难形成直觉。

这个 Demo 用一个很小的 C 项目回答三个具体问题：

1. Agent 把公开测试修绿，是否代表代码真的正确？
2. 更完整的任务要求和验证流程，能发现哪些“一句话修复”遗漏的问题？
3. 如何让“已完成”变成可以从日志和工具输出中复查的结论？

它不是模型排行榜，也不是论文级 benchmark。Demo 使用固定候选补丁，保证每次运行都能稳定展示质量门禁的作用；之后可以把候选补丁换成真实 Agent 输出。

## 2. 来自成熟开源项目的最小借鉴

本 Demo 不复刻大型基准，只抽取几个已经被广泛使用的结构：

| 来源 | 借鉴内容 | Demo 中的实现 |
|---|---|---|
| [Multi-SWE-bench](https://github.com/multi-swe-bench/multi-swe-bench) | Agent 产生补丁，独立 harness 评分 | `candidates/` 与 `scripts/run_demo.sh` 分离 |
| [BUGSC++](https://github.com/Suresoft-GLaDOS/bugscpp/) | 可重复的 C/C++ 缺陷环境 | 固定源码、编译器命令和测试入口 |
| [TutorCode/CREF](https://github.com/GLEAM-Lab/CREF) | 公开测试与隐藏 judge 分离 | `project/tests/` 与 `oracle/hidden_tests.c` 分离 |
| [LLM-CEGIS-Repair](https://github.com/pmorvalho/LLM-CEGIS-Repair) | 失败反例帮助下一轮修正 | 可把隐藏失败作为受控反馈，再提交新候选 |
| [OSS-Fuzz-Gen](https://github.com/google/oss-fuzz-gen) | 用模型外运行信号检查代码 | ASan/UBSan 与确定性 fuzz-smoke |

ManyBugs 和 Codeflaws 适合以后扩充真实缺陷数量；当前 Demo 优先保证几分钟内可以读懂、运行和修改。

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
├── candidates/                # 固定候选补丁夹具
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

这里最重要的变化不是“提示词更长”，而是完成标准可以由模型之外的工具判定。

## 6. 验证流水线

运行：

```sh
cd demo/cpp-agent-repair
./scripts/run_demo.sh
```

验证脚本对初始代码和三个候选版本执行相同流程：

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
| `strategy-a-one-shot` | FAIL | PASS | PASS | PASS | FAIL | FAIL | FAIL | FAIL |
| `strategy-b-public-tests` | FAIL | PASS | PASS | PASS | FAIL | FAIL | FAIL | FAIL |
| `strategy-c-reliable` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |

这次运行揭示了三个很直观的事实：

- 策略 A/B 都让公开测试变绿，但仍不能接受；
- GNU GCC 的严格告警直接发现了 Use-after-free，而本次 cppcheck 没有发现，说明静态工具之间也不能互相替代；
- 策略 B 的 Sanitizer 日志明确报告 `heap-use-after-free`，fuzz-smoke 则立即发现二进制计数回归；策略 C 才通过全部门禁。

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

建议记录一张简单表，而不立即做复杂统计：

| run | 策略 | 公开测试 | 隐藏测试 | Sanitizer | fuzz | 越界修改 | 耗时 |
|---|---|---:|---:|---:|---:|---:|---:|

当运行次数增加、需要比较模型或 Agent 产品时，再考虑更严格的随机化、盲审和置信区间。

## 9. 第二个 Demo：让 Agent 制作完整项目

缺陷修复 Demo 跑通后，可以增加“从规格创建完整项目”：

```text
目标：实现一个小型任务调度器库和 CLI。
固定输入：API、行为样例、错误处理、性能边界和文件范围。
隐藏验收：边界测试、属性测试、静态分析、Sanitizer 和命令行快照。
比较策略：一句话生成 / 分阶段计划 / 任务合同 + 分层验收。
```

它能展示 Agent 对需求拆分、文件组织和完整交付的影响，但变量比 Bug 修复更多。建议复用当前 harness 的“公开项目—候选结果—独立 oracle—报告”结构，而不是重新设计一套流程。

## 10. 当前 Demo 的边界

- 固定候选补丁是教学夹具，不是模型效果数据；
- oracle 与项目位于同一 Git 仓库，只有目录隔离；测试真实 Agent 时需要沙箱或独立目录；
- fuzz-smoke 是固定随机种子的属性测试，不等价于长时间 libFuzzer/AFL++；
- macOS 上使用 ASan/UBSan，未单独启用 LeakSanitizer；
- Demo 代码很小，不能代表大型遗留项目、并发问题或复杂构建系统。

这些限制是刻意的：当前目标是把可靠流程变成一个能运行、能观察、能修改的学习工具。理解它之后，再替换为 BUGSC++、ManyBugs 或真实开源仓库会更有意义。
