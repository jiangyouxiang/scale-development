---
name: scale-development
description: 面向社会科学量表（问卷）开发的人机协作流程。封装 AIGENIE R 包的 UVA/EGA/bootEGA 心理测量验证管线，用多 LLM 智能体（策略师/出题者/审查者/整合者）替换其单模型生成层。适用于：确定构念维度结构（文献/访谈/直接输入/三角验证四条路径）、生成候选题项、对用户确认的完整候选题池做 in-silico 语义筛查与内部削减。当用户需要开发量表、编制问卷、生成或精简测量题项、做构念维度分析时触发。
---

# 社科量表开发 Skill

本 Skill 使用 **「多 LLM 角色协同生成 + AIGENIE 心理测量验证」** 双层架构，
封装 **AIGENIE R 包**（Russell-Lasalandra et al., 2026, *Generative Psychometrics
via AI-GENIE*）的 UVA/EGA/bootEGA 算法进行验证，但用**多智能体生成层**替换其
单模型自适应循环。

架构说明：
- **生成层**：4 个 LLM 角色（策略师→出题者→审查者→整合者）协同工作，
  全过程记录为可读的 `generation_session_log.md`
- **验证层**：`GENIE()` 函数接受已有的题项数据框，跑嵌入→稀疏化→UVA→
  EGA→bootEGA 管线（与 AIGENIE 原版同样的心理测量算法）

详细设计见 `reference/multi-agent-generation.md`。

## 这个 Skill 解决什么

传统量表开发（构念界定 → 题目草拟 → 专家评审 → 试测 → 心测分析 → 修订）耗时数月。
AIGENIE 的验证管线用 **in-silico 网络心理测量**（**语义层筛查，非应答层面的结构效度**）
把它压缩到天级。
本 Skill 的价值：用多智能体生成解决单模型生成的多样性不足和缺乏审查问题，
同时保留 AIGENIE 独有的心理测量验证能力。


## 核心工作原则：交互式确认（重要）

本 Skill 是**人机协作**流程，不是一键黑箱。每个关键决策点，**必须暂停，向用户
说明可选项、推荐项及理由，等用户确认后再继续**。

### 决策门交互形式：弹出选择题优先

遇到任何 ⛔ 决策门时，**优先使用 Codex 当前可用的弹出选择题 / choice UI / `request_user_input`
类工具**，让用户直接点击选项，而不是要求用户在聊天窗口手动输入长文本。执行规则：

- 每次弹出只解决**一个决策**，选项保持互斥；通常给 2–3 个选项，并标明推荐项与理由。
- 若当前运行环境没有弹出选择题能力，才允许用编号选项兜底；兜底时也只要求用户回复选项编号。
- 不得把多个独立决策合并成一个问题；不得在用户未选择前继续进入下游步骤。
- 用户选择与理由必须写入对应产物（如 `dimension_structure_report.md`、`construct_template.json`、
  `generation_session_log.md` 或 `validation_config.json`）。

关键决策门（遇到即暂停询问）：

1. **结构确定路径** —— 文献驱动 / 访谈驱动 / 直接输入 / 三角验证（见第 1 步）
2. **维度结构确认（硬门禁）** —— 路径 A/B/D 必须产出学术论文式
   `dimension_structure_report.md` 与 `dimension_structure_report.docx`；路径 C 回显整理后的结构；
   用户未明确确认绝不进入下一步
3. **生成模式选择（硬门禁）** —— 真多智能体协同 / 单智能体角色模拟 / 已有题池仅验证；
   **没有用户明确选择，不得进入策略师阶段；不可默认单智能体替代多智能体**
4. **生成策略确认** —— 策略师产出生成计划后，展示给用户，确认后再执行出题
5. **完整题池确认** —— 一轮内容优化和复核后，展示完整候选题池的总量与维度配额；确认的是完整题池，不是预先生成的简版
6. **嵌入来源选择** —— OpenAI / Jina / Hugging Face / 本地模型 / 预计算 embedding / skip（见第 5 步）

反向题不作为常规决策门主动询问；默认 `reverse_items.include=false`、全正向生成。只有当用户明确要求反向题、反向计分或 negatively worded items 时，才先提示高风险并记录设置。

## ⚠️ 方法学边界（务必先读）

本 Skill 的生成层产出的是**经多智能体内容优化后、等待进入语义筛查的完整候选题池**；GENIE/local_GENIE 的验证层随后可能进行语义去冗余，**但整个流程不是"已验证的成熟量表"**：

