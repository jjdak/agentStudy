# C/C++ Coding Agent 可靠性 Demo

这个小项目用确定性候选版本和真实子 Agent 候选结果展示：为什么“公开测试通过”不等于修复可信，以及任务合同、修改边界、隐藏回归、静态分析和 Sanitizer 能增加什么证据。

它不是为了证明某个 prompt 一定让 Agent 更聪明，而是帮助你练习判断 Agent 输出是否可验证、可审计、可复盘。

## 一分钟运行

依赖：CMake/CTest、Clang、GNU GCC 和 cppcheck。

macOS 可使用：

```sh
brew install cmake gcc cppcheck
```

```sh
cd demo/cpp-agent-repair
./scripts/run_demo.sh
```

脚本支持用环境变量指定工具路径，例如：

```sh
CMAKE=/path/to/cmake CTEST=/path/to/ctest GCC=/path/to/gcc ./scripts/run_demo.sh
```

结果写入：

- `results/latest/REPORT.md`：汇总表；
- `results/latest/summary.csv`：机器可读结果；
- `results/latest/logs/<candidate>/`：每一层的命令输出和 diff。
- `results/agent_prompt_strategy_report.md`：真实子 Agent prompt 策略实验报告。

## 候选版本

| 候选 | 含义 |
|---|---|
| `buggy` | 初始仓库，公开测试可见一个逻辑错误，另外四类缺陷隐藏在不完整测试后面 |
| `strategy-a-one-shot` | 只修复公开失败的“一句话修复”示例 |
| `strategy-b-public-tests` | 会运行现有测试，也修复了部分明显问题，但仍把公开测试通过当成完成 |
| `strategy-c-reliable` | 按任务合同、根因、不变量和独立验证完成的最小正确修复 |
| `agent-*` | 真实子 Agent 在对应 prompt 策略下生成的修复结果 |

`strategy-*` 候选补丁是为保证 Demo 每次输出一致而编写的**教学夹具**，不是一次受控模型评测结果。它们证明验证流水线能区分不同质量的补丁，不证明某个模型采用某种提示词必然得到对应结果。

`agent-*` 候选来自一次真实子 Agent prompt 策略实验，完整记录见 `results/agent_prompt_strategy_report.md`。它们可以用来观察当前 Agent 在这个小任务上的实际表现，但样本量很小，不能外推成模型排行榜。更重要的是：即使多个策略最终都通过，也可以继续比较它们的根因说明、风险披露、验证诚实度和 reviewer 接管成本。

要测试真实 Agent，可以：

1. 只把 `project/` 复制到独立工作区；
2. 分别使用 `prompts/` 中的三种策略；
3. 保存 Agent 修改后的 `src/safe_ops.c`；
4. 将它放入新的 `candidates/<run-id>/src/safe_ops.c`；
5. 由独立进程运行 `scripts/run_demo.sh`。脚本会自动遍历 `candidates/*`。

不要让被测 Agent 读取 `oracle/` 或修改 `scripts/`、`results/`。本仓库的目录分离用于演示；需要更强隔离时，应把 `oracle/` 放到 Agent 沙箱之外或单独容器中。

## 缺陷类型

初始实现包含：

- 上界逻辑错误；
- 二进制复制越界；
- `size_t` 乘法/加法溢出；
- 链表节点 Use-after-free；
- 把二进制缓冲区误当 C 字符串导致的回归。

公开测试只足以暴露第一项。隐藏测试、ASan/UBSan 和确定性 fuzz-smoke 用于检查其余问题。

## Demo 关注的可靠性动作

- 候选补丁与评分器分离；
- 公开测试与隐藏验证分离；
- 修改范围检查；
- 双编译器构建；
- 静态分析；
- ASan/UBSan；
- 确定性 fuzz-smoke；
- 保存 diff、日志和汇总报告；
- 比较 Agent 的根因说明、验证边界和风险披露。

完整设计说明见 [04 文档](../../docs/04_coding_agent_reliability_experiment.md)。
