# scale-development

`scale-development` 是一个用于社会科学与心理测量量表开发的 Codex Skill。它把构念界定、维度结构论证、完整候选题池生成、一轮内容审查与优化，以及 AIGENIE/local_GENIE 的 in-silico 语义筛查串成一个可审计的人机协作流程。

> 本仓库包含的是 **Codex Skill**，不是独立 Python 包、R 包或通用命令行程序。流程应由 Codex 执行，并保留所有需要用户确认的决策门。

## 功能概览

- 支持文献驱动、访谈驱动、直接输入、文献+访谈三角验证四类构念结构确定路径。
- 使用四个可审计角色：策略师、出题者、审查者、整合者。
- 在内容优化阶段保留完整候选题池；生成层审查不得提前缩减题池。
- 将完整 `generated_items.csv` 输入 `GENIE()` 或 `local_GENIE()` 进行语义筛查。
- 区分 type-level 诊断结果和可选 overall 分析结果。
- 输出可复现的 CSV、PNG、Markdown 文件，并生成正式的 `genie_validation_report.docx`，包含图表、方法说明、文献引用、warnings 和附录。

## 在 Codex 中安装

将本文件夹复制或链接到 Codex skills 目录，例如：

```text
$CODEX_HOME/skills/scale-development
```

Windows 上 `$CODEX_HOME` 通常位于用户的 `.codex` 目录。实际路径随环境而异，不要在脚本或报告中写死个人路径。

## 运行要求

### Skill 本身

- 支持 Skills 的 Codex。
- Python 3.10 或更高版本。
- 生成正式 Word 报告需要 `python-docx`：

```bash
python -m pip install -r requirements.txt
```

### GENIE 验证

- R 4.3 或更高版本；开发测试使用 R 4.4.x。
- 按所选 provider 和 AIGENIE 版本安装所需 R 包，通常包括 `jsonlite`、`reticulate`、`ggplot2`、`igraph`、`patchwork`、`EGAnet` 和 `AIGENIE`。
- AIGENIE 包及其文档要求的 Python 环境或 provider 依赖。

GENIE/local_GENIE 是集成验证路径。仓库内单元测试和 smoke test 不调用付费 API，也不要求真实 embedding 服务。

### 本地 embedding provider

本地 embedding 必须由用户明确选择；Skill 不会因为本机存在模型就自动推断：

```text
--provider local --embedding-model BAAI/bge-m3
```

本地 AIGENIE/reticulate 环境必须能加载所选模型。不同 AIGENIE 安装方式可能还需要 `sentence-transformers`、`transformers`、`torch` 以及已配置的 `reticulate` 环境。

### API providers

OpenAI、Jina 和 Hugging Face provider 分别需要在仓库外设置环境变量：`OPENAI_API_KEY`、`JINA_API_KEY` 或 `HF_TOKEN`。不要把凭据写入 `validation_config.json`、fixtures、报告或 Git 历史。

## 标准验证流程

1. 确认完整候选题池，并写出 `generated_items.csv`。
2. 明确选择 embedding provider。
3. 使用 `scripts/build_aigenie_call.py` 生成 provider-aware 的 `run_genie.R` 和 `genie_input_manifest.json`。
4. 运行 provider 和环境预检。
5. 执行 `Rscript run_genie.R`。
6. 阅读 `genie_validation_report.md`，并交付 `genie_validation_report.docx`。

主输入始终是完整的 `generated_items.csv`。`genie_final_items.csv` 是 GENIE 的输出，绝不能在同一轮验证中重新作为输入。若 `run.overall=TRUE` 且 overall final pool 可用，`genie_final_items.csv` 采用 overall 结果；type-level 和 overall 导出仍分别保留，用于解释。

## 输出文件

一次完整报告运行应包含：

- `genie_input_manifest.json`
- `genie_results_raw.rds`
- `genie_metrics_summary.csv`
- `genie_final_items.csv`
- `genie_type_level_final_items.csv`
- `genie_overall_final_items.csv`
- `genie_removed_items.csv`
- `genie_redundant_pairs.csv`
- `genie_warnings.csv`
- `genie_session_info.txt`
- `figures/*.png`
- `genie_validation_report.md`，可复现的中间报告
- `genie_validation_report.docx`，正式交付报告

报告会说明 GENIE/local_GENIE 的方法原理、Russell-Lasalandra、Christensen 和 Golino（2026）文献依据、初始/最终 NMI 与百分点变化、UVA 冗余筛查、bootEGA 稳定性筛查、题项削减、attribute/community 对应关系、适用时的反向题风险、warnings、可复现信息和方法学边界。DOCX 会嵌入核心图表，以及 AIGENIE 返回的 network/stability 图。

## 方法学边界

GENIE/local_GENIE 是基于文本 embedding 的 **in-silico 语义筛查与内部题项削减流程**。它不是学生或被试样本层面的信度证据、EFA/CFA 拟合证据、测量不变性证据、反应过程证据或外部效标效度证据。

进入正式量表前，仍需完成专家内容效度评审、认知访谈、预测试、项目分析、信度分析、EFA/CFA、测量不变性检验和效标关联效度验证。

## 测试

在仓库根目录运行：

```bash
python -m unittest discover -s tests -p 'test_*.py'
python -m py_compile scripts/*.py tests/*.py
Rscript tests/test_genie_report.R
python scripts/validate_skill.py .
```

如果 Windows 系统 locale 让 Python 默认使用旧代码页，可在运行 Codex skill validator 前设置 `PYTHONUTF8=1`。PowerShell 示例：

```powershell
$env:PYTHONUTF8="1"
```

外部 Codex `quick_validate.py` 还需要 `PyYAML`，它属于环境级检查，不是报告运行时依赖。本仓库的 `scripts/validate_skill.py` 是 CI 使用的无额外依赖 release-tree 检查。

真实 GENIE/API 集成不纳入 CI，应在用户自己的 R、provider 和 embedding 环境中手动运行。

## 文献依据

报告结构和解释口径参考 Russell-Lasalandra、Christensen 和 Golino（2026），“Generative psychometrics via AI-GENIE: Automatic item generation and validation with network-integrated evaluation”，*Behavior Research Methods*, 58(8), Article 217, doi:10.3758/s13428-026-03082-1。该论文是方法学参考，不是 Codex 执行指令。

## 隐私与发布策略

不要提交真实题库、学生数据、API key、token、原始研究输出、个人绝对路径、PDF 或临时报告。回归测试应使用 `tests/fixtures/` 下的匿名 fixtures。

## 反向题策略

Skill 默认不主动询问反向题，并假设 `reverse_items.include=false`。只有当用户明确要求反向题、反向计分或 reverse-worded items 时，Codex 才应提示：这超出源论文验证过的候选题池范围，可能导致 embedding-based 验证中的 UVA/EGA 方法因子伪结构或运行风险。