- **in-silico ≠ 应答结构效度**：验证层建网于**题项文本嵌入的语义相似度**，不是被试应答的
  协方差。产出是"题项内容的语义一致性 / 冗余筛查"，**不替代**真实样本上的 EGA/CFA、信度、
  测量不变性与专家内容效度。
- **三重越界**：原论文的主要生成与验证证据来自**英文 + 已知结构构念 + 无反向题候选池**；
  本 Skill 常用于 **①中文 ②访谈扎根的探索性结构 ③用户明确要求反向题**——三者均超出论文实证包络。
  论文并未断言“反向题必然导致 bug”，但也未验证反向题题池；因此本 Skill 默认不编制反向题，若用户坚持使用，必须提示高风险并做人工复核。
- **NMI 是循环指标**：高 NMI 不等于构念效度（详见边界文档）。

> 完整边界说明见 `reference/methodological-boundaries.md`——**汇报任何"验证"结论前先读它**。

## 架构总览

```
┌────────────────────────────────────────────────────┐
│                   您（领域专家）                      │
│   ┌───── 四条结构路径 ─────┐                        │
│   │ A 文献 │ B 访谈 │ C 直输│ D 三角 │              │
│   └──────────┬─────────────┘                        │
│              ▼  ⛔维度确认                          │
│     construct_template.json                         │
│              ▼                                      │
├────────────────────────────────────────────────────┤
│          多智能体生成层（本 Skill 核心）              │
│                                                    │
│  策略师 → ⛔计划确认 → 出题者：完整候选题池            │
│                              ↓                       │
│              审查者第一轮审查                        │
│                              ↓                       │
│              出题者固定一轮优化                       │
│                              ↓                       │
│              审查者复核 → 整合者                      │
│                              ↓                       │
│              ⛔完整题池确认 → generated_items.csv     │
│                                                    │
├────────────────────────────────────────────────────┤
│          AIGENIE 验证层（GENIE R 包）                │
│                                                    │
│  GENIE(items=..., embedding.model=...)               │
│  嵌入 → 稀疏化 → UVA → EGA → bootEGA               │
│                                                    │
└────────────────────────────────────────────────────┘
```

## AIGENIE 验证层参考

详细参数与默认值见 `reference/aigenie-pipeline.md`。关键入口函数：

| 函数 | 用途 | 是否生成题目 |
|------|------|-------------|
| `AIGENIE()` | 全流程（本 Skill 不使用其生成层） | 是（但被多智能体层替代） |
| `GENIE()` | **只做验证削减**（本 Skill 使用这个） | 否——接受已有题项数据框 |

## 端到端流程（人机协作，9 步）

### 第 1 步：确定测评结构（⛔ 先与用户确认走哪条路径）

量表的维度结构有四条确定路径，**先用弹出选择题问用户选哪条**（可组合）：

| 路径 | 适用场景 | 维度结构论证报告（交付物） |
|------|----------|----------------------------|
| **A 文献驱动** | 有成熟理论 / 已有量表可循 | `dimension_structure_report.md` + `dimension_structure_report.docx`；可附 `literature_review.md` |
| **B 访谈驱动** | 探索性构念，需自下而上 | `dimension_structure_report.md` + `dimension_structure_report.docx`；可附 `interview_analysis.md` |
| **C 直接输入** | 已有明确结构 | 回显整理后的结构；必要时写 `structure_confirmation.md` |
| **D 文献+访谈三角验证** | 两条证据链互证 | `dimension_structure_report.md` + `dimension_structure_report.docx`；正文含三角对比 |

- **A 文献驱动**：用 WebSearch / `deep-research` skill 系统检索构念的定义、理论框架、
  已有量表的因子结构 → 产出学术论文式**维度结构论证报告**，正文必须有引文、参考文献、
  竞争模型比较、证据表与推荐维度结构。
- **B 访谈驱动**：用户提供访谈逐字稿 → 开放式编码 → 主轴编码 → 选择性编码（扎根理论式）
  → 产出学术论文式**维度结构论证报告**，正文必须包含方法、编码证据、代表性引语与局限。
- **C 直接输入**：引导用户给出构念名 / 定义 / 各维度 + 属性 → 质检（维度互斥、每维 ≥2
  唯一属性）→ ⛔ 回显整理后的结构请用户确认；若用户要求正式留档，也可转换为 `.docx`。
- **D 文献+访谈三角验证**：同时走 A 和 B，合并为一份学术论文式报告，对两份证据源进行**三角对比**
  → 标注 🔵/🟢/🟠/🔴 四种情况 → 合成最终推荐结构。

