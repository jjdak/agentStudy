# curl 长任务实验室：从需求到跨模块实现

这个实验室用于练习一个单 Agent 在大型 C 仓库中持续工作的完整过程，而不是比较“哪一段 Prompt 更聪明”。任务从修复局部 Bug 升级为实现 curl 的命令行变量与参数展开功能，可信参考实现涉及 32 个文件、约 1800 行增删，覆盖参数解析、内存所有权、构建文件、文档和测试。

实验回答三个问题：

1. Agent 能否先建立仓库地图和规格，再跨模块完成实现？
2. 外部状态文件能否减少长会话中的遗忘、重复探索和半成品声明？
3. Agent 自己运行过的公开检查，与独立评分器得到的结果是否一致？

这不是当前模型能力的通用排行榜。任务及历史实现是公开资料，可能存在训练污染；一次通过也只表示满足本实验的 oracle。

## 1. 固定对象与评分边界

| 项目 | 固定值 |
|---|---|
| 上游仓库 | [curl/curl](https://github.com/curl/curl) |
| 修复前源码 | `47a3e6e577b019b8dfce8d3f8df764a8dd427fd2` |
| 可信参考实现 | [curl/curl@2e160c9](https://github.com/curl/curl/commit/2e160c9c652504e147f474ed920ae891481e299c) |
| 任务主题 | command line variables，最初合入 curl 8.3.0 |
| 平台 | Linux x86_64 + Bubblewrap（内网推荐），或 Docker Linux containers |
| 编译 | GCC，Autotools + CMake，ASan + UBSan，静态 curl |
| 必须通过 | 构建、15 项外部黑盒检查、10 项上游隐藏测试、8 项既有回归测试 |
| 可选门禁 | curl 完整回归测试 |

源码包、参考 patch 和 Debian 基础镜像都在 [`config.env`](config.env) 中以 commit 或 digest 和 SHA-256 固定。在线准备完成后，实际安装的 Debian 包版本、工具链 image ID、便携 rootfs 及其 SHA-256 都会被保存。`apt` 仓库会变化，因此“第一次在线构建之前”并非逐字节可重现；导出的已验证 Docker 镜像或便携 rootfs 才是内外网比较的固定工具链。

验证记录和每个 run 的元数据还会保存 `config.env` SHA-256、CPU/内存/进程
限制以及构建/测试超时。修改其中任一固定参数都会让旧的验证状态失效，必须重新
运行正负控制。

评分器不接受 Agent 自己的测试作为通过依据：候选 patch 中对 `tests/` 的修改会被记录，然后从可信基线恢复测试，再叠加隔离的隐藏测试。外部黑盒脚本、隐藏测试、参考 patch、评分脚本和评分日志都不放进 Agent 工作区。

## 2. 运行后端与 Codex 的网络关系

`LAB_RUNTIME=auto` 在 Linux x86_64 且已经导入便携 rootfs 时优先选择
Bubblewrap；否则使用可用的 Docker Linux engine。Bubblewrap 不需要 daemon、
root、`sudo`、`/etc/subuid` 或 `/etc/subgid`，但宿主必须允许非特权 user
namespace。Docker 后端仍用于联网制包、macOS 开发和需要严格 cgroup 资源上限的运行。

网络分成两层：

```text
Codex / 其他 Agent 进程 ──联网──> 云端模型 API
             │
             └──受控工具包装器──> Docker 或 Bubblewrap（无网络 namespace）
                                      └──只挂载固定 rootfs 和本次 workspace

独立评分进程 ──> 新建干净源码树 + 候选 patch + 隐藏 oracle
```

“离线容器”不等于“Codex 模型离线”。使用云端 Codex 时，Agent 进程仍需访问模型服务；只有编译、搜索源码和测试命令断网。真正的全离线环境还需要内网模型端点及兼容的 Agent 客户端，这不是本实验室替你提供的部分。

## 3. 第一次在线准备

在 WSL 的 Linux 文件系统中克隆仓库，例如 `~/work/agentStudy`，不要放在 `/mnt/c`，否则大型 C 仓库的文件 I/O 和权限语义通常更差。

```bash
cd ~/work/agentStudy/lab/curl-variable-long-task
./scripts/bootstrap_host.sh
docker info
./scripts/prepare_online.sh
```

`bootstrap_host.sh` 在 Linux x86_64 上验证现有运行后端；在 macOS 上通过
Homebrew 补齐 Colima、Docker CLI、GNU coreutils 和 `jq`，并启动带 Rosetta
支持的 Linux VM。Apple Silicon 上评分容器仍固定为 `linux/amd64`，但编译速度、
文件挂载和总耗时不可与原生 Linux x86_64 直接比较。必须保留宿主平台信息，
并以本节的正负控制是否全部通过作为该环境可用的依据。

准备脚本会执行：

1. 检查受支持的宿主、Docker Linux engine 和宿主命令；
2. 下载并校验固定源码包和可信参考 patch；
3. 构建固定工具链镜像并记录 image ID、包版本；
4. 从参考 patch 中提取隐藏测试；
5. 运行两个强制控制实验：
   - 未修改基线必须“构建成功但功能评分失败”；
   - 可信参考 patch 必须通过所有必选门禁。

任一控制不满足，脚本不会生成 `.runtime/evaluator/VERIFIED.json`，也不能创建正式 run。这一设计防止在验证器本身失效时继续得到看似漂亮的模型结果。

## 4. 创建可恢复的新 run

每次都从同一源码快照创建新目录，不在旧工作区执行 `git reset`：

```bash
./scripts/new_run.sh codex-01
```

生成内容：

```text
runs/codex-01/
├── metadata.json             # 固定输入、runtime/toolchain ID、prompt hash、Git tree
├── run-notes.md              # 人工记录时间、模型和干预
├── process-report.md         # 可公开的命令、决策、失败和恢复记录
├── result-report.md          # 定量结果与跨会话过程复盘
└── workspace/                # 唯一交给 Agent 的目录
    ├── .agent/TASK.md        # 自包含任务合同
    ├── .agent/REPO_MAP.md    # 仓库地图
    ├── .agent/SPEC.md        # 可核对规格
    ├── .agent/DESIGN.md      # 跨模块设计
    ├── .agent/TASKS.md       # 工作包和完成证据
    └── .agent/STATUS.md      # 恢复/交接状态
```

给 Agent 的首条指令可以很短：

```text
阅读 .agent/TASK.md 并按其中工作合同完成任务。先更新仓库地图、规格、设计和
工作包，再开始实现。所有 shell 命令必须通过实验提供的受控 toolchain wrapper
执行。遇到上下文压缩或需要新会话前先更新 .agent/STATUS.md。
```

受控命令入口：

```bash
./scripts/run_in_toolchain.sh codex-01 bash -lc 'git status --short'
./scripts/run_in_toolchain.sh codex-01 bash
```

实际使用 Codex、Claude Code 或其他 Agent 时，应把 wrapper 配置成它唯一可用的 shell 入口，并把 Agent 的工作目录限定到本次 `workspace`。如果 Agent 仍可任意读取实验仓库父目录、调用原始 Docker socket、访问 Web/GitHub 或查看其他 run，那么“隐藏测试隔离”只是一项文字约定，该次结果应标记为无效。当前脚本提供的是可审计的工具隔离基础，不声称能防御一个已经取得同用户宿主机任意读权限的恶意进程。

## 5. 收集和独立评分

先填写 `run-notes.md` 的模型、Agent 版本、预算和人工干预，再收集 patch：

```bash
./scripts/collect_patch.sh codex-01 "codex-cli + exact-model-id"
./scripts/evaluate.sh codex-01
```

需要把完整 curl 回归也作为本次硬门禁时：

```bash
./scripts/evaluate.sh codex-01 --full
```

评分总是从新的可信源码树应用 patch，不复用 Agent 的 build 目录。两个后端都使用无网络 namespace、只读根文件系统并丢弃 capabilities。Docker 额外用 cgroup 限制 CPU、内存和进程数；Bubblewrap 用 `prlimit` 限制派生进程数，但不能在所有无特权宿主上强制相同的 CPU/内存 cgroup 上限，因此不同后端的性能和资源耗尽行为不能直接比较。每个阶段有独立日志和退出码：

```text
runs/codex-01/evaluation/
├── 01-patch.log
├── 02-build.log
├── 03-black-box.log
├── 04-hidden-tests.log
├── 05-regression-tests.log
├── 06-full-regression.log     # 仅 --full
├── summary.json
└── artifacts.sha256           # 日志和摘要的完整性清单
```

`resolved=true` 要求 patch 可应用、Sanitizer 构建、黑盒、隐藏测试和选定回归全部通过；指定 `--full` 时还要求完整回归通过。最后汇总多次运行：

```bash
./scripts/summarize_runs.sh
```

同一个模型至少重复 3 次，固定首条指令、Agent 版本、权限、预算、runtime 和 toolchain ID。除 `resolved` 外，还应比较总耗时、调用/费用、人工干预、状态文件质量、重复探索次数和独立评分与 Agent 自报结果的差异。

要把模型解决过程与结果提交到本仓库，先填写 `run-notes.md`、
`process-report.md` 和 `result-report.md`，再生成经过筛选的可发布目录：

```bash
./scripts/publish_run.sh codex-01
```

默认输出到 `reports/codex-01/`，包含候选 patch、状态文档、公开构建/测试日志、
评分摘要和 SHA-256 清单；不会复制隐藏测试文件或原始隐藏测试日志。它记录可观察
的命令、决策、失败和恢复证据，不导出模型的私有推理链或未经审查的聊天记录。
提交前仍需人工检查凭据、内网地址、用户名和其他敏感信息。

## 6. 无 Docker 的便携离线迁移

联网制包机在 Docker 控制实验通过后生成并导出便携 rootfs：

```bash
./scripts/prepare_portable_runtime.sh
./scripts/export_portable_bundle.sh ~/curl-variable-portable
```

把整个 `agentStudy` 仓库和 bundle 传到内网 Linux x86_64。目标机只需
Bash、GNU `timeout`、`tar`、`gzip`、常见 coreutils/findutils/util-linux
命令和可用的非特权 user namespace；
`git` 和 `jq` 会从便携 rootfs 暴露为用户态工具，
不需要 Docker、Podman、root 或网络：

```bash
cd ~/work/agentStudy/lab/curl-variable-long-task
./scripts/import_portable_bundle.sh ~/curl-variable-portable
```

导入脚本会校验每个文件，解压固定 rootfs，使用 rootfs 自带的 Bubblewrap
创建隔离环境，并在目标机重新跑正负控制。以下检查可在传包前由目标用户执行：

```bash
./scripts/check_portable_host.sh
```

输出 `portable host check: PASS` 才表示宿主命令与内核允许所需的非特权
user/network namespace。Bubblewrap 是低层沙箱，
隔离强度取决于本仓库构造的参数；不要把未知、不可信的 rootfs 替换进 bundle。

## 7. Docker 离线迁移与重新开始

联网 WSL 在通过控制实验后导出：

```bash
./scripts/export_offline_bundle.sh ~/curl-variable-bundle
```

把整个 `agentStudy` 仓库和 bundle 目录传到内网 WSL/Linux。内网无需访问 GitHub 或软件源：

```bash
cd ~/work/agentStudy/lab/curl-variable-long-task
./scripts/import_offline_bundle.sh ~/curl-variable-bundle
```

导入会重新校验 bundle、加载镜像，并在目标机器再次运行正负控制。这条路径要求目标机已经拥有可用的 Docker daemon。模型是否可用仍取决于内网是否允许访问云端 API，或是否已经配置内网模型服务。

要恢复初始状态，不要删除或覆盖旧 run；创建新 ID：

```bash
./scripts/new_run.sh codex-02
```

这样旧 patch、日志和人工记录仍可追溯，新 run 又拥有完全相同的基线。

## 8. 已知限制

- 公开任务可能被模型记忆，适合练流程和做接入 smoke test，不适合单独给模型排名。
- 隐藏测试与黑盒 oracle 只能覆盖已编码行为，不能证明不存在所有回归或安全问题。
- ASan/UBSan 只覆盖本次实际运行的路径；`--full` 仍不是形式化验证。
- Docker/Bubblewrap 隔离控制的是命令执行面；模型请求、Agent 客户端和宿主文件权限必须单独配置。
- Bubblewrap 后端不保证与 Docker 相同的 CPU/内存 cgroup 上限；跨后端只比较功能门禁，不比较耗时和资源峰值。
- 工具链资源上限、超时和选定回归是实验参数。比较模型时必须保持一致并记录。
- 独立评分证明 patch 达到本实验的技术门禁，最终代码质量、可维护性和真实需求仍需人工 review。

curl 源码和参考 patch 依据 curl license 使用，见 [`licenses/curl-LICENSE`](licenses/curl-LICENSE) 和 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
