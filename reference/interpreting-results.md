# 结果解读与验收标准

AIGENIE 返回经 in-silico 验证的题池与一系列心理测量指标。本文档说明如何解读，
以及各阶段的验收标准。

> ⚠️ **边界声明（先读）**：以下所有指标都建立在**题项文本嵌入的语义相似度**之上，
> **不是被试应答数据**。它们衡量的是"题项内容的语义一致性 / 冗余"，**不等于**应答层面的
> 结构效度、信度或测量不变性。在**中文 / 探索性结构 / 含反向题**场景下尤其不可外推到真实样本。
> 完整说明见 `reference/methodological-boundaries.md`。

## 核心指标

### NMI（Normalized Mutual Information，标准化互信息）

衡量 EGA 识别出的维度结构与你预设的 `attribute` 真实结构的吻合度。

| 指标 | 含义 |
|------|------|
| `initial_NMI` | GENIE 接收的完整候选题池的基线（本流程应对应 `generated_items.csv`） |
| `final_NMI` | 削减后（稀疏化 + UVA + bootEGA）的吻合度 |
| `final_NMI − initial_NMI` | AIGENIE 管线的端到端增益 |

- NMI 范围 0–1，**越接近 1** 表示识别出的维度与预设结构越一致。
- NMI 偏低 → 维度间重叠、属性同义、或构念定义跨维漂移（回到构念定义修订）。
- 注意：预削减 NMI 常接近 1.0（因每属性模板化生成易分离），重点看 final 与结构合理性。

> ⚠️ **NMI 是循环指标，高 NMI 不等于构念效度**：NMI 的"真值标签"就是 LLM 自己给每道题打的
> `attribute`——按属性生成题项、再用嵌入聚类还原属性，近乎同义反复。高 NMI 只说明"生成时属性
> 可分离"，**不是**应答层面的效度证据。另一面：**反射式 / 单维构念**题项语义高度同质，可能
> NMI 偏低，切勿据此误判"结构差"而人为撕裂维度。解读时把权重放在内容合理性、专家内容效度与
> 真实样本结果上，而非 NMI 数字本身。

### UVA（Unique Variable Analysis，唯一变量分析）

基于加权拓扑重叠（wTO）检测局部依赖（冗余）。`uva.cut.off=0.20`：wTO ≥ 0.20 的题对被
判为冗余并删除其一。

返回 `$UVA`：
- `n_removed` —— 删除的冗余题数
- `n_sweeps` —— 迭代轮数
- `redundant_pairs` —— 被判冗余的题对（可人工复核）

冗余去除率高（≥50%）说明候选题大量近义——属正常，也提示生成多样性可提升。

### bootEGA（Bootstrap EGA）

通过自助重采样（`boot.iter=100`）评估维度与题项稳定性，删除稳定性 < `cut.off=0.75`
的题项。

> ⚠️ **这里 bootstrap 的不是被试**：标准 bootEGA 重采样**个案（被试）**以评估跨样本可复现性；
> 本管线没有被试，它对**嵌入矩阵做参数化自助**（从原始嵌入参数化的多元正态分布抽样）。因此
> "0.75 稳定性"衡量的是**嵌入扰动下的几何稳定性**，**不是跨人类样本的可复现性**——汇报时务必
> 措辞准确，勿让用户误读为"已证明跨样本稳定"。

返回 `$bootEGA`：
- `n_removed` / `items_removed` —— 因不稳定被删的题项
- `post_uva_final_boot` —— 最终自助结果

### initial_items 与 final_items

`initial_items` 表示进入 GENIE/local_GENIE 的完整候选题池；`final_items` 表示 GENIE 完成 UVA/EGA/bootEGA 后的最终保留题项。两者不能混为一谈，也不能把 `final_items` 作为同一流程的预先简版输入。若 N 题最终保留 K 题，应表述为“完整 N 题进入语义筛查后保留 K 题”。

### final_items

最终保留题项，列含 `ID` / `statement` / `attribute` / `type` / `EGA_com`（EGA 识别的
社区/维度标签）。**核对 `EGA_com` 是否与预设 `attribute`/维度对应**——错位说明该题
载荷到了非预期维度。

## 图

- `network_plot` —— 削减前后网络对比（节点=题项，边=嵌入相关，颜色=社区）
- `stability_plot` —— 削减前后题项自助稳定性对比

## 阶段验收标准

| 阶段 | 验收标准 |
|------|---------|
| 原型（生成 + 优化） | 完整候选题池经过一轮审查—优化—复核；优化前后题量和维度配额一致；专家内容效度评分需单独收集 |
| 筛选（UVA + EGA） | 报告冗余去除率、最终题量、EGA 社区与预设结构的对应关系 |
| 中文适配 | 报告中文题项可用率与文化适配问题；不得把英文论文结果直接当中文效度证据 |
| 真实样本验证 | 在被试数据上另行报告 EGA/CFA、信度、测量不变性和外部效度 |

