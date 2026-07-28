# Coding Agent 教学 Demo

这里提供一小一大两个真实开源任务。默认路径直接使用宿主机工具，不需要 Docker、
Bubblewrap、Python 评测框架或严格沙箱；测试和参考答案都是可见的。

| Demo | 规模 | 主要练习 | 宿主要求 | 典型时间 |
|---|---:|---|---|---:|
| [fmt 小型修复](swebench-fmt-2310/README.md) | 约 2 个核心文件 | 复现、定位、最小修复、回归 | `c++`、Git、curl、tar | 15～40 分钟 |
| [curl 大型功能](curl-variable-long-task/README.md) | 参考实现约 32 个文件 | 仓库地图、规格、分包、状态外置、跨会话恢复 | C 工具链、Autotools、Perl | 2～8 小时 |

## 小型 Demo

```bash
cd lab/swebench-fmt-2310
./scripts/demo.sh new demo-small
./scripts/demo.sh test demo-small
codex -C "$PWD/demo-runs/demo-small/workspace"
```

修复前测试会显示 `00+nan` 与期望值不符。完成后再次运行测试。需要提示时：

```bash
./scripts/demo.sh answer demo-small
```

## 大型 Demo

```bash
cd lab/curl-variable-long-task
./scripts/demo.sh new demo-large
./scripts/demo.sh test demo-large
codex -C "$PWD/demo-runs/demo-large/workspace"
```

workspace 内的 `TASK.md` 是任务入口，`.agent/` 中的文件用于保存规格、设计、
工作包和进度。查看或应用公开上游答案：

```bash
./scripts/demo.sh answer demo-large --show
./scripts/demo.sh answer demo-large --apply
```

## 统一命令

两个 Lab 都提供相同的基本接口：

```text
demo.sh check                   检查普通宿主依赖
demo.sh prepare                 下载并校验固定源码/答案
demo.sh new RUN_ID              创建新的干净 workspace
demo.sh test RUN_ID             宿主机编译并运行可见检查
demo.sh answer RUN_ID --show    查看公开参考答案
demo.sh answer RUN_ID --apply   把答案应用到该 Demo run
```

Demo 模式不试图阻止 Agent 读取父目录、联网或查看答案。若要研究盲测、固定工具链、
隐藏评分和权限边界，再进入各 Lab README 后半部分的进阶模式。
