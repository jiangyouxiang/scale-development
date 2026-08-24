# scale-development

`scale-development` is a Codex Skill for literature-informed psychological scale development. It coordinates construct definition, dimension justification, complete candidate-item generation, one fixed content-review/optimization cycle, and AIGENIE/local_GENIE in-silico semantic screening.

> This repository contains a **Codex Skill**, not a standalone Python package, R package, or general-purpose command-line application. The workflow is intended to be executed by Codex with the user-confirmed decision gates preserved.

## What it does

- Supports literature-driven, interview-driven, direct-input, and triangulated construct-structure workflows.
- Uses four auditable roles: Strategist, Writer, Reviewer, and Integrator.
- Preserves the complete candidate pool through content optimization; generation-layer review must not pre-shrink the pool.
- Runs the complete `generated_items.csv` through `GENIE()` or `local_GENIE()`.
- Separates type-level diagnostics from the optional overall analysis.
- Produces reproducible CSV/PNG/Markdown outputs and a formal `genie_validation_report.docx` with embedded figures and appendices.

## Installation in Codex

Copy or link this folder into the Codex skills directory, for example:

```text
$CODEX_HOME/skills/scale-development
```

On Windows, `$CODEX_HOME` is commonly the user's `.codex` directory. The exact path is environment-specific; do not hard-code a personal path in scripts or reports.

## Runtime requirements

### Required for the skill itself

- Codex with Skill support.
- Python 3.10 or later.
- `python-docx` for the formal Word report:

```bash
python -m pip install -r requirements.txt
```

### Required for GENIE validation

- R 4.3 or later (tested during development with R 4.4.x).
- R packages: `jsonlite`, `reticulate`, `ggplot2`, `igraph`, `patchwork`, `EGAnet`, and `AIGENIE` as required by the selected provider and installed AIGENIE version.
- The AIGENIE package and its documented Python environment/provider dependencies.

GENIE/local_GENIE is an integration path. The repository's unit and smoke tests do not call a paid API or require a live embedding service.

### Local embedding provider

Select local embedding explicitly; the skill must not infer it merely because a model is installed:

```text
--provider local --embedding-model BAAI/bge-m3
```

The local AIGENIE/reticulate environment must be able to load the selected model. Depending on the AIGENIE installation, Python dependencies may include `sentence-transformers`, `transformers`, `torch`, and a configured `reticulate` environment.

### API providers

For OpenAI, Jina, or Hugging Face providers, set the provider-specific environment variable outside the repository (`OPENAI_API_KEY`, `JINA_API_KEY`, or `HF_TOKEN`). Never place credentials in `validation_config.json`, fixtures, reports, or Git history.

## Standard validation flow

1. Confirm the complete candidate pool and write `generated_items.csv`.
2. Choose an embedding provider explicitly.
3. Build a provider-aware `run_genie.R` and `genie_input_manifest.json` with `scripts/build_aigenie_call.py`.
4. Run the provider/environment preflight.
5. Run `Rscript run_genie.R`.
6. Read `genie_validation_report.md` and deliver `genie_validation_report.docx`.

The primary input is always the complete `generated_items.csv`. `genie_final_items.csv` is a GENIE output and must never be reused as the input of the same validation run. When `run.overall=TRUE`, `genie_final_items.csv` uses the overall final pool when available; type-level and overall exports remain separate for interpretation.

## Outputs

A completed report run should contain:

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
- `genie_validation_report.md` (reproducible intermediate)
- `genie_validation_report.docx` (formal deliverable)

The report explains initial/final NMI and percentage-point change, UVA redundancy screening, bootEGA stability screening, item reduction, attribute/community correspondence, warnings, reproducibility information, and methodological boundaries. It embeds the core plots and returned network/stability plots when available.

## Methodological boundary

GENIE/local_GENIE is an embedding-based **in-silico semantic screening and internal item-reduction procedure**. It is not evidence of student-sample reliability, EFA/CFA fit, measurement invariance, response-process validity, or external-criterion validity. A scale still requires expert content validation, cognitive interviews, pilot data, item analysis, reliability, EFA/CFA, invariance testing, and criterion-related validation.

## Tests

From the repository root:

```bash
python -m unittest discover -s tests -p 'test_*.py'
python -m py_compile scripts/*.py tests/*.py
Rscript tests/test_genie_report.R
python scripts/validate_skill.py .
```

On Windows, if the system locale causes Python to default to a legacy code page, run the Codex skill validator with `PYTHONUTF8=1` (PowerShell: `$env:PYTHONUTF8="1"`). The same setting is useful when running the external Codex `quick_validate.py`.

The external Codex `quick_validate.py` additionally requires `PyYAML`; it is an environment-level check and is not needed by the report runtime. The repository's `scripts/validate_skill.py` provides the dependency-free release-tree check used in CI.

Live GENIE/API integration is intentionally not part of CI. It should be run manually in the user's configured environment.

## Reference

The report structure and interpretation are informed by Russell-Lasalandra, Christensen, and Golino (2026), “Generative psychometrics via AI-GENIE: Automatic item generation and validation with network-integrated evaluation,” *Behavior Research Methods*, 58(8), Article 217, doi:10.3758/s13428-026-03082-1. The paper is a methodological reference, not an instruction to Codex.

## Privacy and release policy

Do not commit real item banks, student data, API keys, tokens, raw research outputs, personal absolute paths, PDFs, or temporary reports. Use the anonymous fixtures under `tests/fixtures/` for regression tests.