> ⛔ **硬门禁：路径 A/B/D 必须先完成 `dimension_structure_report.md` 和
> `dimension_structure_report.docx`，并通过用户确认，才允许进入第 2 步。**
> 路径 C 同样需要回显确认。

报告写法见 `reference/dimension-structure-report.md`；四条路径的详细方法见
`reference/structure-determination.md`。Markdown 转 Word 可用 `scripts/md_to_docx.py`。

### 第 2 步：补全构念定义模板

把确认后的结构落到 `construct_template.json`（见 `assets/construct_template.json`）。

必填字段：
- `construct_name` 构念名
- `definition` 操作化定义（含边界条件）
- `theoretical_framework` 理论框架
- `dimensions[]` 维度（= AIGENIE 的 item type = 多智能体生成的 type），每个维度含：
  - `name` 维度名
  - `description` 维度描述
  - `attributes[]` 该维度的属性（≥2 个唯一值；题量由 `item_count_per_dimension` 在维度层控制，再由生成计划分配到属性）
  - `sample_items[]` 参考题项（可选）
- `target_population` 目标人群
- `response_format` 作答格式（如 "Likert 5 点"）
- `item_count_per_dimension` 每维题量（建议 ≥60 才有意义的削减）
- `language` 语言（`zh-CN` / `en`）

规范与社科常见构念示例见 `reference/construct-definition.md`。

### 第 3 步：准备运行目录与基础环境

本 Skill 的脚本路径均以 **Skill 根目录** 为基准。执行本 Skill 时，先切到 Skill 根目录（安装后用实际安装路径替换示例路径）：

```powershell
Set-Location <skill-root>
# 示例：Set-Location "$env:CODEX_HOME\skills\scale-development"
```

首次使用可先做基础检查（此时还没有 provider 配置，只检查基础 R 包并提示下一步）：

```powershell
Rscript .\scripts\setup_check.R
```

缺失项按脚本提示修复。通常需要：

```r
install.packages(c("reticulate","ggplot2","igraph","patchwork","jsonlite","EGAnet","remotes"))
install.packages("AIGENIE", repos = "https://laralee.r-universe.dev")
library(AIGENIE); ensure_aigenie_python()
```

> 仅选择 `skip` 暂缓验证时，生成的 `run_genie.R` 不加载 `AIGENIE` / `EGAnet`；但若后续要真正运行 `GENIE()`，仍必须完成上述依赖。

### 第 4 步：生成模式选择与题项生成（核心）

这是本 Skill 替换 AIGENIE 生成层的步骤——用多个 LLM 角色协同生成题项，
而非 AIGENIE 原版的单模型自适应循环。

#### 4.0 ⛔ 生成模式决策门（不可跳过）

开始生成前，必须把“生成模式选择”作为第一个动作；即使用户已经确认维度、题量或反向题，也不得跳过本门。必须用弹出选择题让用户选择生成模式：

1. **真多智能体协同（推荐）**：使用 Codex 子代理/多代理能力，让策略师、出题者、审查者、
   整合者分别工作并交叉检查；最能体现本 Skill 的核心特点。
2. **单智能体角色模拟（显式兜底）**：仅在用户追求速度、当前环境没有子代理能力，或用户明确选择时使用；
   仍需按四角色顺序写出可审计产物。
3. **已有题池仅验证**：用户已提供题项，跳过生成层，直接进入 embedding provider 与 GENIE 验证。

**禁止行为**：不得因为方便而直接默认单智能体多流程；不得把“我可以在同一回复中模拟四个角色”视为用户已选择 B；不得因用户催促“继续”而跳过本门。若用户选择真多智能体但当前 Codex 环境没有可用子代理，应再次弹出选择题询问「改用单智能体角色模拟 / 暂停等待可用环境 / 改为已有题池验证」。最终选择必须写入 `generation_session_log.md` 的“生成模式”字段，并记录 `generation_mode`、`subagents_used`、`mode_decision_source`、`fallback_reason`。

具体编排见 `reference/multi-agent-generation.md`。

#### 4.1 反向题默认规则 + 策略师制定生成计划

**反向题默认规则**：不主动询问是否包含反向题；默认 `reverse_items.include=false`，按全正向题生成。只有当用户明确提出“反向题 / 反向计分 / negatively worded items”时，才先提示：源论文未验证反向题题池，反向题在 embedding→UVA/EGA/bootEGA 管线中可能造成正/反题冗余删除、方法因子伪结构或运行异常；本 Skill 不建议编制反向题。若用户仍要求使用，将设置写入 `construct_template.json` 的 `reverse_items` 字段和 `generation_session_log.md`。

