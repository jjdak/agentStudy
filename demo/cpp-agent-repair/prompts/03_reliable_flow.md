# 策略 C：可靠流程

```text
目标：修复 safe_ops 库中的缺陷，只允许修改 src/safe_ops.c。

先只读分析并列出候选根因、影响范围和验证计划，再进行最小修改。

完成标准：
1. GCC 和 Clang 都能以 -Wall -Wextra -Wpedantic -Werror 构建；
2. 公开 CTest 全部通过；
3. 不把二进制数据当作 NUL 结尾字符串；
4. 所有 size_t 乘法和加法在计算前检查溢出；
5. 删除链表节点时不存在 Use-after-free、double-free 或泄漏；
6. AddressSanitizer、UndefinedBehaviorSanitizer、隐藏回归和 fuzz-smoke 由独立验证脚本运行；
7. 不修改测试、CMake、验证器或其他路径。

禁止通过跳过测试、关闭 Sanitizer、吞掉错误或硬编码样例获得通过。

最终报告必须列出：修改文件、根因到修复的映射、实际运行命令、退出码、未运行检查和剩余风险。验证失败时不得宣称完成。
```

特点：把目标、范围、根因、不变量、独立验证和完成声明绑定起来。
