# 标准练习选择记录

> 选择日期：2026-07-19

## 1. 候选基准

| 基准 | 任务形式 | 优点 | 为什么未选为当前主练习 |
|---|---|---|---|
| [LiveCodeBench](https://github.com/LiveCodeBench/LiveCodeBench) | 竞赛算法、执行、自修复 | 自动评分、题目持续更新 | 更偏独立算法实现，较少训练仓库调查和 patch review |
| [Aider Polyglot](https://github.com/Aider-AI/polyglot-benchmark) | 多语言 Exercism 难题 | C++ 支持好、运行直接 | 更偏实现指定函数，不是完整真实 issue 修复 |
| [Terminal-Bench 2.0](https://github.com/laude-institute/terminal-bench) | 终端中的端到端任务 | 真实工具使用、任务困难 | 任务领域过宽，当前学习主线只需要 Coding Agent |
| [SWE-bench Multilingual](https://www.swebench.com/multilingual.html) | 多语言真实 GitHub issue | 仓库级调查、patch、问题修复与回归测试 | 选用 |

## 2. 选定任务

```text
dataset: SWE-bench/SWE-bench_Multilingual
instance_id: fmtlib__fmt-2310
repository: fmtlib/fmt
base_commit: 7612f18dc8e0112e64e0845a1ebe9da6cfb8a123
created_at: 2021-05-23
FAIL_TO_PASS: 2
PASS_TO_PASS: 102
```

原始 issue 描述的是：数值零填充错误地作用于 infinity 和 NaN。标准任务要求 Agent 在修复前仓库中理解格式化实现并生成 patch。

## 3. 难度依据

SWE-bench 官方 [experiments 仓库](https://github.com/SWE-bench/experiments/tree/main/evaluation/multilingual) 保存公开提交的逐任务结果。对 2026-02-13 至 2026-02-20 发布的 13 组 `mini-v2.0` 模型/Agent 结果进行统计，`fmtlib__fmt-2310` 仅有 2 组标记为 `resolved=true`。

这里的“困难”只表示在这 13 个公开设置中通过率低。它不等于经过人工标注的绝对难度，也不能推出其他模型的成功概率。不同模型、Agent 脚手架、预算和权限会影响结果。

## 4. 固定版本

| 组件 | 固定值 |
|---|---|
| SWE-bench harness commit | `f7bbbb2ccdf479001d6467c9e34af59e44a840f9` |
| harness archive SHA-256 | `b36fe073d6057c20c714a09d2d05265ed658319f4bcf2c874037ac8cc0420c82` |
| Multilingual dataset revision | `2b7aced941b4873e9cad3e76abbae93f481d1beb` |
| dataset parquet SHA-256 | `28b7f874e48496399077d276f9f2b163a077ddf0a70dc507c148d58da826baa9` |
| 官方镜像 | `swebench/sweb.eval.x86_64.fmtlib_1776_fmt-2310:latest` |
| 镜像 digest | `sha256:39db2c6407c51739050f7c7985042f95e927bad455f69605e2306d430ccc9c62` |
| Python | 3.11 |
| 目标平台 | Linux x86_64 |

固定 tag 之外还校验 digest，避免 `latest` 漂移。Python 依赖保存在练习目录的 `requirements.lock`。

## 5. 许可与使用边界

- [`fmtlib/fmt` LICENSE](https://github.com/fmtlib/fmt/blob/main/LICENSE) 为 MIT 风格许可；
- [SWE-bench LICENSE](https://github.com/SWE-bench/SWE-bench/blob/main/LICENSE) 为 MIT License；
- 数据集卡标注 MIT；
- 迁移到内网前仍需遵守组织对开源代码、镜像、许可证文本和介质传输的审批要求。

本仓库不提交上游源码、官方镜像、参考 patch 或测试 patch，只保存任务标识、固定版本和运行脚本。

## 6. 有效性边界

1. 任务和修复已经公开，模型可能在训练中见过；
2. SWE-bench 测试 oracle 可能遗漏未测试行为；
3. 单题结果不能代表整体 Coding Agent 能力；
4. 官方镜像包含原仓库 Git 数据，因此导出给 Agent 时必须移除 `.git` 并重新初始化干净基线；
5. 评分数据和日志必须放在 Agent 不可访问的位置；
6. 内部正式评测应逐步扩展多个仓库、缺陷类型和重复运行。