## 解读后的必做项

1. **专家内容效度复核** —— in-silico 验证不替代人类判断。每维抽题请领域专家评 1–5 分。
2. **人类样本验证（可选第二步）** —— 真实被试数据上重跑 EGA/CFA 确认结构。
3. **偏见审查** —— 检查题项是否含文化/性别/年龄隐性偏见。
4. **伦理标注** —— 论文方法部分明确说明 AI 参与程度与人类复核流程。

## 失败模式排查

| 现象 | 可能原因 | 处理 |
|------|---------|------|
| final_NMI 低 | 维度重叠 / 构念定义模糊 | 修订构念定义，增强维度区分 |
| UVA 删除过多 | 属性同义、跨批次重复或生成多样性低 | 回到策略师/出题者，丰富 attributes，维护跨批次已生成题项清单后重生成 |
| 剩题 < 4 | 初始 target.N 太小或冗余太高 | 提高 `item_count_per_dimension`（≥60） |
| EGA_com 与预设错位 | 题项跨维漂移 | 检查属性定义，修改生成计划与出题者约束 |
| 报错题数 < 6 | 某维生成不足 | 增加该维 target.N |


---

## 论文式 GENIE 报告模板（Skill 标准）

`genie_validation_report.md` 至少包含以下层次；这些内容随后应原样或经过排版后进入正式 `genie_validation_report.docx`：

1. **执行摘要**：完整 N 题进入 GENIE/local_GENIE，primary final pool 最终保留 K 题；报告 initial vs final NMI 及增益百分点。
2. **输入与模型**：输入文件、SHA-256、provider、embedding model、`run.overall`、`uva.cut.off`、locale/encoding 状态。
3. **核心指标表**：每个 type 与 overall 一行：`level`、`type`、`start_N`、`final_N`、`removed_N`、`removed_rate`、`EGA_model`、`initial_NMI_raw`、`final_NMI_raw`、`delta_NMI_pp`、`UVA_removed`、`UVA_sweeps`、`bootEGA_removed`、`warning_count`。
4. **图表**：NMI 前后比较、题量削减、UVA/bootEGA 删除流程、attribute × EGA community 热图；若 AIGENIE 返回网络图/稳定性图，应按 type 和 overall 分别导出。
5. **逐层解释**：分别解释 type-level 与 overall。二者是不同分析，不得把 type-level 拼接输出解释为 overall 最终量表。
6. **删除明细**：`genie_redundant_pairs.csv` 解释 UVA 冗余对；`genie_removed_items.csv` 解释 bootEGA 删除项。
7. **warnings 分类**：至少分为 `locale`、`encoding`、`dependency`、`computation`、`other`。locale 类 warning 通常说明 Windows R 编码环境，非 locale 类 warning 需要人工复核。
8. **方法边界**：固定说明这只是文本嵌入层面的 in-silico 语义筛查，不是学生样本信度、EFA/CFA、测量不变性或外部效度。
9. **DOCX 交付检查**：封面、目录域、页眉页脚/页码、核心图表、图题表题、宽表附录、warning 分类与 session info 应在 Word 文档中可读；Markdown 只作为中间产物，不替代 DOCX。

### NMI 增益的写法

报告 NMI 时同时给 raw 值和百分点变化：

> initial_NMI = 0.449，final_NMI = 0.596，提升 14.75 个百分点。

不要写成“效度提升 14.75%”。NMI 只是语义聚类与预设 attribute 标签的一致性指标，不是应答层面的效度系数。

### 自动风险提示

报告应自动标出以下情形：`final_NMI < .50`、NMI 增益为负、某层最终少于 4 题、删除率过高、attribute/community 热图严重错位、出现非 locale 类 warnings。风险提示不等于流程失败，但意味着必须人工复核。

### 中文编码故障排查

若 RDS、CSV 或日志中出现 Unicode 转义占位符（例如 U+XXXX）这类字面量，优先判断为 Windows R locale / AIGENIE 内部字符串转换问题。处理顺序：

1. 确认 `generated_items.csv` 是否可按 UTF-8 正常读取；若输入完好，不要重写题池。
2. 查看 `genie_results_raw.rds` 是否已经含 Unicode 转义占位符；若 RDS 内已转义，单纯 `write.csv(fileEncoding="UTF-8")` 无法修复。
3. 使用 `scripts/genie_report.R` 的 Unicode escape 后处理重新导出 CSV/Markdown。
4. 在报告 `warnings` 中保留 locale/encoding 说明，避免误判为题项内容损坏。
