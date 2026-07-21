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
| 平台 | Linux/WSL2 x86_64 + Docker Linux containers |
| 编译 | GCC，Autotools + CMake，ASan + UBSan，静态 curl |
| 必须通过 | 构建、15 项外部黑盒检查、10 项上游隐藏测试、8 项既有回归测试 |
| 可选门禁 | curl 完整回归测试 |

源码包、参考 patch 和 Debian 基础镜像都在 [`config.env`](config.env) 中以 commit 或 digest 和 SHA-256 固定。在线准备完成后，实际安装的 Debian 包版本、工具链 image ID 和镜像本身也会被保存；从此可以导出到离线机器复用。`apt` 仓库会变化，因此“第一次在线构建之前”并非逐字节可重现，导出的已验证镜像才是内外网比较的固定工具链。

评分器不接受 Agent 自己的测试作为通过依据：候选 patch 中对 `tests/` 的修改会被记录，然后从可信基线恢复测试，再叠加隔离的隐藏测试。外部黑盒脚本、隐藏测试、参考 patch、评分脚本和评分日志都不放进 Agent 工作区。

## 2. WSL、Docker 与 Codex 的网络关系

推荐 Windows 使用 **WSL2 + Docker Desktop 的 WSL integration**。在 WSL 中执行的是 Linux `docker` CLI，容器由 Docker Desktop 的 Linux engine 运行，不需要在 WSL 里再嵌套一个虚拟机或 Docker-in-Docker。也可以直接在 WSL 安装 Docker Engine，但不要同时混用两个 daemon。

网络分成两层：

```text
Codex / 其他 Agent 进程 ──联网──> 云端模型 API
             │
             └──受控工具包装器──> Docker 容器（--network none）
                                      └──只挂载本次 run/workspace

独立评分进程 ──> 新建干净源码树 + 候选 patch + 隐藏 oracle
```

“离线容器”不等于“Codex 模型离线”。使用云端 Codex 时，Agent 进程仍需访问模型服务；只有编译、搜索源码和测试命令断网。真正的全离线环境还需要内网模型端点及兼容的 Agent 客户端，这不是本实验室替你提供的部分。

## 3. 第一次在线准备

在 WSL 的 Linux 文件系统中克隆仓库，例如 `~/work/agentStudy`，不要放在 `/mnt/c`，否则大型 C 仓库的文件 I/O 和权限语义通常更差。

```bash
cd ~/work/agentStudy/lab/curl-variable-long-task
docker info
./scripts/prepare_online.sh
```

准备脚本会执行：

1. 检查 Linux x86_64、Docker 和宿主命令；
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
├── metadata.json             # 固定输入、image ID、prompt hash、Git tree
├── run-notes.md              # 人工记录时间、模型和干预
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

容器命令入口：

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

评分总是从新的可信源码树应用 patch，不复用 Agent 的 build 目录。容器无网络、只读根文件系统、丢弃 capabilities，并限制 CPU、内存和进程数。每个阶段有独立日志和退出码：

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

同一个模型至少重复 3 次，固定首条指令、Agent 版本、权限、预算和 image ID。除 `resolved` 外，还应比较总耗时、调用/费用、人工干预、状态文件质量、重复探索次数和独立评分与 Agent 自报结果的差异。

## 6. 离线迁移与重新开始

联网 WSL 在通过控制实验后导出：

```bash
./scripts/export_offline_bundle.sh ~/curl-variable-bundle
```

把整个 `agentStudy` 仓库和 bundle 目录传到内网 WSL/Linux。内网无需访问 GitHub 或软件源：

```bash
cd ~/work/agentStudy/lab/curl-variable-long-task
./scripts/import_offline_bundle.sh ~/curl-variable-bundle
```

导入会重新校验 bundle、加载镜像，并在目标机器再次运行正负控制。模型是否可用仍取决于内网是否允许访问云端 API，或是否已经配置内网模型服务。

要恢复初始状态，不要删除或覆盖旧 run；创建新 ID：

```bash
./scripts/new_run.sh codex-02
```

这样旧 patch、日志和人工记录仍可追溯，新 run 又拥有完全相同的基线。

## 7. 已知限制

- 公开任务可能被模型记忆，适合练流程和做接入 smoke test，不适合单独给模型排名。
- 隐藏测试与黑盒 oracle 只能覆盖已编码行为，不能证明不存在所有回归或安全问题。
- ASan/UBSan 只覆盖本次实际运行的路径；`--full` 仍不是形式化验证。
- Docker 隔离控制的是命令执行面；模型请求、Agent 客户端和宿主文件权限必须单独配置。
- 工具链资源上限、超时和选定回归是实验参数。比较模型时必须保持一致并记录。
- 独立评分证明 patch 达到本实验的技术门禁，最终代码质量、可维护性和真实需求仍需人工 review。

curl 源码和参考 patch 依据 curl license 使用，见 [`licenses/curl-LICENSE`](licenses/curl-LICENSE) 和 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
