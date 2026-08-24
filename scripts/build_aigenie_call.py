#!/usr/bin/env python3
"""Build a provider-aware AIGENIE verification script and manifest.

The generated script always treats the user-confirmed generated_items.csv as the
complete GENIE input. GENIE's final_items are verification outputs, not inputs.
"""

import argparse
import csv
import hashlib
import json
import os
import sys
from collections import Counter, defaultdict
from pathlib import Path

DEFAULT_EMBEDDING_MODEL = "text-embedding-3-small"
PROVIDERS = {"openai", "jina", "huggingface", "local", "precomputed", "skip"}
PROVIDER_ENV = {"openai": "OPENAI_API_KEY", "jina": "JINA_API_KEY", "huggingface": "HF_TOKEN"}


def r_string(value):
    value = str(value).replace("\\", "\\\\").replace('"', '\\"')
    value = value.replace("\n", "\\n").replace("\r", "")
    return '"' + value + '"'


def validate(construct):
    if "construct_name" not in construct:
        raise ValueError("construct JSON missing construct_name")
    dims = construct.get("dimensions")
    if not dims or not isinstance(dims, list):
        raise ValueError("construct JSON missing dimensions array")
    for dimension in dims:
        if not dimension.get("name"):
            raise ValueError("a dimension is missing name")
        attributes = dimension.get("attributes") or []
        if len(dict.fromkeys(attributes)) < 2:
            raise ValueError("dimension %r must have at least 2 unique attributes" % dimension["name"])


