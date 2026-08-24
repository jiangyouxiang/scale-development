# AIGENIE / GENIE 流程与参数速查

本 Skill 使用双层架构：**多智能体生成层**（策略师→出题者→审查者→整合者）
负责生成，**AIGENIE 验证层**（`GENIE()`）负责心理测量验证。

当前依据的是 Russell-Lasalandra, Christensen, & Golino (2026) 的正式发表版本：
*Generative psychometrics via AI-GENIE: Automatic item generation and validation
with network-integrated evaluation*, *Behavior Research Methods*, 58(8), Article 217,
doi:10.3758/s13428-026-03082-1。

因此需要关注 AIGENIE 的两个方面：
1. **验证引擎**：嵌入 + 稀疏化 + UVA + EGA + bootEGA（由 `GENIE()` 封装，是使用重点）
2. **生成引擎**：`AIGENIE()` 原版的 `generate_items_via_llm()` **不再被本 Skill 使用**

---

## 本 Skill 使用的验证管线流程

`GENIE()` 的内部流程（接收用户确认后的完整候选题池进行 in-silico 验证）：

```
完整候选题池（`generated_items.csv`） → 嵌入 → 稀疏化 → UVA(去冗余) → EGA(维度识别) → bootEGA(稳定性) → 最终保留题项（`genie_final_items.csv`）
```

每套题项（按 `type` 分组）**独立**跑验证管线：

| 步骤 | 函数 | 关键参数 | 默认 |
|------|------|---------|------|
| 稀疏化 | `sparsify_embeddings` | — | 一次性稀疏，后续子集化 |
| 去冗余 | `reduce_redundancy_uva` → `EGAnet::UVA` | `uva.cut.off`（wTO 阈值） | `0.20` |
| 模型/表征择优 | `select_optimal_embedding` | `EGA.model` | `NULL`→同时测 TMFG 与 glasso，取 NMI 最大；full vs sparse 也择优 |
| 稳定性过滤 | `iterative_stability_check`（bootEGA） | `cut.off` / `boot.iter` | `0.75` / `100` |
| 最终维度 | `final_community_detection` | — | 输出最终 EGA + NMI |

---

## 仅涉及验证层的默认参数

### GENIE() 入口参数（`main_v2.R` 第 1492–1516 行）

| 参数 | 默认值 | 说明 | 本 Skill 使用的值 |
|------|--------|------|-----------------|
| `items` | **必填** | 数据框：`ID`, `statement`, `attribute`, `type` | 多智能体产出的 CSV |
| `embedding.matrix` | `NULL` | 可选预计算嵌入矩阵 | 不传（让 GENIE 生成） |
| `openai.API` | `NULL` | OpenAI API key | `Sys.getenv("OPENAI_API_KEY")` |
| `embedding.model` | `"text-embedding-3-small"` | 多语言，支持中文 | `text-embedding-3-small`（默认） |
| `EGA.model` | `NULL` | 自选 TMFG 或 glasso | `NULL`（让算法自选） |
| `EGA.algorithm` | 单维 `walktrap`、多维 `louvain` | 社区检测 | 默认 |
| `EGA.uni.method` | `"louvain"` | 单维性方法 | 默认 |
| `uva.cut.off` | `0.20` | wTO 阈值 | `0.20` |
| `run.overall` | `FALSE` | 类型级削减后对整体再做拟合 | `TRUE` |
| `all.together` | `FALSE` | 所有类型混在一起削减 | `FALSE` |
| `plot` | `TRUE` | 生成网络对比图 | `TRUE` |
| `silently` | `FALSE` | 抑制进度信息 | `FALSE` |

### 不再使用的生成参数

以下是 AIGENIE 原版的生成参数，本 Skill **不再经由生成器传递**，
因为生成已由多智能体层处理：

| 参数 | 原默认值 | 在本 Skill 中 |
|------|---------|-------------|
| `model` | `"gpt4o"` | 由 Codex 子代理或单代理角色切换时自定 |
| `temperature` | `1` | 由 Codex 子代理或单代理角色切换时自定 |
| `top.p` | `1` | 不使用 |
| `target.N` | `NULL→60` | 由策略计划决定 |
| `adaptive` | `TRUE` | 不使用（多智能体自行去重） |
| `system.role` | 内置 | 各角色独立设定 |
| `prompt.notes` | — | 策略师/出题者内置约束 |
| `response.options` | — | 生成层不需要 |
| `items.only` | `FALSE` | 不适用 |
| `embeddings.only` | `FALSE` | 不适用 |

---

## 验证管线的内部流程（引用 AIGENIE 源码）

```
GENIE() 的调用链（main_v2.R 第 1492–1676 行）：

1. validate_user_input_GENIE()     → 参数校验
2. 如未提供 embedding.matrix:
   generate_embeddings()           → 嵌入 API 调用
3. run_item_reduction_pipeline()   → 对完整输入题池执行削减管线（每个 type 独立）
   ├── sparsify_embeddings()
   ├── reduce_redundancy_uva()     → EGAnet::UVA
   ├── select_optimal_embedding()  → EGA.model 选择（TMFG vs glasso）
   ├── iterative_stability_check() → EGAnet::bootEGA
   └── final_community_detection() → 最终 EGA + NMI
4. (optional) run_pipeline_for_all() → run.overall=TRUE 时
5. build_return()                  → 结果组装
```

### 输入与输出边界