按用户已选择的生成模式调用**策略师（Strategist）**：
- 输入：构念 JSON（含默认或用户明确要求的 `reverse_items` 设置）+ 语言/人群信息
- 输出：《题项生成计划》（每个维度的题项侧重、属性分布、默认全正向题；仅当用户明确要求反向题时才安排正反比并标注高风险、边界标记）
- ⛔ **展示给用户确认**，用户可修改计划

#### 4.2 出题者执行生成

按用户已选择的生成模式调用**出题者（Writer）**：
- 输入：确认后的生成计划
- 输出：JSON 数组，严格遵循 `[{"type","attribute","statement"},...]` 格式
- 按维度分批生成，维度之间可并行

#### 4.3 审查者质检与一轮优化

按用户已选择的生成模式调用**审查者（Reviewer）**：
- 输入：出题者生成的**完整候选题池**
- 审查维度：内容效度、语句质量、区分度、规范遵从、表面效度、儿童年龄适配
- 输出逐题《第一轮审查报告》，至少包含：ID、当前题目、维度、属性、问题类型、严重程度、处理建议、可执行修订要求
- 审查结论使用：**通过 / 需要改写 / 需要替代**；不得把“建议删除”作为生成层的直接删除动作

随后复用**出题者（Writer）**完成且仅完成一轮定向优化：
- 改写表达不清、双重含义、跨维漂移、年龄不适配或诊断化的题项
- 对无法修复的题项生成同维度、同属性的替代题
- 尽量保留原题 ID，保持每个维度和属性的题量配额
- **不得减少完整候选题池的总题数，不得生成预先的简版量表**

再由**审查者（Reviewer）**完成一次复核，输出《优化复核报告》，说明改写/替代题、残留风险、数量配额和进入语义筛查的准备状态。

#### 4.4 整合者整理输出

按用户已选择的生成模式调用**整合者（Integrator）**：
- 汇总策略计划、第一轮题项、第一轮审查、优化修订和复核报告
- 核对初始题池与优化后题池的总数、各维度题数、属性配额、ID 连续性和字段完整性
- 输出：`generation_session_log.md`（完整决策链记录）+ `generated_items.csv`
- `generated_items.csv` 必须是**一轮内容优化后的完整候选题池**，而不是 `genie_final_items.csv` 或任何预先缩减的简版

⛔ **完整题池确认门**：展示优化后的完整候选题池总量和每维题数。用户确认的是完整题池；确认后才进入 embedding provider 决策和 GENIE/local_GENIE。

### 生成层到验证层的硬性边界

- `generated_items.csv` 是一轮内容优化和复核后的**完整候选题池**，必须作为 GENIE/local_GENIE 的输入。
- 生成层优化前后题项总数、各维度题数、属性配额和 ID 数量必须保持一致；以用户确认的完整候选题池为基准，记为 N 题。
- `genie_final_items.csv` 是 GENIE/local_GENIE 的验证输出，不能作为同一流程的下一轮输入。
- 若 GENIE 最终从 N 题保留 K 题，应记录为“完整 N 题进入语义筛查后保留 K 题”，不得表述为“先筛选 K 题再验证”。

### 第 5 步：选择 embedding provider 并构建 GENIE 验证脚本

题目生成完成后，先单独完成嵌入来源决策。`--provider` 与 `--validation-config` 至少提供一个，否则生成器会拒绝继续。所有命令均在 **Skill 根目录** 执行；`construct_template.json` / `generated_items.csv` 若在任务工作目录中，请传入实际路径。

**不得默认选择任一 embedding provider。** 即使检测到本地模型、API key 或历史配置，也必须先向用户展示可选路径并等待明确选择；只有当用户明确选择“本地模型 / local”时，才生成 `--provider local` 脚本。

当用户选择本地模型时：
- 若用户只给出 Hugging Face 模型名或本地模型标识，则原样传入 `--embedding-model <模型名>`。
- 若用户给出本地模型文件夹，Windows 路径在 R 脚本中优先写成 `/` 形式，例如 `D:/models/your-embedding-model`，避免反斜杠转义问题。
- 本地模型路径/名称属于**项目级运行配置**，应写入当前项目的 `validation_config.json` 与 `run_genie.R`，不要写死进本 Skill。
- 生成脚本后仍需运行 `scripts/setup_check.R validation_config.json`；本地模型依赖 `AIGENIE` 的 Python/reticulate 环境，不等于只安装模型文件即可运行。

