# 01. LLM 幻觉的产生原因与原理

> 适用场景：软件部门内部 AI 培训
> 目标听众：普通软件工程师，包含少量 Transformer 技术点
> 建议时长：20～30 分钟
> 使用边界：本文只讨论公开原理和通用例子，不涉及公司源码、日志、芯片结构或内部架构。

## 1. 本文目标

读完这一部分，听众应该能够回答三个问题：

1. 什么是 LLM 幻觉？
2. 为什么 next-token prediction 天然可能生成“看似合理但不真实”的内容？
3. 为什么幻觉只能降低，不能靠提示词或模型升级彻底消灭？

## 2. 什么是 LLM 幻觉

LLM 幻觉通常指：模型生成了缺乏依据、与事实不符、与给定材料矛盾，或者无法由现有信息推出的内容，却把它表达得像可信答案。

软件研发中常见表现包括：

- 编造不存在的 API、类、命令、参数或第三方包；
- 混用不同版本的软件接口；
- 声称引用了某份标准或文档，但章节并不存在；
- 根据有限日志直接断言唯一根因；
- 生成无法编译、存在资源泄漏或并发问题的代码；
- 声称“测试已经通过”，但实际上没有执行测试；
- 忽略用户给出的约束，自己补充一个看似合理但未经确认的条件。

可以进一步区分几类风险：

| 类型 | 含义 | 示例 |
|---|---|---|
| 事实性幻觉 | 陈述了错误或不存在的事实 | 编造 `std::scheduler` |
| 上下文幻觉 | 与用户材料或约束矛盾 | 要求 C++17，却使用 C++20 接口 |
| 推理错误 | 已知信息正确，但推导过程错误 | 错误计算结构体对齐后的大小 |
| 信息缺失 | 没覆盖关键边界条件 | 调度器未处理任务取消后的资源释放 |
| 需求误解 | 对模糊需求作了错误假设 | 把“超时”理解成执行前超时，而非执行中超时 |

培训时可以先用一句话建立直觉：

> LLM 最危险的地方不一定是说出明显荒谬的话，而是把错误答案说得流畅、完整、专业。

## 3. 从 GPT-2 动画开始讲：模型到底在做什么

推荐用下面三个可视化材料：

