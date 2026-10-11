# opencode-workflow-kit

> 把 [opencode](https://github.com/opencode-ai/opencode) 打造成生产级编码 agent 的 **工作流套件**：安全护栏、语义记忆、工具纪律、集群审计、UI 复刻 —— 全是可组合的小碎片。

个人技能总仓：[opencode-personal-skills](https://github.com/Yulimfish/opencode-personal-skills) 汇总 18 个个人原创 skill 原件，并为 32 个非原创技能提供原始链接；全局 Agent 契约单独存放于 [`AGENTS.md`](./AGENTS.md)。

一行安装脚本会拉一组精心挑选的插件 + 技能，装完之后你会得到：

- 🛡  **Guardrails 护栏** —— 硬拦 `rm -rf /`、fork bomb、`curl \| sh`；对 `git push --force`、`drop database`、`sudo` 弹提示；前端文件上自动带 UI 预览提醒。
- 🧠 **Memory 记忆** —— 通过 [`@yulimfish/opencode-mem`](https://github.com/Yulimfish/opencode-mem) 提供的语义长时记忆：Paper & Ink WebUI、暂存与证据链、混合注入检索；向量由阿里云百炼 MaaS（`qwen3.7-text-embedding`，1024 维）直接生成。
- 🎯 **Discipline 纪律** —— 五条硬规则，阻止 agent 在 30 行分片重读、串行化本该并行的调用、shell 工具乱选上浪费轮次。
- 🔎 **Tool Search 动态工具加载** —— 参考 Kimi K3 的 tool-search 模式；把 MCP 等噪声工具的描述折叠成 stub，模型按需 `tool_search("...")` 揭示，命中的工具本 session 永久可见。省 token、聚焦注意力。
- 🖼  **UI-preview-first** —— 任何会移动 DOM 的改动前，先给 ASCII wireframe。
- 🌙 **Memory Dream** —— 睡眠隐喻的碎片巩固：五阶段（Doze → Cluster → Consolidate → NREM 衰减评分 → REM 清理），支持「清理 / 遗忘」快路径。
- 🧬 **Memory Evolution** —— P0-P2 的报告-only Dream agent、暂存/证据链补丁、混合注入检索与回滚资产；不上传个人记忆数据。
- ❓ **Clarify-before-act** —— 分支决策前一条消息拿到确认。
- 🕸  **Swarm Cluster** —— 主 Agent 遇到复杂任务时自主拆解，并行 spawn 2-4 个 subagent（默认继承主模型；要指定模型就自建 `agents/swarm-worker-<name>.md`），最后汇总。
- 🔍 **Post-Task Audit** —— 任务完成后派出零上下文污染的 subagent 独立核查（默认审计员 `goal-verify`），必要时多维度并行开审（功能 / 合规 / 安全 / 意图对齐）。
- ⚖️ **Execution Economy** —— 按风险分级（Level 1/2/3）决定检查 / 验证 / 审计的强度，平衡安全、效果与速度：最终目标优先、最小充分验证、不重复验证已知事实、窄范围命令即安全、失败驱动复杂度、环境绕过优先、连续执行不打断。
- 🖼️ **Screenshot-to-UI** —— 给张参考图（截图 / Figma 导出 / 手绘稿 / URL），走 5 阶段流水线（analyze → HTML plan → styled build → visual diff → iterate）做像素级 1:1 复刻。
- 🗼 **Tower Workflow** —— 独立的模型档位协作流程：总控路由、高能力与轻量 Agent、Spec/Plan/Build/Review 闭环；模型由 OpenChamber 绑定。

## 内容清单

| 仓库 | 角色 | 安装 |
| --- | --- | --- |
| [`opencode-personal-skills`](https://github.com/Yulimfish/opencode-personal-skills) | 个人技能唯一来源 · 18 个原创原件 + 32 个外部来源链接 | 安装器复制精选的 10 个 |
| [`opencode-guardrails`](https://github.com/Yulimfish/opencode-guardrails) | 插件 · 安全 | `npm i opencode-guardrails` |
| [`@yulimfish/opencode-tool-search`](https://github.com/Yulimfish/opencode-tool-search) | 插件 · 动态工具加载 | `npm i @yulimfish/opencode-tool-search` |
| [`@yulimfish/opencode-mem`](https://github.com/Yulimfish/opencode-mem) | 插件 · Paper & Ink 记忆 fork | git-based npm install |
| [`opencode-memory-evolution`](https://github.com/Yulimfish/opencode-memory-evolution) | 记忆系统进化资产 · Dream / P1 / P2 | git clone |
| [`opencode-swarm-agents`](https://github.com/Yulimfish/opencode-swarm-agents) | Agent 集 · worker + synth + auditor | git clone → agents/ |
| [`opencode-tower-workflow`](https://github.com/Yulimfish/opencode-tower-workflow) | Agent 集 · Tower controller + high/light tiers | git clone → agents/ |

## 一行安装

```bash
curl -fsSL https://raw.githubusercontent.com/Yulimfish/opencode-workflow-kit/main/install.sh | bash
```

脚本会：

1. 检查前置（git、npm、curl）。
2. 从个人技能总仓复制 10 个精选 skill 到 `~/.config/opencode/skills/`（Agent bundles 单独安装，不计入此数）。
3. 安装 `opencode-memory-evolution` 的 report-only Dream agent、`dreamctl` 和报告模板（不触碰数据库）。
4. 把 `opencode-swarm-agents` 和 `opencode-tower-workflow` clone 出来，将 agent md 文件复制到 `~/.config/opencode/agents/`（装完需要重启一次 opencode 让 Task 白名单识别）。
5. 把插件和 `@yulimfish/opencode-mem` fork 安装到 `~/.config/opencode/`。
6. 打印你需要粘到 `opencode.jsonc` / `opencode-mem.jsonc` 的确切片段。

**全流程幂等** —— 反复跑没关系。

## 手动安装

想自己一步一步来：

```bash
# 插件（含固定的 Paper & Ink 记忆 fork）
npm install opencode-guardrails @yulimfish/opencode-tool-search \
  "github:Yulimfish/opencode-mem"

# 精选个人技能
mkdir -p ~/.config/opencode/skills
skill_tmp=$(mktemp -d)
git clone --depth=1 https://github.com/Yulimfish/opencode-personal-skills.git "$skill_tmp/catalog"
for s in clarify-before-act ui-preview-first long-term-memory \
         memory-graph-ui tool-call-discipline memory-dream \
         swarm-cluster post-task-audit execution-economy screenshot-to-ui; do
  cp -R "$skill_tmp/catalog/$s" "$HOME/.config/opencode/skills/$s"
done
rm -rf "$skill_tmp"

# Agent bundle：worker + synth + 审计员的 md 定义（可选，供 swarm-cluster / post-task-audit 用）
mkdir -p ~/.config/opencode/agents
git clone --depth=1 https://github.com/Yulimfish/opencode-swarm-agents.git /tmp/swarm-agents \
  && cp /tmp/swarm-agents/agents/*.md ~/.config/opencode/agents/ \
  && rm -rf /tmp/swarm-agents

# Tower Agent bundle：controller + high/light capability tiers
git clone --depth=1 https://github.com/Yulimfish/opencode-tower-workflow.git /tmp/opencode-tower-workflow \
  && cp /tmp/opencode-tower-workflow/agents/*.md ~/.config/opencode/agents/ \
  && rm -rf /tmp/opencode-tower-workflow

# Memory Evolution：报告-only Dream + 本地只读接口
git clone --depth=1 https://github.com/Yulimfish/opencode-memory-evolution.git /tmp/opencode-memory-evolution \
  && cp /tmp/opencode-memory-evolution/agents/memory-dream.md ~/.config/opencode/agents/ \
  && mkdir -p ~/.config/opencode/memory/bin ~/.config/opencode/memory/dream \
  && cp /tmp/opencode-memory-evolution/bin/dreamctl ~/.config/opencode/memory/bin/ \
  && chmod +x ~/.config/opencode/memory/bin/dreamctl \
  && cp /tmp/opencode-memory-evolution/templates/dream/TEMPLATE.md ~/.config/opencode/memory/dream/ \
  && rm -rf /tmp/opencode-memory-evolution
```

然后编辑 `~/.config/opencode/opencode.jsonc`：

```jsonc
{
  "plugin": [
    "opencode-guardrails",
    "@yulimfish/opencode-tool-search",
    "./node_modules/@yulimfish/opencode-mem/dist/plugin.js"
  ]
}
```

再编辑 `~/.config/opencode/opencode-mem.jsonc`，接上 embedding 后端：

```jsonc
{
  "embeddingApiUrl": "https://<your-endpoint>.cn-beijing.maas.aliyuncs.com/compatible-mode/v1",
  "embeddingApiKey": "<YOUR_API_KEY>",
  "embeddingModel": "qwen3.7-text-embedding",
  "embeddingDimensions": 1024
}
```

## 一屏截图看到的东西

```
$ opencode
[guardrails] armed — 9 hard rules, 10 prompt rules, UI hint active
[opencode-mem] loaded 42 memories, profile v3
> 你好

Recalled 2 relevant memories （依据 memory mem_… · 2026-07-15）
…
```

试试：

```
> rm -rf ~/*
[guardrails] refused: rm -rf ~ …
```

## 设计目标

1. **可组合。** 插件和 Agent bundles 各自独立；个人技能集中收录、按需安装。
2. **零魔法。** ~180 行的 guardrails、纯 markdown 的技能。装之前先读源码。
3. **可挽回。** 破坏性动作要么被拦要么弹提示，事件全部落日志。
4. **快。** 技能懒加载，插件小体量；记忆检索按需触发（一次 embedding ~200–300ms）。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/Yulimfish/opencode-workflow-kit/main/uninstall.sh | bash
```

手动卸载不推荐：安装器会记录它实际创建的文件，只删除内容未被修改的自有文件，并保留用户已有或改过的 skill/agent。无论哪种方式，都不会删除 Dream 报告、数据库或备份。

## 许可

MIT © Yulimfish
