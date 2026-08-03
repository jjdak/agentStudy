# OpenCode 代码理解轻量对比评测

这个目录用于比较相同 OpenCode 工作流下的公司内网模型和外部 API 模型。它不需要
Docker、GPU 工具链或额外 Python 包，只依赖 Bash、Python 3 和已经配置好的
OpenCode。

首轮包含 120 次独立请求：

| 题库 | 子集 | 请求数 | 目的 |
|---|---|---:|---|
| SWE-QA | Oracle | 30 | 给定相关代码时的跨实体理解 |
| SWE-QA | Noisy Oracle | 30 | 加入干扰代码后的理解稳定性 |
| CodeMMLU | code completion | 10 | 代码补全理解 |
| CodeMMLU | code repair | 10 | 缺陷定位和修复判断 |
| CodeMMLU | execution prediction | 10 | 执行结果判断 |
| CRUXEval | output prediction | 30 | Python 程序执行语义 |

SWE-QA 的两个子集使用同一批 30 个问题，可以直接统计 Oracle 正确、加入噪声后
错误的题目数量。CRUXEval 只使用输出预测，避免执行模型生成的任意代码，也避免
输入预测存在多个有效答案时产生误判。

## 运行前检查

确认模型标识能被当前 OpenCode 识别：

```bash
opencode --version
opencode models
```

本次已知模型标识：

- 公司内网：`local/Qwen3-Coder`
- 外网：`deepseek/deepseek-v4-flash`

## 一键运行

公司内网：

```bash
./run_eval.sh --label company-qwen --model local/Qwen3-Coder
```

外网：

```bash
./run_eval.sh \
  --label deepseek-v4-flash-0731 \
  --model deepseek/deepseek-v4-flash
```

脚本先执行一次不计分的 `opencode run` 预热，再逐题执行新的 `opencode run`。
这样排除已观测到的约 60 秒首次模型或连接冷启动，同时不会把上一题的对话历史
带入下一题。预热后的后续直接调用已实测只需要几秒启动时间。

默认单题超时 600 秒，失败后重试一次。可调整：

```bash
./run_eval.sh --label company-qwen --model local/Qwen3-Coder \
  --timeout 900 --retries 2
```

`opencode run --attach` 在 OpenCode 1.1.x 和部分新版本中存在已知的批处理会话错误，
正式评测不使用它。只有确认目标版本已修复时才实验性启用：

```bash
./run_eval.sh --label company-qwen --model local/Qwen3-Coder \
  --use-serve

# 或连接已有服务
./run_eval.sh --label company-qwen --model local/Qwen3-Coder \
  --use-serve --attach-url http://127.0.0.1:4096
```

## 中断后继续

结果会在每题完成后立即写盘。找到未完成目录后执行：

```bash
./run_eval.sh --label company-qwen --model local/Qwen3-Coder \
  --resume results/20260802-120000-company-qwen
```

恢复时会校验题库 SHA-256、模型标识和标签，已经保存的题目不会重复请求。恢复运行
仍会执行一次不计分预热。

## 结果文件

每次运行会生成：

```text
results/<时间>-<标签>/
├── manifest.json          # 模型、OpenCode、题库哈希和预热信息
├── responses.jsonl        # 逐题结构化结果和完整回答文本
├── answers.csv            # 方便用表格查看
├── summary.json           # 总体、题库、子集和 SWE-QA 成对统计
├── raw/                   # OpenCode 原始 JSON 事件和 stderr
├── server.log             # 仅实验性 --use-serve 模式生成
├── opencode-version.txt
└── model-list.txt
```

打包：

```bash
./pack_results.sh results/<时间>-<标签>
```

会生成 `.tar.gz` 和对应 `.sha256`。将公司 Qwen 与外部 DeepSeek 的两个压缩包交给
分析人员即可复核判分、检查格式错误和生成最终报告。

## 公平性与限制

- 两端使用相同题目、题序、提示词和 OpenCode 调用方式。
- 每题是新会话；首次预热时间单独记录，不计入题目延迟。
- 提示词禁止工具、文件、Shell、Web 和其他 Agent；若原始事件中出现工具事件，
  该题标为 `tool_contaminated`。
- 选择题必须以 `FINAL_ANSWER: A` 等格式结尾；不能解析时标为
  `format_error`，不会猜测答案。
- CRUXEval 使用空白差异归一化后的精确答案比较，不执行模型输出。
- OpenCode CLI 没有统一的跨 provider temperature 参数。本轮测量的是各模型在
  公司实际 OpenCode provider 配置下的效果，而不是底层推理引擎的严格同参数实验。
- 内外网硬件和服务不同，因此延迟只作运行画像，模型替换结论应以正确率、错误类型
  和稳定性为主。

## 开发烟雾测试

只跑前 3 题用于确认接口，不应作为模型结论：

```bash
./run_eval.sh --label smoke --model local/Qwen3-Coder --limit 3
```

`--limit` 会写入 manifest，正式评测不要使用。
