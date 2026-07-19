# 参考资料

主学习路线只保留稳定概念和可执行方法。本目录用于查证依据和继续深入，资料最后核对日期为 **2026-07-19**。

## 语言模型与幻觉

- Vaswani et al., [Attention Is All You Need](https://arxiv.org/abs/1706.03762)：Transformer 与 attention；
- Radford et al., [Language Models are Unsupervised Multitask Learners](https://cdn.openai.com/better-language-models/language_models_are_unsupervised_multitask_learners.pdf)：GPT-2；
- Ouyang et al., [Training language models to follow instructions with human feedback](https://arxiv.org/abs/2203.02155)：InstructGPT、SFT 与 RLHF；
- Lin et al., [TruthfulQA](https://aclanthology.org/2022.acl-long.229/)：模型可能模仿人类常见错误；
- Manakul et al., [SelfCheckGPT](https://aclanthology.org/2023.emnlp-main.557/)：使用多次采样检查一致性；
- Dhuliawala et al., [Chain-of-Verification](https://arxiv.org/abs/2309.11495)：先生成再设计验证问题；
- Gao et al., [Retrieval-Augmented Generation for Large Language Models: A Survey](https://arxiv.org/abs/2312.10997)：RAG 的方法与局限。

## Agent 定义与工程方法

- Yao et al., [ReAct](https://arxiv.org/abs/2210.03629)：推理、行动和观察循环；
- Anthropic, [Building effective agents](https://www.anthropic.com/engineering/building-effective-agents)：工作流与 Agent、从简单系统开始；
- OpenAI, [A practical guide to building agents](https://openai.com/business/guides-and-resources/a-practical-guide-to-building-ai-agents/)：模型、工具、指令与编排；
- NIST, [AI RMF Generative AI Profile, NIST AI 600-1](https://doi.org/10.6028/NIST.AI.600-1)：治理、测量、来源、监控和事件管理；
- OWASP, [Agentic AI Threats and Mitigations](https://genai.owasp.org/)：提示注入、工具滥用、权限和身份风险。

## Coding Agent 与验证

- GitHub, [Responsible use of Copilot coding agent](https://docs.github.com/en/copilot/responsible-use/agents)：人工 review、测试和产品边界；
- NIST, [Secure Software Development Framework SP 800-218](https://csrc.nist.gov/pubs/sp/800/218/final)：安全开发和软件完整性；
- LLVM, [AddressSanitizer](https://clang.llvm.org/docs/AddressSanitizer.html)：内存错误动态检测；
- LLVM, [UndefinedBehaviorSanitizer](https://clang.llvm.org/docs/UndefinedBehaviorSanitizer.html)：未定义行为检测；
- Google, [Fuzzing with libFuzzer](https://llvm.org/docs/LibFuzzer.html)：覆盖引导模糊测试；
- Jimenez et al., [SWE-bench](https://openreview.net/forum?id=VTF8yNQM66)：真实 GitHub issue 修复基准；
- SWE-bench, [Evaluation guide](https://www.swebench.com/SWE-bench/guides/evaluation/)：官方 patch 评分流程；
- SWE-bench, [Docker setup](https://www.swebench.com/SWE-bench/guides/docker_setup/)：容器层次、资源与缓存。

## 如何阅读模型发布说明

模型能力、版本、价格和工具权限变化很快。学习时不要维护一张永远过时的“谁的幻觉最低”表，而应按下面的方法阅读最新官方资料：

1. 记录模型全名、版本、发布日期和访问日期；
2. 区分预训练、后训练、推理预算、检索、工具和系统安全机制；
3. 查清 benchmark 测量的是事实问答、代码生成还是 Agent 长任务；
4. 不把厂商在某个数据集上的提升外推为所有场景的通用幻觉率；
5. 检查评测是否有污染、隐藏测试、重复采样和成本限制；
6. 将“官方明确声明”“研究结果”“工程经验”和“自己的推断”分开记录；
7. 最终仍使用自己的公开或授权任务做小规模 eval。

模型升级会改变错误概率，不会改变基本责任边界：参数知识不是实时事实库，模型自述不是独立证据，外部操作需要权限和人工批准。