常用示例：

```powershell
# OpenAI：需要 OPENAI_API_KEY
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv -o .\run_genie.R `
  --provider openai --embedding-model text-embedding-3-small

# Jina：需要 JINA_API_KEY
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv -o .\run_genie.R `
  --provider jina --embedding-model jina-embeddings-v3

# Hugging Face：需要 HF_TOKEN 或可用 HF 环境
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv -o .\run_genie.R `
  --provider huggingface --embedding-model BAAI/bge-large-zh-v1.5

# 本地模型：需要 AIGENIE Python 环境
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv -o .\run_genie.R `
  --provider local --embedding-model <local-embedding-model-or-path>

# 已有 embedding matrix：矩阵列名必须匹配 items$ID
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv -o .\run_genie.R `
  --provider precomputed --embedding-matrix .\embeddings.rds

# 暂不验证：只写待验证状态，不运行 GENIE
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv -o .\run_genie.R `
  --provider skip
```

生成器会自动写入 `run_genie.R` 和 `validation_config.json`，并从 `generated_items.csv` 读取题项数据框；API Key 只从环境变量读取，不写入配置文件或脚本日志。

### 第 6 步：按 provider 检查环境、运行 GENIE 并生成标准报告

生成 `validation_config.json` 后，再运行 provider-specific 环境检查：

```powershell
Rscript .\scripts\setup_check.R .\validation_config.json
```

环境检查除包和 provider 外，还必须检查 `Sys.getlocale()`、中文 UTF-8 round-trip 和 `genie_input_file` 是否存在。若 Windows R 处于 `C` locale，不阻断运行，但后续报告必须把 locale/encoding warning 分类说明。

检查通过后，用户可在 R / RStudio 中 `source("run_genie.R")`，或在终端执行 `Rscript .\run_genie.R`。生成的 `run_genie.R` 必须只读取用户确认后的完整 `generated_items.csv`，保存 `genie_results_raw.rds`，然后调用 `scripts/genie_report.R` 做后处理与报告生成。GENIE 执行：

```
完整候选题池（generated_items.csv）
→ 嵌入 → 稀疏化 → UVA（wTO 0.20 去冗余）
→ EGA（TMFG/glasso 自选）→ bootEGA（100次自举，0.75 稳定性阈值）
→ type-level / overall 分层输出 → 标准 CSV + PNG + Markdown + DOCX 论文式报告
```

必需产物：`genie_input_manifest.json`、`genie_results_raw.rds`、`genie_metrics_summary.csv`、`genie_final_items.csv`、`genie_type_level_final_items.csv`、`genie_overall_final_items.csv`、`genie_warnings.csv`、`genie_session_info.txt`、`figures/*.png`、`genie_validation_report.md` 和正式交付的 `genie_validation_report.docx`。Markdown 是可复现中间产物，DOCX 是面向用户的正式报告；DOCX 应嵌入核心图表、网络图/稳定性图（若存在）、图题、表题、页码和附录。

### 第 7 步：读取标准报告并解读结果

首先阅读并交付 `genie_validation_report.docx`；同时保留 `genie_validation_report.md` 作为可复现中间产物，再按 `reference/interpreting-results.md` 解读：
- `initial_items` —— 进入 GENIE/local_GENIE 的完整候选题池（本流程对应 `generated_items.csv`）
- `final_items` —— GENIE/local_GENIE 完成 UVA/EGA/bootEGA 后的最终保留题项（含 `EGA_com` 社区标签）；它是验证输出，不是下一轮验证输入
- `genie_final_items.csv` —— primary final pool；若 `run.overall=TRUE` 且 `overall$final_items` 存在，采用 overall 结果
- `genie_type_level_final_items.csv` / `genie_overall_final_items.csv` —— 分别保留 type-level 与 overall 两套结果，二者题量可以不同，不能混为一谈
- `final_NMI` / `initial_NMI` —— 维度结构与目标的吻合度，并报告 NMI 增益百分点
- `UVA` —— 冗余删除的题对与数量，见 `genie_redundant_pairs.csv`
- `bootEGA` —— 稳定性过滤删除的题项，见 `genie_removed_items.csv`
- `figures/` —— NMI 前后图、题量削减图、删除流程图、attribute × EGA community 热图，以及可导出的网络图/稳定性图

