# SWE-bench C++ 可靠使用练习

这个练习使用 SWE-bench Multilingual 的真实任务 `fmtlib__fmt-2310`。目标是练习“布置任务—隔离 Agent—收集 patch—独立评分—人工复盘”，不是比较 Prompt 长短，也不是用一道题给模型排名。

## 1. 信任边界

```text
Agent 可见                         Agent 不可见
────────────────────────────      ────────────────────────────
修复前源码的干净快照              数据集中的参考 patch
固定任务文本                      test_patch 和官方评分脚本
仓库已有公开测试                  其他模型 patch 与运行轨迹
自己的命令与工具结果              .runtime/ 和 evaluation 日志
```

不要在本目录根部启动被测 Agent。只把 `runs/<run-id>/workspace/` 设为可读写工作区，并把 `task/agent_task.md` 作为任务输入。评分命令由 Agent 会话之外的人或进程执行。

## 2. 支持环境

当前脚本有意只支持：

- Linux `x86_64`；
- Python 3.11；
- Docker Engine 及可用的 Docker API；
- `curl`、`git`、`jq`、`tar`、`sha256sum`；
- 建议 16 GB 内存，并预留充足 Docker 磁盘空间。

SWE-bench 的通用文档建议为完整 benchmark 预留较多资源；本练习只拉取一个约 229 MB 压缩大小的官方任务镜像，但展开后的镜像、Python wheel 和日志仍会占用更多空间。先运行 `docker system df` 检查。

Apple Silicon 上的运行不作为标准结果。当前仓库开发机没有 Docker，因此容器执行需在 Linux 主机完成。

## 3. 联网 Linux 主机准备

```sh
cd lab/swebench-fmt-2310
./scripts/check_host.sh
./scripts/prepare_online.sh
```

`prepare_online.sh` 会：

1. 下载固定 commit 的官方 SWE-bench harness；
2. 下载固定 revision 的 Multilingual parquet，并校验 SHA-256；
3. 使用锁定依赖创建 Python 3.11 虚拟环境；
4. 按 digest 拉取官方 `linux/x86_64` 任务镜像并设置固定 tag；
5. 使用官方 gold patch 运行一次评分器自检。

Gold 自检仅用于证明评分环境能接受官方答案，保存在 `.runtime/evaluator/`。不要把该目录提供给 Agent。

## 4. 创建一次干净运行

```sh
./scripts/new_run.sh run-001
```

脚本从官方镜像导出 `/testbed`，删除原 `.git` 后重新初始化一个只有基线快照的仓库。这一步防止 Agent 从远端、tag 或 Git 历史读取原修复。

产生：

```text
runs/run-001/
├── workspace/       # 唯一交给 Agent 的目录
├── agent_task.md    # 固定任务文本，粘贴给 Agent
├── run-notes.md     # 人工记录
└── metadata.json    # 环境与固定版本
```

运行 Agent 时至少保证：

- 当前目录和可写根仅为 `workspace/`；
- 网络关闭；
- 不挂载 Docker socket、`.runtime/`、其他 run 或本仓库 `.git`；
- 使用同一模型比较时固定 Agent 版本、工具、预算和超时。

如果 Agent 需要在固定 Linux 工具链中运行公开构建或测试，不要给它 Docker socket。只允许调用这个包装器：

```sh
./scripts/run_in_toolchain.sh run-001 -- cmake -S . -B build
./scripts/run_in_toolchain.sh run-001 -- cmake --build build -j 4
```

包装器只挂载当前 run 的 `workspace/`，关闭容器网络，丢弃 Linux capabilities，并限制 CPU、内存和进程数。需要复合命令时可显式使用 `-- bash -lc '<command>'`；Agent 的工具 allowlist 仍应只开放包装器，而不是任意 `docker` 命令。

启动某一次 Agent 会话前，建议由外层执行器设置 `LAB_ALLOWED_RUN_ID=run-001`。包装器会拒绝访问其他 run；不要允许 Agent 修改或清除此变量。若所用 Agent 只能访问自己的工作区，可把包装器做成受控工具接口，由外层进程代为执行，而不要复制脚本或暴露 Docker socket。

## 5. 收集并评分

Agent 结束后，由 Agent 会话之外执行：

```sh
./scripts/collect_patch.sh run-001 internal-model-v1
./scripts/evaluate.sh run-001
```

第一条命令保存：

- `patch.diff`；
- SWE-bench 格式的 `prediction.json`；
- patch SHA-256、diff stat 和工作区状态。

第二条命令从干净官方镜像应用 patch，再运行官方问题修复测试与回归测试。最终查看：

```text
runs/run-001/evaluation/summary.json
runs/run-001/evaluation/harness-output.log
runs/run-001/evaluation/logs/
```

多次运行后可生成汇总：

```sh
./scripts/summarize_runs.sh
```

`resolved=true` 只表示该 patch 达到这一个任务的测试 oracle。仍需人工检查 diff、Agent 报告、未验证项和可能的 benchmark 污染。

## 6. 重复运行与模型比较

每次使用新的 run ID：

```sh
./scripts/new_run.sh model-a-01
./scripts/new_run.sh model-a-02
./scripts/new_run.sh model-a-03
```

不要复制上一次 workspace，不要向下一次提供旧 patch 或评分日志。同一配置至少重复 3 次观察稳定性。单题只能作为 smoke test；形成模型能力结论前需要增加多个仓库和缺陷类型。

## 7. 离线迁移到内网

在与内网服务器兼容的联网 Linux `x86_64` 主机上执行：

```sh
./scripts/export_offline_bundle.sh offline-bundles/fmt-2310
```

它会导出：

- 固定 Docker 镜像；
- 官方 harness 源码压缩包；
- 固定数据集 parquet；
- Linux/Python 3.11 wheelhouse；
- SHA-256 清单。

将整个目录按组织规定审批、扫描和传输。在内网 Linux 主机上：

```sh
./scripts/import_offline_bundle.sh /approved/path/fmt-2310
```

导入脚本先验证清单，再加载镜像并离线安装评分器。外网与内网主机应使用兼容的 `x86_64` Linux、Python 3.11 和 Docker 版本。

内网实验还应在主机或网关层阻断被测 Agent 与评分进程的非必要外联；容器中的 `--network none` 只是其中一层控制，不能代替主机侧策略。

不要为了方便把参考 patch、test patch 或评分日志复制进 Agent 可见工作区。

## 8. 结果解释

内部记录至少包含：模型和 Agent 精确版本、权限、网络状态、运行次数、patch、resolved、耗时/费用和人工复核时间。

以下结论是不成立的：

- “一次通过，所以模型已具备可靠编程能力”；
- “没有通过，所以模型完全不会 C++”；
- “输出解释更长，所以模型更可靠”；
- “公开测试通过，所以隐藏评分必然通过”；
- “两个 Agent 同意，所以修改正确”。

更合理的表述是：

> 在固定任务、容器、Agent 脚手架、权限和预算下，本次运行生成的 patch 是否达到固定测试 oracle；过程留下了哪些可复查证据，人工接管成本是多少。

任务来源与固定版本见 [基准选择记录](../../references/benchmark_selection.md)。
