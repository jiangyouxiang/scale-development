
# 工作流逻辑与状态机

本文件规定 scale-development skill 的端到端执行顺序、决策门、文件流和兜底逻辑。
所有 ⛔ 决策门都应优先通过 Codex 弹出选择题 / choice UI / `request_user_input` 类工具让用户点击选择；
当前环境没有弹出选择能力时，才用编号选项兜底，且只要求用户回复编号。

---

## 一、总体架构（双层设计）

```
┌──────────────────────────────────────────────────────────────┐
│  四条结构路径 → 生成模式决策门 → 生成/已有题池 → AIGENIE 验证层 │
│  结构确定       题目生成与质检        语义心理测量验证          │
└──────────────────────────────────────────────────────────────┘
```

- **结构确定层**：文献驱动 / 访谈驱动 / 用户直接输入 / 文献+访谈三角验证。
- **报告层**：路径 A/B/D 必须产出 `dimension_structure_report.md` 和 `dimension_structure_report.docx`。
- **生成层**：先由用户选择真多智能体协同 / 单智能体角色模拟 / 已有题池仅验证。
- **验证层**：把生成层优化后的完整候选题池交给 AIGENIE `GENIE()`；GENIE 内部执行语义筛查、UVA/EGA/bootEGA 削减，不使用 AIGENIE 原版生成层。

---

## 二、完整状态流程图

```
用户提出量表开发/验证需求
        │
        ▼
⛔ 决策门 1：结构确定路径（弹出选择题）
        │
        ├─ A 文献驱动 ─┐
        ├─ B 访谈驱动 ─┼─ 产出 dimension_structure_report.md + .docx
        ├─ D 三角验证 ─┘
        │
        └─ C 直接输入 → 回显结构/可选 structure_confirmation.md
        │
        ▼
⛔ 决策门 2：维度结构确认（硬门禁）
        │
        ▼
construct_template.json
        │
        ▼
基础环境检查 setup_check.R
        │
        ▼
⛔ 决策门 3：生成模式选择
        │
        ├─ A 真多智能体协同（推荐） → 策略师/出题者/审查者/整合者子代理
        ├─ B 单智能体角色模拟（显式兜底） → 同一代理内保留四角色产物
        └─ C 已有题池仅验证 → 跳过生成层
        │
        ▼
⛔ 决策门 4：反向题设置
        │
        ▼
⛔ 决策门 5：生成策略确认
        │
        ▼
第一轮审查报告
        │
        ▼
出题者固定一轮优化 → 审查者复核
        │
        ▼
整合者输出完整 generated_items.csv + generation_session_log.md
        │
        ▼
⛔ 决策门 6：完整题池确认
        │
        ▼
⛔ 决策门 7：embedding provider 选择
        │
        ▼
run_genie.R + validation_config.json + genie_input_manifest.json
        │
        ▼
GENIE/local_GENIE(items=generated_items.csv 的完整题池) → genie_results_raw.rds → 标准后处理报告（genie_validation_report.md + CSV + figures）
```

---

## 三、关键决策门（⛔）

### ⛔ 决策门 1 — 结构确定路径

优先弹出选择题：
- A 文献驱动
- B 访谈驱动
- C 用户直接输入
- D 文献+访谈三角验证

### ⛔ 决策门 2 — 维度结构确认（硬门禁）

A/B/D 的交付物是学术论文式**维度结构论证报告**：
- `dimension_structure_report.md`
- `dimension_structure_report.docx`
- 正文引文、参考文献、证据整合表、推荐维度结构表
- D 路径额外包含三角对比表

**用户未明确确认前，不进入第 2 步。**

### ⛔ 决策门 3 — 生成模式选择

优先弹出选择题：
- 真多智能体协同（推荐）：使用子代理/多代理能力，体现本 Skill 核心。
- 单智能体角色模拟：显式兜底，只有用户选择后才能使用。
- 已有题池仅验证：跳过生成层，直接进入 provider 决策与 GENIE。

**不可默认单智能体替代多智能体**。选择结果写入 `generation_session_log.md`。

### ⛔ 决策门 4 — 反向题设置

优先弹出选择题：
- 不包含反向题（推荐，符合原论文验证条件）
- 包含少量反向题（另问比例）
- 暂不确定，先全正向生成

