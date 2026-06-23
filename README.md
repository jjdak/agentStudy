# LLM 幻觉培训材料

这是一组面向软件工程师的内部培训材料，用来解释大语言模型为什么会产生幻觉、先进模型如何降低幻觉，以及在日常研发辅助中如何降低幻觉带来的影响。

> 使用边界：材料中的案例均为通用或虚构内容，不包含公司源码、日志、接口、芯片型号、芯片结构、客户问题或内部架构。

## 推荐阅读顺序

1. [01_hallucination_principles.md](./01_hallucination_principles.md)

   主题：幻觉的产生原因和原理。

   适合讲：

   - LLM 为什么会把错误内容说得很流畅；
   - GPT-2 / Transformer / next-token prediction；
   - attention、softmax、temperature、采样；
   - 数据缺口、训练目标、评测激励、上下文缺失；
   - 为什么“看起来合理”不等于“事实正确”。

2. [02_model_mitigation_strategies.md](./02_model_mitigation_strategies.md)

   主题：先进模型和 agent 系统如何降低幻觉。

   适合讲：

   - GPT-2 到 ChatGPT、GPT-4、GPT-5.5 的演进；
   - Claude Opus 4.8 的 honesty / uncertainty / pushback；
   - GLM-5.2 和 DeepSeek-V4-Pro 的长上下文、推理 effort、开放部署；
   - Claude Code、Codex、OpenClaw 这类 agent 如何通过工具反馈降低一部分幻觉；
   - 哪些结论有公开资料支持，哪些属于工程机制推断。

3. [03_practical_playbook.md](./03_practical_playbook.md)

   主题：使用中如何降低幻觉影响。

   适合讲：

   - 外部 AI 工具的使用边界；
   - 软件研发中的低/中/高风险任务分类；
   - 如何组织上下文、写提示词、要求模型列假设；
   - 如何用编译、测试、lint、官方文档和人工 review 验证；
   - agent 工具的验收规范；
   - 现场练习和检查清单。

## 建议培训结构

如果只有 60～90 分钟，可以按下面节奏：

| 时间 | 内容 | 对应文档 |
|---:|---|---|
| 10 分钟 | AI 能做什么、不能做什么 | README + 03 |
| 20 分钟 | 幻觉原理：GPT-2 动画和 next-token prediction | 01 |
| 20 分钟 | 先进模型和 agent 如何降低幻觉 | 02 |
| 20 分钟 | 脱敏材料现场练习：脚本、调度器、测试 | 03 |
| 10 分钟 | 安全规范与讨论 | 03 |

## 对同事最重要的三句话

1. 幻觉不是模型“故意撒谎”，而是概率生成、数据缺口、奖励机制、上下文不足和验证缺失共同造成的。
2. 先进模型降低幻觉靠的是系统工程：更好的数据、后训练、推理、工具、检索、评测、监控，而不是某个单一魔法开关。
3. 软件工程里最可靠的反幻觉方法是：脱敏输入、明确假设、要求证据、运行验证、人工 review。

## 文件维护建议

- 需要补充公式、Transformer 动画、论文细节时，优先改 `01_hallucination_principles.md`。
- 需要补充某个新模型或 agent 工具时，优先改 `02_model_mitigation_strategies.md`。
- 需要补充内部使用规范、提示词模板、现场练习时，优先改 `03_practical_playbook.md`。