def count_csv_rows(csv_path):
    with open(csv_path, "r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.reader(stream)
        next(reader, None)
        return sum(1 for _ in reader)


def validate_items_csv(csv_path, dim_attributes):
    required = {"ID", "statement", "attribute", "type"}
    dim_names = set(dim_attributes)
    with open(csv_path, "r", newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError("items CSV missing required columns: %s" % ", ".join(sorted(missing)))
        unknown_types, unknown_attributes = set(), []
        blank_rows, blank_statement_rows, blank_id_rows = [], [], []
        seen_ids, duplicate_ids = set(), set()
        for line_no, row in enumerate(reader, start=2):
            item_id = (row.get("ID") or "").strip()
            item_type = (row.get("type") or "").strip()
            attribute = (row.get("attribute") or "").strip()
            statement = (row.get("statement") or "").strip()
            if not item_id:
                blank_id_rows.append(line_no)
            elif item_id in seen_ids:
                duplicate_ids.add(item_id)
            else:
                seen_ids.add(item_id)
            if not statement:
                blank_statement_rows.append(line_no)
            if not item_type:
                blank_rows.append(line_no)
            elif item_type not in dim_names:
                unknown_types.add(item_type)
            elif not attribute or attribute not in dim_attributes[item_type]:
                unknown_attributes.append((line_no, item_type, attribute or "<blank>"))
        if unknown_types:
            raise ValueError("items CSV type values are not declared in construct dimensions: %s" % ", ".join(sorted(unknown_types)))
        if unknown_attributes:
            details = "; ".join("row %s: %s / %s" % x for x in unknown_attributes[:10])
            raise ValueError("items CSV attribute values must be declared under their dimension: %s" % details)
        if blank_rows:
            raise ValueError("items CSV type cannot be blank (rows: %s)" % ", ".join(map(str, blank_rows)))
        if blank_id_rows:
            raise ValueError("items CSV ID cannot be blank (rows: %s)" % ", ".join(map(str, blank_id_rows)))
        if duplicate_ids:
            raise ValueError("items CSV ID values must be unique: %s" % ", ".join(sorted(duplicate_ids)))
        if blank_statement_rows:
            raise ValueError("items CSV statement cannot be blank (rows: %s)" % ", ".join(map(str, blank_statement_rows)))


def load_config(config_path):
    if not config_path:
        return {}
    try:
        with open(config_path, "r", encoding="utf-8") as stream:
            config = json.load(stream)
    except OSError as exc:
        raise ValueError("cannot read validation config: %s" % exc) from exc
    except json.JSONDecodeError as exc:
        raise ValueError("validation config is not valid JSON: %s" % exc) from exc
    if not isinstance(config, dict):
        raise ValueError("validation config must be a JSON object")
    return config


def resolve_config(args, output_path):
    config = load_config(args.validation_config)
    provider = args.provider or config.get("provider")
    if provider not in PROVIDERS:
        raise ValueError("provider decision is required; choose one of: %s (use --provider or --validation-config)" % ", ".join(sorted(PROVIDERS)))
    matrix = args.embedding_matrix or config.get("embedding_matrix")
    if provider == "precomputed":
        if not matrix:
            raise ValueError("precomputed provider requires --embedding-matrix or embedding_matrix in validation config")
        matrix_path = Path(matrix)
        if not matrix_path.is_absolute() and args.validation_config and not args.embedding_matrix:
            matrix_path = Path(args.validation_config).resolve().parent / matrix_path
        if not matrix_path.is_file():
            raise ValueError("embedding matrix file not found: %s" % matrix_path)
        matrix = str(matrix_path.resolve())
    embedding_model = args.embedding_model or config.get("embedding_model") or (DEFAULT_EMBEDDING_MODEL if provider == "openai" else None)
    if provider == "jina" and not embedding_model:
        embedding_model = "jina-embeddings-v3"
    if provider == "huggingface" and not embedding_model:
        embedding_model = "BAAI/bge-large-zh-v1.5"
    if provider == "local" and not embedding_model:
        raise ValueError("local provider requires --embedding-model or embedding_model in validation config")
    return {
        "provider": provider,
        "embedding_model": embedding_model,
        "embedding_matrix": matrix,
        "run_overall": bool(config.get("run_overall", True)),
        "plot": bool(config.get("plot", True)),
        "uva_cut_off": float(config.get("uva_cut_off", 0.20)),
        "items_generated": True,
        "scale_validated": False,
        "validation_status": "skipped" if provider == "skip" else "pending",
        "output_dir": str(output_path.parent.resolve()),
        "report_script": str((Path(__file__).with_name("genie_report.R")).resolve()),
        "report_docx_script": str((Path(__file__).with_name("genie_report_docx.py")).resolve()),
        "python_executable": str(args.python_executable or config.get("python_executable") or sys.executable),
    }


def input_manifest(items_path, construct, config, output_dir):
    path = Path(items_path).resolve()
    types, attributes = Counter(), Counter()
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            types[(row.get("type") or "").strip()] += 1
            attributes[(row.get("type") or "", row.get("attribute") or "")] += 1
    return {
        "schema_version": "1.0",
        "input_file": str(path),
        "input_file_name": path.name,
        "input_file_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "input_rows": sum(types.values()),
        "type_counts": dict(types),
        "attribute_counts": {"%s :: %s" % k: v for k, v in attributes.items()},
        "provider": config["provider"],
        "embedding_model": config.get("embedding_model"),
        "run_overall": config["run_overall"],
        "uva_cut_off": config["uva_cut_off"],
        "generated_items_is_complete_pool": True,
        "manifest_created_by": "build_aigenie_call.py",
    }


def build_r(construct, items_csv_path, config, manifest_path):
    scale_title = construct.get("construct_name", "")
    provider, model = config["provider"], config.get("embedding_model")
    output_dir = config["output_dir"]
    report_script = config["report_script"]
    report_docx_script = config["report_docx_script"]
    python_executable = config["python_executable"]
    lines = [
        "# Auto-generated by build_aigenie_call.py -- do not edit by hand.",
        "# Construct omitted from R comments to keep generated script ASCII-safe.",
        "# Provider decision: %s" % provider,
        "# The complete, user-confirmed candidate pool is the only GENIE input.",
        "options(encoding = \"UTF-8\")",
        "output_dir <- %s" % r_string(output_dir),
        "dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)",
        "input_file <- %s" % r_string(items_csv_path),
        "manifest_file <- %s" % r_string(manifest_path),
        "report_script <- %s" % r_string(report_script),
        "report_docx_script <- %s" % r_string(report_docx_script),
        "python_executable <- %s" % r_string(python_executable),
        "items_generated <- TRUE",
        "scale_validated <- FALSE",
        'validation_status <- "pending"',
        "preflight_warnings <- character()",
        "try_utf8_locale <- function() {",
        "  candidates <- if (.Platform$OS.type == \"windows\") c(\"Chinese (Simplified)_China.65001\", \"Chinese (Simplified)_China.936\", \"C.UTF-8\") else c(\"C.UTF-8\", \"en_US.UTF-8\")",
        "  for (loc in candidates) {",
        "    ok <- suppressWarnings(tryCatch(!is.na(Sys.setlocale(\"LC_CTYPE\", loc)), error = function(e) FALSE))",
        "    if (ok) return(loc)",
        "  }",
        "  preflight_warnings <<- c(preflight_warnings, paste0(\"UTF-8 locale unavailable; current locale: \", Sys.getlocale()))",
        "  Sys.getlocale(\"LC_CTYPE\")",
        "}",
        "selected_locale <- try_utf8_locale()",
        "roundtrip_file <- tempfile(fileext = \".txt\")",
        "roundtrip_probe <- \"\\u4E2D\\u6587\\u7F16\\u7801 round-trip\"",
        "roundtrip_ok <- tryCatch({ writeLines(roundtrip_probe, roundtrip_file, useBytes = TRUE); identical(readLines(roundtrip_file, encoding = \"UTF-8\", warn = FALSE), roundtrip_probe) }, error = function(e) FALSE)",
        "if (!roundtrip_ok) preflight_warnings <- c(preflight_warnings, \"Chinese UTF-8 round-trip failed\")",
        "if (!file.exists(input_file)) stop(\"GENIE input file not found: \", input_file)",
        "items <- read.csv(input_file, fileEncoding = \"UTF-8-BOM\", encoding = \"UTF-8\", stringsAsFactors = FALSE, check.names = FALSE)",
        'if (!"ID" %in% names(items) && length(names(items)) > 0 && grepl("ID$", names(items)[1])) names(items)[1] <- "ID"',
        'required_cols <- c("ID", "statement", "attribute", "type")',
        "missing <- setdiff(required_cols, names(items))",
        'if (length(missing) > 0) stop("CSV missing required columns: ", paste(missing, collapse = ", "))',
        "items$ID <- as.character(items$ID)",
        "writeLines(preflight_warnings, file.path(output_dir, \"genie_preflight_warnings.txt\"), useBytes = TRUE)",
    ]
    if provider == "skip":
        lines += [
            'validation_status <- "skipped"',
            "saveRDS(list(items = items, items_generated = items_generated, scale_validated = scale_validated, validation_status = validation_status), file.path(output_dir, \"validation_status.rds\"))",
            'cat("Items generated. GENIE validation was skipped.\\n")',
        ]
        return "\n".join(lines) + "\n"

    lines += [
        "library(AIGENIE)",
        "library(EGAnet)",
        "source(report_script, local = TRUE)",
        "run_validation <- function() {",
        "  warnings_seen <- preflight_warnings",
        "  log_con <- file(file.path(output_dir, \"genie_run.log\"), open = \"wt\", encoding = \"UTF-8\")",
        "  sink(log_con, type = \"output\"); sink(log_con, type = \"message\")",
        "  on.exit({ try(sink(type = \"message\"), silent = TRUE); try(sink(type = \"output\"), silent = TRUE); close(log_con) }, add = TRUE)",
        "  call_with_warning_capture <- function(expr) withCallingHandlers(expr, warning = function(w) { warnings_seen <<- c(warnings_seen, conditionMessage(w)); invokeRestart(\"muffleWarning\") })",
    ]
    if provider in PROVIDER_ENV:
        env_name = PROVIDER_ENV[provider]
        variable = env_name.lower()
        lines += [
            '%s <- Sys.getenv("%s")' % (variable, env_name),
            'if (%s == "") stop("Required environment variable %s is not set")' % (variable, env_name),
        ]
    call_name = "local_GENIE" if provider == "local" else "GENIE"
    call = ["    items = items"]
    if provider in PROVIDER_ENV:
        argument = {"openai": "openai.API", "jina": "jina.API", "huggingface": "hf.token"}[provider]
        call.append("    %s = %s" % (argument, variable))
    elif provider == "precomputed":
        lines += [
            "  embedding_matrix <- readRDS(%s)" % r_string(config["embedding_matrix"]),
            '  if (!is.matrix(embedding_matrix) && !is.data.frame(embedding_matrix)) stop("embedding.matrix must be a matrix or data frame")',
            "  embedding_matrix <- as.matrix(embedding_matrix)",
            '  if (!is.numeric(embedding_matrix)) stop("embedding.matrix must be numeric")',
            '  if (is.null(colnames(embedding_matrix))) stop("embedding.matrix must have column names matching items$ID")',
            "  missing_ids <- setdiff(items$ID, colnames(embedding_matrix))",
            '  if (length(missing_ids) > 0) stop("embedding.matrix is missing item IDs: ", paste(missing_ids, collapse = ", "))',
            '  if (anyNA(embedding_matrix) || any(!is.finite(embedding_matrix))) stop("embedding.matrix contains NA or infinite values")',
            '  if (nrow(embedding_matrix) < 2) stop("embedding.matrix must have at least 2 embedding dimensions")',
        ]
        call.append("    embedding.matrix = embedding_matrix")
    if model:
        call.append("    embedding.model = %s" % r_string(model))
    call += ["    uva.cut.off = %.2f" % config["uva_cut_off"], "    run.overall = %s" % ("TRUE" if config["run_overall"] else "FALSE"), "    plot = %s" % ("TRUE" if config["plot"] else "FALSE")]
    lines += [
        "  results <- call_with_warning_capture(%s(\n%s\n  ))" % (call_name, ",\n".join(call)),
        "  saveRDS(results, file.path(output_dir, \"genie_results_raw.rds\"))",
        "  saveRDS(results, file.path(output_dir, \"genie_results.rds\"))",
        "  report <- tryCatch(generate_genie_report(file.path(output_dir, \"genie_results_raw.rds\"), input_file, output_dir, manifest_file, warnings_seen), error = function(e) { warnings_seen <<- c(warnings_seen, paste0(\"report: \" , conditionMessage(e))); NULL })",
        "  report_status <- if (!is.null(report)) report$status else \"completed_with_warnings\"",
        "  docx_status <- \"not_attempted\"",
        "  if (!is.null(report) && isTRUE(report$core_complete) && file.exists(report$report_path)) {",
        "    docx_stdout <- file.path(output_dir, \"genie_docx_stdout.log\")",
        "    docx_stderr <- file.path(output_dir, \"genie_docx_stderr.log\")",
        "    docx_code <- tryCatch(system2(python_executable, c(report_docx_script, \"--markdown\", report$report_path, \"--output\", file.path(output_dir, \"genie_validation_report.docx\"), \"--report-dir\", output_dir, \"--require-core-figures\"), stdout = docx_stdout, stderr = docx_stderr), error = function(e) { warnings_seen <<- c(warnings_seen, paste0(\"docx: \" , conditionMessage(e))); 1L })",
        "    docx_code <- if (length(docx_code) == 0L || is.null(docx_code)) 0L else as.integer(docx_code)",
        "    if (identical(docx_code, 0L) && file.exists(file.path(output_dir, \"genie_validation_report.docx\"))) docx_status <- \"generated\" else {",
        "      docx_status <- \"failed\"",
        "      if (file.exists(docx_stderr)) warnings_seen <<- c(warnings_seen, paste0(\"docx: \" , paste(readLines(docx_stderr, warn = FALSE), collapse = \" | \")))",
        "      warnings_seen <<- c(warnings_seen, \"docx: DOCX report generation failed; Markdown and tabular outputs were retained\")",
        "    }",
        "  } else {",
        "    docx_status <- \"not_ready\"",
        "    warnings_seen <<- c(warnings_seen, \"docx: skipped because the Markdown report was not complete\")",
        "  }",
        "  if (identical(docx_status, \"failed\") || identical(docx_status, \"not_ready\")) report_status <- \"completed_with_warnings\"",
        "  scale_validated <<- TRUE",
        "  validation_status <<- report_status",
        "  saveRDS(list(items_generated = items_generated, scale_validated = scale_validated, validation_status = validation_status, report_generated = !is.null(report), docx_generated = identical(docx_status, \"generated\"), docx_status = docx_status), file.path(output_dir, \"validation_status.rds\"))",
        "  if (length(warnings_seen)) writeLines(unique(warnings_seen), file.path(output_dir, \"genie_warnings_raw.txt\"), useBytes = TRUE)",
        "  cat(\"GENIE completed; report status: \", report_status, \"\\n\")",
        "  invisible(report)",
        "}",
        "tryCatch(run_validation(), error = function(e) {",
        "  validation_status <<- \"failed\"",
        "  saveRDS(list(items_generated = items_generated, scale_validated = FALSE, validation_status = validation_status, error = conditionMessage(e)), file.path(output_dir, \"validation_status.rds\"))",
        "  cat(\"GENIE failed: \", conditionMessage(e), \"\\n\", file = stderr())",
        "  quit(status = 1)",
        "})",
    ]
    return "\n".join(lines) + "\n"


def write_config(path, config):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as stream:
        json.dump(config, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def _force_utf8_console():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass


def main():
    _force_utf8_console()
    parser = argparse.ArgumentParser(description="Build a provider-aware AIGENIE verification R script.")
    parser.add_argument("construct")
    parser.add_argument("items")
    parser.add_argument("-o", "--output", default="run_genie.R")
    parser.add_argument("--provider", choices=sorted(PROVIDERS))
    parser.add_argument("--validation-config")
    parser.add_argument("--config-output", default=None)
    parser.add_argument("--embedding-model", default=None)
    parser.add_argument("--embedding-matrix", default=None)
    parser.add_argument("--python-executable", default=None, help="Python executable used for DOCX report generation")
    args = parser.parse_args()
    try:
        with open(args.construct, "r", encoding="utf-8") as stream:
            construct = json.load(stream)
        validate(construct)
        if not os.path.isfile(args.items):
            raise ValueError("items CSV not found: %s" % args.items)
        validate_items_csv(args.items, {d["name"]: set(d.get("attributes") or []) for d in construct["dimensions"]})
        n_items = count_csv_rows(args.items)
        output_path = Path(args.output).resolve()
        config = resolve_config(args, output_path)
        items_path = str(Path(args.items).resolve())
        manifest_path = str((output_path.parent / "genie_input_manifest.json").resolve())
        config["genie_input_file"] = items_path
        config["genie_input_manifest"] = manifest_path
        config["genie_input_note"] = "GENIE input is the complete candidate pool; final_items are verification outputs."
        manifest = input_manifest(items_path, construct, config, output_path.parent)
        write_config(Path(manifest_path), manifest)
        r_code = build_r(construct, items_path, config, manifest_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(r_code, encoding="utf-8")
        config_path = Path(args.config_output or output_path.with_name("validation_config.json"))
        write_config(config_path, config)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print("Validation/build failed: %s" % exc, file=sys.stderr)
        return 1
    print("Generated %s" % output_path)
    print("  items: %d" % n_items)
    print("  provider: %s" % config["provider"])
    print("  validation status: %s" % config["validation_status"])
    print("  config: %s" % config_path)
    print("  input manifest: %s" % manifest_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