结果写入 `construct_template.json` 的 `reverse_items` 字段。

### ⛔ 决策门 5 — 生成策略确认

策略师产出「题项生成计划」后展示给用户，用户确认后才进入出题阶段。

### ⛔ 决策门 6 — 完整题池确认

审查者完成第一轮审查、出题者完成一轮优化、审查者完成复核、整合者完成数量核对后，展示优化后的完整候选题池。用户确认的是完整题池，不是预先筛出的简版；确认后才进入 provider 决策。

### ⛔ 决策门 7 — 嵌入来源选择

题目确认后必须选择验证嵌入来源，再生成 `validation_config.json` 和 `run_genie.R`。

---

## 四、分支逻辑

### 4.1 结构确定 → 路径分叉

```
走哪条路径？
├── A 文献驱动 → dimension_structure_report.md + .docx
├── B 访谈驱动 → dimension_structure_report.md + .docx
├── C 直接输入 → 引导录入 + 质检 + 回显确认
└── D 三角验证 → 含三角对比的 dimension_structure_report.md + .docx
         ↓
    ⛔ 用户确认/修改维度结构
         ↓
    construct_template.json
```

### 4.2 生成层 → 验证层切换

```
生成模式选择？
├── A 真多智能体协同 → 策略师/出题者/审查者 → 一轮优化与复核 → 整合者 → 完整 generated_items.csv
├── B 单智能体角色模拟 → 四角色顺序执行 → 一轮优化与复核 → 完整 generated_items.csv
└── C 已有题池仅验证 → 用户提供 items 数据框/CSV
         ↓
    provider 决策门
         ↓
    build_aigenie_call.py → run_genie.R
         ↓
    GENIE(items=generated_items.csv 的完整题池)
```

### 4.3 审查—优化—复核固定循环

```
第一轮审查
    ↓
出题者固定优化一轮
    ├── 需要改写 → 改写原题并尽量保留 ID
    ├── 需要替代 → 生成同维度、同属性替代题
    └── 通过 → 原题保留
    ↓
审查者复核
    ↓
整合者核对数量不变量并输出完整题池
```

生成层不自动删除题项，不生成预先简版；疑难题必须通过改写或同维度同属性替代维持题量。

---

## 四点四、生成层与验证层的硬性边界

- 生成层优化前后总题数、各维度题数、属性配额和 ID 数量必须一致。
- 用户确认后的完整候选题池必须以原始 N 题进入 GENIE/local_GENIE；GENIE 可能在内部输出较短的 `final_items`。
- `generated_items.csv` 是完整输入；`genie_final_items.csv` 是验证输出，不能作为同一流程的下一轮输入。
- 日志必须记录 `input_item_count`、`final_item_count` 和“完整题池进入语义筛查”的说明。

## 五、数据流（文件级）

| 步骤 | 输入 | 处理 | 输出 |
|------|------|------|------|
| 第 1 步 A | 构念名 + 检索指示 | WebSearch/deep-research + 学术化写作 | `dimension_structure_report.md` + `.docx` |
| 第 1 步 B | 访谈逐字稿 | 三级编码 + 学术化写作 | `dimension_structure_report.md` + `.docx` |
| 第 1 步 C | 用户口述结构 | 引导录入 + 质检 | 回显确认 / `structure_confirmation.md` |
| 第 1 步 D | A+B 证据链 | 三角对比 + 学术化写作 | `dimension_structure_report.md` + `.docx` |
| 第 1→2 步 | 确认后的结构 | 人工/Codex 整理 | `construct_template.json` |
| 第 3 步 | 基础 R 环境 | `setup_check.R` | 控制台 ✓/✗ |
| 第 4.0 步 | 用户决策 | 弹出选择题（生成模式） | `generation_session_log.md` 的 `generation_mode` |
| 第 4.1 步前 | 用户决策 | 弹出选择题（反向题设置） | `construct_template.json` 的 `reverse_items` |
| 第 4.1 步 | 构念 JSON | 策略师 | 《题项生成计划》 |
| 第 4.2 步 | 生成计划 | 出题者 | 题项 JSON |
| 第 4.3 步 | 完整题项 JSON | 审查者 | 第一轮审查报告 → 出题者一轮优化 → 审查者复核报告 |
| 第 4.4 步 | 全部产物 | 整合者 | 数量核对 + `generation_session_log.md` + 完整 `generated_items.csv` |
| 第 5 步 | construct.json + items.csv + provider 决策 | `build_aigenie_call.py` | `run_genie.R` + `validation_config.json` |
| 第 6 步 | validation_config.json + run_genie.R | `setup_check.R` 后 `Rscript` | `genie_results.rds` + `genie_final_items.csv` + 图 |
| 第 7 步 | genie_results.rds | 解读 | 用户理解 + 下一步 |

