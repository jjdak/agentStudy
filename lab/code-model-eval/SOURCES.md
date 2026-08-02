# 数据来源与固定版本

题库生成种子：`20260802`

## SWE-QA

- 项目：https://lailanelkoussy.github.io/swe-qa/
- 数据：https://huggingface.co/datasets/lailaelkoussy/swe-qa
- Hugging Face revision：`579a8e1220c46742213998a36ccbb26c8bd26468`
- GitHub commit：`9fa0595ad52c0b2ae8ec4a52b042e2d13b1a142a`
- 许可证：Apache-2.0（数据卡声明）
- 引用：ElKoussy and Perez, *SWE-QA: A Dataset and Benchmark for Complex Code Understanding*, LREC-COLING 2026.

抽样限制：Oracle 与 Noisy Oracle 按仓库、类别、问题和实体严格配对；两类问题各
15 个；单仓库最多 3 个；Oracle 代码不超过 24,000 字符，Noisy Oracle 不超过
48,000 字符。

## CodeMMLU

- 项目：https://fsoft-ai4code.github.io/codemmlu/
- 代码：https://github.com/FSoft-AI4Code/CodeMMLU
- 数据：https://huggingface.co/datasets/Fsoft-AIC/CodeMMLU
- Hugging Face revision：`f7c1221269df3609eb5c3023770126839e24e608`
- GitHub commit：`2999a6a888734a9dc48cc84d8a77a8311e9ca245`
- 许可证：MIT
- 引用：Nguyen et al., *CodeMMLU: A Multi-Task Benchmark for Assessing Code Understanding Capabilities*, ICLR 2025.

固定输入快照 SHA-256：

- code completion：`7424a83c6675c0e6f52796e3fcd2993ba81f3b6f1ada82e527719b1d649e6676`
- code repair：`a39ca08951feef20aca8d23932f07e85cc850e3e45986c343db67a61d8796ecc`
- execution prediction：`a9633c0b8a7f28973fe093786590aad47e72654bbe0669de833ef479d09ebaa2`

每个子集从固定接口返回的前 100 条四选一题中，使用固定种子选择 10 条，并限制
单个答案字母最多出现 3 次。

## CRUXEval

- 代码与数据：https://github.com/facebookresearch/cruxeval
- GitHub commit：`190faf16d175b5847b0af05d937872b1fb395942`
- 许可证：MIT
- 引用：Gu et al., *CRUXEval: A Benchmark for Code Reasoning, Understanding and Execution Evaluation*, 2024.

从 800 条公开样本中用固定种子选择 30 条，只运行 output prediction。

## 当前评测文件

`data/questions.jsonl`：120 行，SHA-256
`245c4d950832dca38c9ac5a0846ecb03debe71336e5bc3f71f966a98e7c0603c`。