- [Transformer Explainer](https://poloclub.github.io/transformer-explainer/)：浏览器里运行 GPT-2 small，可以演示 token、embedding、attention、temperature、top-k、top-p。
- [The Illustrated GPT-2](https://jalammar.github.io/illustrated-gpt2/)：静态图适合讲 decoder-only Transformer、自回归生成、masked self-attention。
- [LLM Visualization](https://bbycroft.net/llm)：适合展示模型内部层级和向量流动的直观感觉。

### 3.1 动画讲法

可以按这个节奏讲 8～10 分钟：

1. 输入一句话：`Data visualization empowers users to`
2. 展示 tokenization：一句话被切成 token。
3. 展示 embedding：每个 token 变成向量。
4. 展示 masked self-attention：每个 token 只能看左侧上下文，不能偷看未来。
5. 展示 logits / softmax：模型输出的是下一个 token 的概率分布。
6. 拖动 temperature / top-k / top-p：让大家看到“更确定”和“更发散”的差异。
7. 点出关键：模型本质上不是在查事实库，而是在概率空间里续写。

一句适合收尾的话：

> GPT-2 像一个超级强的文本/代码补全器；现代 ChatGPT、Claude、GLM、DeepSeek 则是在这个核心生成机制外面叠加了指令训练、推理、工具、检索、评测和安全策略。

## 4. 从文字到 token

模型不会直接理解完整句子。输入首先会被切分成 token。Token 可能是一个词、词的一部分、符号或一段常见字符。

代码也会被 token 化，例如类型名、标识符、括号、运算符都会成为模型处理的序列元素。模型看到的是 token 之间的统计关系，而不是编译器拥有的抽象语法树、类型系统和执行语义。

设输入经过分词后得到序列：

```math
x_1,x_2,\ldots,x_n
```

每个 token ID 会通过嵌入矩阵映射为向量，再加入位置信息：

```math
h_i^{(0)}=E[x_i]+P_i
```

其中，`E[x_i]` 是 token embedding，`P_i` 是位置编码或位置嵌入。

对软件工程师来说，这带来两个结果：

1. 相似名称和代码模式在表示空间中可能接近，所以模型擅长模仿 API 风格。
2. Token 序列并不自带编译器语义，所以“形式像正确代码”不等于类型、生命周期、并发行为正确。

## 5. Transformer 和 self-attention

Transformer 的核心机制之一是 self-attention。它允许模型在处理当前 token 时，根据上下文判断其他 token 的相关程度。

对于某一层输入矩阵 `X`，模型通过训练得到的参数矩阵产生 Query、Key、Value：

```math
Q=XW_Q,\qquad K=XW_K,\qquad V=XW_V
```

缩放点积注意力的核心公式是：

```math
\operatorname{Attention}(Q,K,V)
=\operatorname{softmax}\left(\frac{QK^T}{\sqrt{d_k}}+M\right)V
```

其中：

- `QK^T` 衡量当前位置与其他位置的匹配程度；
- `sqrt(d_k)` 用于缩放，避免点积过大导致 softmax 过度饱和；
- `M` 是掩码。自回归模型使用因果掩码，使当前位置不能看到未来 token；
- softmax 将分数转换为归一化权重；
- 最后乘以 `V`，得到融合上下文后的表示。

多头注意力可以简化表示为：

```math
\operatorname{MultiHead}(Q,K,V)
=\operatorname{Concat}(\operatorname{head}_1,\ldots,\operatorname{head}_h)W_O
```

不同 head 可能关注不同关系，例如局部语法、变量引用、函数调用风格、长距离依赖等。

## 6. 自回归生成：一个 token 接一个 token

GPT-2 这类 decoder-only 模型的生成过程可以简化为：

```text
给定前文 x_1, x_2, ..., x_t，预测下一个 token x_{t+1}
```

训练目标是最大化真实文本序列概率：

```math
P(x_1,x_2,\ldots,x_T)=\prod_{t=1}^{T}P(x_t\mid x_{<t})
```

对应损失函数通常是负对数似然：

```math
\mathcal{L}=-\sum_{t=1}^{T}\log P_\theta(x_t\mid x_{<t})
```

这套目标带来一个关键后果：

> 模型被训练成“给出最像训练语料的续写”，而不是“只输出可验证事实”。

所以当上下文不足、训练数据稀疏、问题含糊、用户要求不存在的东西，或者采样温度较高时，模型仍然会继续生成看起来合理的 token。

## 7. softmax、temperature 与“自信地编”

模型最后会输出每个候选 token 的 logit。Softmax 把 logit 转成概率：

```math
P(x_{t+1}=i\mid x_{\le t})
=\frac{\exp(z_i/T)}{\sum_j\exp(z_j/T)}
```

其中 `T` 是 temperature：

- `T < 1`：分布更尖锐，输出更确定；
- `T = 1`：保持原始分布；
- `T > 1`：分布更平，输出更发散。

这解释了一个常见现象：

- 降低 temperature 可以减少随机性，但不能保证事实正确；
- 提高 temperature 可以增加创意，但也可能增加幻觉；
- 即使 temperature 很低，如果最高概率候选本身就是错的，模型仍然会稳定地产生错误。

## 8. 幻觉产生的主要原因

### 8.1 训练目标不是事实验证

语言建模训练的是“预测下一个 token”，不是“证明这个 token 对应的事实为真”。

模型可以学到很多事实，但这些事实是通过文本统计关系内化到参数中的，不等于一个可查询、可更新、可审计的事实数据库。

### 8.2 训练数据有噪声、冲突和过时信息

训练数据来自大量公开文本，里面天然包含：

- 过时文档；
- 错误教程；
- 复制粘贴的 bug；
- 版本不一致的 API；
- 未注明上下文的经验总结；
- 互相矛盾的资料。

模型会学习这些分布。当问题落在噪声区域或冲突区域时，它可能生成一个流畅但错误的折中答案。

### 8.3 参数知识不能实时更新

模型参数中的知识来自训练阶段。对新版本 API、新法规、新论文、新漏洞、新工具链，如果没有联网检索或外部资料，模型很可能凭旧知识回答。

### 8.4 上下文缺失导致“补洞”

如果用户没有提供版本、约束、边界条件、运行环境，模型会根据常见模式自动补齐。

例如只说“写一个调度器”，模型可能默认：

- 单线程；
- 任务不可取消；
- deadline 是软约束；
- priority 越大越优先；
- 不考虑时钟漂移；
- 不考虑任务执行失败。

这些假设不一定错，但如果没有标注出来，就会变成幻觉风险。

### 8.5 奖励机制可能鼓励猜测

OpenAI 研究论文 [Why Language Models Hallucinate](https://arxiv.org/abs/2509.04664) 提出一个重要观点：很多训练和评测流程奖励“猜答案”，却不奖励“承认不确定”。

这很像考试：

- 答对得分；
- 答错扣分；
- 空着也不得分。

在这种制度下，模型会学会“不会也猜”。要降低这类幻觉，需要让评测和训练也奖励恰当的不确定性表达。

### 8.6 生成过程会让错误滚雪球

模型一旦先生成了错误结论，后续 token 会围绕这个结论继续展开，形成自洽但错误的解释。

论文 [How Language Model Hallucinations Can Snowball](https://arxiv.org/abs/2305.13534) 讨论了这种现象：模型可能在后续解释中继续为早先错误“找理由”，让错误越来越完整。

### 8.7 语言流畅性会掩盖事实不确定性

LLM 的强项是生成自然、连贯、符合风格的语言。可读性、专业术语、结构完整，都会让人误以为内容可信。

这对软件工程尤其危险：代码片段、错误日志分析、性能解释、论文引用都可能看起来“专业”，但未经验证。

## 9. 软件研发中的典型幻觉案例

### 9.1 编造 API

```text
请用 C++ 写一个跨平台定时任务调度器。
```

模型可能编造一个不存在的标准库 API，或者混用不同库版本的接口。

降低方式：

- 指定语言标准和依赖版本；
- 要求引用官方文档；
- 要求给出可编译最小例子；
- 本地编译验证。

### 9.2 编造包名

模型可能建议安装不存在的 npm/PyPI 包。代码生成场景中，这不仅是准确性问题，还可能带来供应链风险。

降低方式：

- 查询官方 registry；
- 锁定依赖；
- 不允许模型随意引入第三方包；
- 对新依赖做人工 review。

### 9.3 根因过度断言

```text
这个错误日志说明是什么问题？
```

模型可能把“可能原因”说成“唯一原因”。

降低方式：

- 要求列出多个候选假设；
- 要求说明证据和反证；
- 要求给出下一步验证命令；
- 不允许在证据不足时下结论。

## 10. 小结

LLM 幻觉不是单一 bug，而是由生成目标、数据分布、上下文缺失、采样机制、奖励激励和验证缺失共同造成的。

最重要的认识是：

> LLM 的默认能力是“生成合理文本”，不是“保证事实正确”。事实可靠性需要额外系统工程来约束。

## 11. 参考资料

- [Attention Is All You Need](https://arxiv.org/abs/1706.03762)
- [The Illustrated GPT-2](https://jalammar.github.io/illustrated-gpt2/)
- [Transformer Explainer](https://poloclub.github.io/transformer-explainer/)
- [GPT-4 Technical Report](https://arxiv.org/abs/2303.08774)
- [Why Language Models Hallucinate](https://arxiv.org/abs/2509.04664)
- [How Language Model Hallucinations Can Snowball](https://arxiv.org/abs/2305.13534)
- [Language Models (Mostly) Know What They Know](https://arxiv.org/abs/2207.05221)
- [HaluEval](https://arxiv.org/abs/2305.11747)