---

## 六、异常与兜底

| 场景 | 反应 | 处理位置 |
|------|------|----------|
| 当前环境没有弹出选择题工具 | 用编号选项兜底，只要求用户回复编号 | 所有 ⛔ 门 |
| 用户选择真多智能体但子代理不可用 | 再次弹出选择：单智能体兜底 / 暂停 / 已有题池验证 | 第 4.0 步 |
| 路径 A/B/D 未生成 docx | 运行 `scripts/md_to_docx.py`；失败则修复依赖后重试 | 第 1 步 |
| 用户维度定义模糊 | 追问并给范例 | 第 1 步 |
| 每维属性 < 2 | 报错退出 | 第 2 步/JSON 校验 |
| 策略计划用户不满意 | 用户修改后重走策略师 | 第 4.1 步 |
| 出题者产出不足 | 可要求出题者继续生成或重新设置策略 | 第 4.2 步 |
| 审查发现问题 | 固定由出题者优化一轮，审查者复核；不得直接删题 | 第 4.3 步 |
| R 环境缺失 | `setup_check.R` 检测并输出修复命令 | 第 3 步 |
| API key 未设 | `setup_check.R` 与 `run_genie.R` 报错；key 只从环境变量读取 | 第 5→6 步 |
| GENIE 验证失败 | 返回部分结果与警告 | 第 6 步 |

---

## 七、所用工具索引

| 工具/资源 | 用途 | 触发时机 |
|-----------|------|----------|
| skill:`deep-research` | 文献检索扇出 + 来源核验 + 合成报告 | 路径 A/D |
| WebSearch | 补充检索、核验特定引用 | 路径 A/D |
| 弹出选择题 / choice UI / `request_user_input` | 决策门优先交互方式 | 所有 ⛔ 门 |
| 编号选项兜底 | 无弹出选择工具时使用 | 所有 ⛔ 门 |
| Codex 子代理 / 多代理能力 | 真多智能体协同执行四角色 | 第 4 步（用户选择 A） |
| 单智能体角色模拟 | 用户明确选择后的兜底模式 | 第 4 步（用户选择 B） |
| `scripts/md_to_docx.py` | Markdown 维度结构报告转 `.docx` | 第 1 步 A/B/D |
| `scripts/build_aigenie_call.py` | 构念 JSON + items CSV → R 脚本 | 第 5 步 |
| `scripts/setup_check.R` | R 环境自检 | 第 3/6 步 |
| `GENIE()` | 验证削减：嵌入 + UVA + EGA + bootEGA | 第 6 步内部 |

---

## 八、文件索引

