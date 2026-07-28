# 中型 Demo 任务：让 `fmt::join(tuple)` 支持格式规格

这是基于真实任务 `fmtlib__fmt-2457` 的教学练习。当前仓库是 fmt 修复该问题之前
的干净源码快照。

## 问题描述

使用 `fmt::join` 格式化范围时，外层格式规格会应用到每个元素：

```cpp
std::vector<int> values{1, 2, 3};
fmt::format("{:02}", fmt::join(values, ", "));  // "01, 02, 03"
```

对 tuple 执行相同操作却会抛出 `format_error`：

```cpp
auto values = std::make_tuple(1, 2, 3);
fmt::format("{:02}", fmt::join(values, ", "));  // 当前失败
```

## 目标行为

1. tuple join 的格式规格应分别应用到 tuple 的每个元素。
2. tuple 可以包含不同类型，每个元素必须使用其自身类型的 formatter。
3. 不带格式规格的现有 tuple join 行为必须保持不变。
4. 空 tuple 必须继续安全地产生空输出。
5. 如果同一规格不能被所有元素 formatter 一致解析，应抛出清晰的
   `format_error`，不能产生未定义行为。
6. 范围版本的 `fmt::join` 不能回归。

## 建议流程

1. 修改前运行可见测试，分别观察范围和 tuple 的行为。
2. 找到 `tuple_join_view` 对应的 formatter，并与范围版本比较。
3. 画出“规格解析”和“逐元素输出”两个阶段的数据流。
4. 为不同 tuple 元素类型保存独立 formatter 状态。
5. 处理空 tuple、异构 tuple 和解析结果不一致等边界。
6. 运行可见测试并检查最小差异。

本 Demo 不设置隐藏测试或隔离要求。可以通过 Lab 的
`scripts/demo.sh answer` 命令查看完整公开参考答案。