- `GENIE()`/`local_GENIE()` 的输入必须是用户确认后的完整候选题池；本 Skill 生成流程中对应 `generated_items.csv`。
- 生成层的一轮内容优化只改写或替代题项，不减少总题数、维度配额或属性配额。
- `final_items`、`genie_final_items.csv` 是 GENIE 内部 UVA/EGA/bootEGA 后的输出，不得作为同一验证流程的预先简版或下一轮输入。
- 若输入为 N 题而输出为 K 题，应报告为“完整 N 题进入语义筛查后保留 K 题”。

### 数量阈值（硬约束）

- 网络分析需 **≥6 题**（否则返回部分结果并告警）
- UVA 后需 **≥4 题** 才继续
- 多个 item type 时 `run.overall=TRUE` 才在整体层面再跑一次拟合分析

---

## 返回结构（GENIE 默认，`keep.org=FALSE`）

```
$item_type_level
  $<每个维度>
    $final_items     # GENIE 内部筛查后的最终题项；不是下一轮 GENIE 输入
    $final_NMI       # 削减后维度结构吻合度
    $initial_NMI     # 削减前基线
    $UVA             # n_removed / n_sweeps / redundant_pairs
    $bootEGA         # 删除项与稳定性
    $EGA.model_selected  # "TMFG" 或 "Glasso"
    $start_N / $final_N
    $network_plot / $stability_plot
$overall
  $final_items / $embeddings  # （run.overall=TRUE 时含更多字段）
```

---

## 嵌入模型选择（中文）

| 模型 | provider | 中文表现 | 备注 |
|------|----------|---------|------|
| `text-embedding-3-small` | OpenAI | 良好 | 默认，性价比高 |
| `text-embedding-3-large` | OpenAI | 更好 | 维度更高，成本略高 |
| `jina-embeddings-v3` | Jina | 良好 | 需 `jina.API`（有免费额度） |
| `BAAI/bge-*-zh` | HF | 中文专用 | 需 `hf.token` |

API key 通过 `Sys.getenv()` 读取，不硬编码。
## Embedding Decision Gate

`GENIE()` 的 `embedding.matrix` 已提供时，不会再调用任何嵌入 API。
因此 OpenAI key 不是 GENIE 验证的理论必需条件，而只是其中一个嵌入来源。

| provider | R 入口 | 嵌入来源 | 是否需要 OpenAI key |
|---|---|---|---|
| `openai` | `GENIE()` | `text-embedding-*` | 是 |
| `jina` | `GENIE()` | `jina-embeddings-*` | 否，需要 `JINA_API_KEY` |
| `huggingface` | `GENIE()` | HF embedding model | 否，需要 HF token/环境 |
| `local` | `local_GENIE()` | 本地 sentence-transformers | 否 |
| `precomputed` | `GENIE()` | `embedding.matrix` | 否 |
| `skip` | 不调用 | 暂缓验证 | 否 |

决策门产出的 `validation_config.json` 只保存 provider、模型、矩阵路径和
分析参数。所有秘密仍通过 `Sys.getenv()` 在 R 运行时读取。



---

## 标准 GENIE 后处理与结果口径（Skill 约定）

从本 Skill 生成的 `run_genie.R` 必须执行四段式验证：

1. **输入冻结**：`generated_items.csv` 是唯一输入；`genie_input_manifest.json` 记录绝对路径、行数、type/attribute 分布、SHA-256、provider、embedding model、`run.overall` 和 `uva.cut.off`。
2. **环境与编码预检**：记录 `Sys.getlocale()` 与中文 UTF-8 round-trip；Windows `C` locale 不阻断运行，但在报告中列为 locale/encoding warning。
3. **运行 GENIE/local_GENIE**：保存 `genie_results_raw.rds`，不得在 R 主脚本中把 type-level 拼接结果直接当作唯一最终结果。
4. **后处理与报告**：调用 `scripts/genie_report.R`，统一解码 Unicode 转义占位符、导出 CSV/PNG/Markdown；再调用 `scripts/genie_report_docx.py` 生成正式 DOCX，并嵌入图表与附录表。

### type-level 与 overall 是两套结果

`$item_type_level` 是按 `type` 独立执行的题项筛查；`$overall` 是 `run.overall=TRUE` 时在整体层面的额外筛查。二者的最终题量、NMI、UVA/bootEGA 删除数可以不同。

Skill 的文件口径固定为：

| 文件 | 定义 |
|---|---|
| `genie_type_level_final_items.csv` | 拼接所有 `$item_type_level[[type]]$final_items`，用于诊断每个 type 的保留情况 |
| `genie_overall_final_items.csv` | `$overall$final_items`，仅在 overall 结果存在时有内容 |
| `genie_final_items.csv` | primary final pool；若 `run.overall=TRUE` 且 `$overall$final_items` 存在，则采用 overall，否则采用 type-level 拼接 |

因此，若 type-level 共保留 67 题而 overall 保留 51 题，应报告为“type-level 诊断保留 67 题；overall primary final pool 保留 51 题”，不能把 67 题误当作 overall 结果，也不能把 51/67 题作为同一轮 GENIE 的输入。


## 正式报告交付

`genie_validation_report.md` 是可复现的中间报告；`genie_validation_report.docx` 是正式交付物。DOCX 至少应包含封面、执行摘要、输入与方法、type-level 与 overall 分层结果、NMI/UVA/bootEGA 解释、属性—社区对应关系、核心图表及图注、删除题项与 warning 附录、方法学边界和真实样本验证建议。

当 `run.overall=TRUE` 时，报告必须同时呈现两套口径：type-level 用于诊断各类型的删题与结构变化，overall 用于 primary final pool；二者不能在表格或文字中合并成一个“最终结果”。
