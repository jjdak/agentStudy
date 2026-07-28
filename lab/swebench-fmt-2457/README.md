# fmt tuple join 中型教学 Demo

这个练习来自 SWE-bench Multilingual 的真实任务 `fmtlib__fmt-2457`。它比
`fmtlib__fmt-2310` 更大：需要理解变参模板、tuple 展开、每元素 formatter 状态、
格式规格解析和递归输出，但环境要求完全相同。

## 代码问题

范围版本的 `fmt::join` 会把外层格式规格应用到每个元素，tuple 版本却忽略规格并
抛出异常：

```cpp
std::vector<int> values{1, 2, 3};
fmt::format("{:02}", fmt::join(values, ", "));  // "01, 02, 03"

auto values2 = std::make_tuple(1, 2, 3);
fmt::format("{:02}", fmt::join(values2, ", ")); // 当前抛出 format_error
```

目标是让 tuple join 保存每种元素类型对应的 formatter，在解析阶段把相同规格传给
所有 formatter，并在输出阶段使用对应 formatter 格式化每个 tuple 元素。

## 环境

和已经跑通的 fmt-2310 一样，只需要：

```bash
sudo apt-get install build-essential curl git tar
```

不需要 Docker、CMake、Python、Autotools、Perl 或额外系统库。首次准备只下载约
800 KB 的固定 fmt 源码，之后可以离线创建多个 run。

## 完整演示

```bash
cd lab/swebench-fmt-2457
./scripts/demo.sh check
./scripts/demo.sh new demo-medium
./scripts/demo.sh test demo-medium       # 基线应有 tuple 格式化失败

codex -C "$PWD/demo-runs/demo-medium/workspace"

./scripts/demo.sh test demo-medium
./scripts/demo.sh answer demo-medium     # 查看公开参考答案
```

只演示“失败 → 应用答案 → 通过”：

```bash
./scripts/demo.sh answer demo-medium --apply
./scripts/demo.sh test demo-medium
```

任务入口是 workspace 中的 `TASK.md`。所有测试和答案均可见，本 Demo 只用于学习，
不用于模型排名。