| 文件 | 类型 | 作用 |
|------|------|------|
| `SKILL.md` | 入口 | 端到端流程 + 决策门 + provider 决策 |
| `reference/structure-determination.md` | 参考 | 四条路径 + 学术化报告硬门禁 |
| `reference/dimension-structure-report.md` | 参考 | `dimension_structure_report.md`/`.docx` 写作模板、引用规范与检查清单 |
| `reference/multi-agent-generation.md` | 参考 | 生成模式决策门 + 四角色协同架构 |
| `reference/methodological-boundaries.md` | 参考 | in-silico 边界与风险 |
| `reference/aigenie-pipeline.md` | 参考 | AIGENIE 验证管线参数默认值 |
| `reference/construct-definition.md` | 参考 | 构念规范 + JSON schema |
| `reference/chinese-adaptation.md` | 参考 | 中文题项编写规范 |
| `reference/interpreting-results.md` | 参考 | NMI/UVA/bootEGA 解读 |
| `scripts/md_to_docx.py` | 工具 | 报告 Word 转换 |
| `scripts/build_aigenie_call.py` | 工具 | 构念 JSON + items CSV → `run_genie.R` |
| `scripts/setup_check.R` | 工具 | R 环境自检 |
| `dimension_structure_report.md` | 产物 | 学术化维度结构论证报告 |
| `dimension_structure_report.docx` | 产物 | Word 版维度结构论证报告 |
| `generation_session_log.md` | 产物 | 生成模式、角色产物与决策链记录 |
| `generated_items.csv` | 产物 | 四智能体优化后的完整候选题池；GENIE/local_GENIE 的唯一输入 |
| `run_genie.R` | 产物 | GENIE 验证脚本 |
| `genie_results.rds` | 产物 | GENIE 验证结果 |
| `genie_final_items.csv` | 产物 | GENIE/local_GENIE 内部语义筛查后的最终保留题项；不是输入 |

---

## 九、嵌入来源决策门

第 5 步不再默认假定 OpenAI。题目确认后必须先选择验证嵌入来源，再生成
`validation_config.json` 和 `run_genie.R`。

状态约束：

- `items_generated=true` 只说明生成层产出了题目。
- 只有 GENIE 或 `local_GENIE` 成功完成后，才可写入 `scale_validated=true`。
- `skip` 不得创建伪造的 `genie_results.rds`，只写 `validation_status.rds`。
- 任何 provider 的 key 都只能从当前环境读取，不得写入 JSON、R 脚本或日志。

命令示例：

```powershell
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv --provider openai --embedding-model text-embedding-3-small -o .\run_genie.R
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv --provider local --embedding-model <local-embedding-model-or-path> -o .\run_genie.R
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv --provider precomputed --embedding-matrix .\embeddings.rds -o .\run_genie.R
python .\scripts\build_aigenie_call.py .\construct_template.json .\generated_items.csv --provider skip -o .\run_genie.R
Rscript .\scripts\setup_check.R .\validation_config.json
```




---

## GENIE 验证状态机（标准报告版）

验证阶段状态必须按以下方式推进：

```text
pending
  → running
  → completed_with_report          # GENIE 成功，CSV/PNG/Markdown/DOCX 全部生成，无 warning
  → completed_with_warnings        # GENIE 成功，DOCX/Markdown/核心产物齐全，但存在 locale/encoding/计算等 warning
  → failed                         # GENIE 调用或后处理失败，缺少核心报告产物
```

完成条件不是“控制台显示 done”或“存在 `genie_final_items.csv`”，而是同时存在：

- `genie_input_manifest.json`
- `genie_results_raw.rds`
- `genie_metrics_summary.csv`
- `genie_final_items.csv`
- `genie_type_level_final_items.csv`
- `genie_overall_final_items.csv`（无 overall 时可为空表，但文件应存在）
- `genie_warnings.csv`
- `genie_session_info.txt`
- `genie_validation_report.md`
- `genie_validation_report.docx`
- `figures/nmi_before_after.png`
- `figures/item_reduction_by_type.png`
- `figures/removal_waterfall.png`
- `figures/attribute_community_heatmap.png`
- `genie_validation_report.md`

### 数据流不变量

```text
generated_items.csv  --唯一输入-->  GENIE/local_GENIE  --原始输出-->  genie_results_raw.rds
                                                        --后处理-->  genie_validation_report.md + CSV + figures
```

`genie_final_items.csv`、`genie_type_level_final_items.csv`、`genie_overall_final_items.csv` 都是后处理输出，不得作为同一流程的输入。`validation_config.json` 中的 `genie_input_file` 必须与 `run_genie.R` 实际读取的 `input_file` 完全一致。


### DOCX 完成门禁

验证状态不能仅因 Markdown 或 `genie_final_items.csv` 存在而标记完成。正式报告阶段必须检查：DOCX 文件存在且可被 ZIP/Word 读取、包含核心图片关系、正文和附录无 Unicode 转义残留、核心 CSV/PNG 齐全。DOCX 失败时保留 Markdown/CSV/PNG，但状态必须为 `completed_with_warnings`，并记录可诊断的失败日志。