**重要**：in-silico 验证是**语义层筛查**，**不替代**人类样本验证——它衡量的是题项内容的
语义一致性/冗余，不是应答层面的结构效度。报告必须说明方法原理、参考 Russell-Lasalandra, Christensen, & Golino (2026) 及 DOI `10.3758/s13428-026-03082-1`，并提示中文、探索性结构和用户明确要求反向题时的外推风险；真实被试上的 EGA/CFA、信度、测量不变性与外部专家内容效度均不可省略。
详见 `reference/methodological-boundaries.md`。

## 决策树

| 场景 | 用法 |
|------|------|
| 结构未定，有理论/已有量表 | 第 1 步走**路径 A 文献驱动** |
| 结构未定，探索性构念 | 第 1 步走**路径 B 访谈驱动** |
| 两条证据链互证 | 第 1 步走**路径 D 文献+访谈三角验证** |
| 结构已定 | 第 1 步走**路径 C 直接输入** |
| 全新量表，从构念生成题目 | 第 4 步**多智能体生成** + 第 5-6 步 `GENIE()` 验证 |
| 已有题池，只想对完整题池进行语义筛查 | 直接 `GENIE(items=your_df)`，跳过第 4 步；GENIE 内部才执行 UVA/EGA/bootEGA 削减 |
| 想查看多智能体生成过程 | `generation_session_log.md`（第 4.4 步产出） |

## 参考文档

- `reference/methodological-boundaries.md` —— **方法学边界与适用范围（务必先读）**：in-silico 边界 / 三重越界 / NMI 循环性 / bootEGA 语义 / 反向题风险 / LLM 评 LLM 局限
- `reference/workflow-logic.md` —— 系统性运行逻辑图（完整状态流程/分支逻辑/数据流/异常兜底）
- `reference/structure-determination.md` —— 四条结构确定路径的方法
- `reference/multi-agent-generation.md` —— 多智能体题项生成架构（四角色定义/交互流程/输出格式）
- `reference/aigenie-pipeline.md` —— AIGENIE 验证管线参数默认值速查
- `reference/construct-definition.md` —— 构念定义规范 + JSON schema + 示例
- `reference/chinese-adaptation.md` —— 中文编写规范 / 嵌入模型 / 文化校验
- `reference/interpreting-results.md` —— NMI/UVA/bootEGA 解读 + 验收标准
## Embedding Verification Decision Gate

题目生成完成后，进入 GENIE 前必须单独完成嵌入来源决策。生成题目不等于量表已经验证。

1. 检查 `generated_items.csv`、构念维度、CSV `type` 与 `attribute`。
2. 检查可用路径：OpenAI、Jina、HuggingFace、本地模型、已有 `embedding.matrix`，或暂不验证。
3. 向用户展示可用路径、所需环境变量和缺失依赖，等待用户选择；不得因本地模型或 API key 存在而默认选择某一路径。
4. 若用户选择本地模型，记录用户指定的模型名或路径（如 `<hf-model-name>` 或 `D:/models/your-embedding-model`），并用 `--provider local --embedding-model <模型名或路径>` 生成脚本。
5. 在 Skill 根目录运行 `scripts/build_aigenie_call.py`，并传入 `--provider` 或 `--validation-config`。
6. 生成 `validation_config.json` 与 `genie_input_manifest.json` 后运行 `scripts/setup_check.R validation_config.json`。
7. 运行 `run_genie.R` 后必须生成 Markdown、DOCX、核心 CSV 与 `figures/` 图表；DOCX 能打开、包含预期图片且报告无未解码 Unicode 占位符后，验证状态才可视为 `completed_with_report` 或 `completed_with_warnings`。
8. 保留生成的 `validation_config.json`，其中不得写入 API key。

支持的 provider：

| provider | 调用 | 前置条件 |
|---|---|---|
| `openai` | `GENIE(..., openai.API=...)` | `OPENAI_API_KEY` |
| `jina` | `GENIE(..., jina.API=...)` | `JINA_API_KEY` |
| `huggingface` | `GENIE(..., hf.token=...)` | `HF_TOKEN` 或可用 HF 环境 |
| `local` | `local_GENIE(...)` | 本地 AIGENIE Python 环境 |
| `precomputed` | `GENIE(..., embedding.matrix=...)` | 可读的数值矩阵，列名匹配 item ID |
| `skip` | 不运行 GENIE | 只保存题目和待验证状态 |

`skip` 路径必须输出 `items_generated=true`、`scale_validated=false`、
`validation_status=skipped`，不得使用“已验证量表”等表述。
