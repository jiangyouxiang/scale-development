# Smoke test for genie_report.R post-processing.
# Uses ASCII <U+....> literals so it runs even in Windows C locale.

all_args <- commandArgs()
file_arg <- grep("^--file=", all_args, value = TRUE)
script_path <- if (length(file_arg)) normalizePath(sub("^--file=", "", file_arg[[1]]), mustWork = FALSE) else normalizePath(file.path("tests", "test_genie_report.R"), mustWork = FALSE)
skill_root <- normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
source(file.path(skill_root, "scripts", "genie_report.R"), local = TRUE)

args <- commandArgs(trailingOnly = TRUE)
out <- if (length(args) >= 1) args[[1]] else file.path(tempdir(), "genie_report_smoke")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

items <- data.frame(
  ID = c("1", "2", "3", "4"),
  statement = c("<U+6211><U+77E5><U+9053>AI", "<U+6211><U+4F1A><U+4FDD><U+62A4><U+9690><U+79C1>", "<U+6211><U+4F1A><U+6838><U+9A8C><U+4FE1><U+606F>", "<U+6211><U+80FD><U+8D1F><U+8D23><U+4F7F><U+7528>"),
  attribute = c("<U+6982><U+5FF5>", "<U+9690><U+79C1>", "<U+5224><U+65AD>", "<U+8D23><U+4EFB>"),
  type = c("<U+7406><U+89E3>", "<U+7406><U+89E3>", "<U+5224><U+65AD>", "<U+4F26><U+7406>"),
  stringsAsFactors = FALSE
)
safe_write_csv(items, file.path(out, "input.csv"))

mk <- function(ids, type, attr, com) data.frame(
  ID = as.character(ids),
  statement = paste0("<U+6211>", ids),
  attribute = paste0("<U+", attr, ">"),
  type = paste0("<U+", type, ">"),
  EGA_com = com,
  stringsAsFactors = FALSE
)

type_result <- list(
  start_N = 2L, final_N = 1L, initial_NMI = .4, final_NMI = .7,
  EGA.model_selected = "TMFG",
  UVA = list(n_removed = 0L, n_sweeps = 0, redundant_pairs = data.frame()),
  bootEGA = list(n_removed = 1L, items_removed = mk("2", "7406", "5B89", 1)),
  final_items = mk("1", "7406", "6982", 1),
  network_plot = NULL, stability_plot = NULL
)
overall_result <- list(
  start_N = 4L, final_N = 2L, initial_NMI = .5, final_NMI = .6,
  EGA.model_selected = "glasso",
  UVA = list(n_removed = 1L, n_sweeps = 1, redundant_pairs = data.frame(items = "<U+6211>", keep = "<U+4FDD>", remove = "<U+9664>")),
  bootEGA = list(n_removed = 1L, items_removed = mk("4", "4F26", "8D23", 2)),
  final_items = rbind(mk("1", "7406", "6982", 1), mk("3", "5224", "4FE1", 2)),
  network_plot = NULL, stability_plot = NULL
)
res <- list(item_type_level = list(`<U+7406><U+89E3>` = type_result), overall = overall_result)
raw <- file.path(out, "genie_results_raw.rds")
saveRDS(res, raw)
manifest <- file.path(out, "manifest.json")
writeLines('{"provider":"local","embedding_model":"BAAI/bge-m3","input_rows":4,"run_overall":true,"uva_cut_off":0.2}', manifest, useBytes = TRUE)

ans <- generate_genie_report(raw, file.path(out, "input.csv"), out, manifest, c("Setting LC_CTYPE=C.UTF-8 failed"))
stopifnot(ans$core_complete)
for (f in c("genie_metrics_summary.csv", "genie_final_items.csv", "genie_type_level_final_items.csv", "genie_overall_final_items.csv", "genie_validation_report.md")) stopifnot(file.exists(file.path(out, f)))
report <- readLines(file.path(out, "genie_validation_report.md"), encoding = "UTF-8", warn = FALSE)
stopifnot(!any(grepl("<U\\+", report)))
stopifnot(any(grepl(decode_unicode_escapes("<U+5B8C><U+6574> 4 <U+9053><U+5019><U+9009><U+9898><U+8FDB><U+5165>"), report, fixed = TRUE)))
primary_lines <- readLines(file.path(out, "genie_final_items.csv"), encoding = "UTF-8", warn = FALSE)
type_lines <- readLines(file.path(out, "genie_type_level_final_items.csv"), encoding = "UTF-8", warn = FALSE)
stopifnot(length(primary_lines) == 3L, length(type_lines) == 2L)

manifest_without_rows <- file.path(out, "manifest_without_rows.json")
writeLines('{"provider":"local","embedding_model":"BAAI/bge-m3","run_overall":true,"uva_cut_off":0.2}', manifest_without_rows, useBytes = TRUE)
fallback_out <- file.path(out, "fallback_count")
dir.create(fallback_out, recursive = TRUE, showWarnings = FALSE)
ans2 <- generate_genie_report(raw, file.path(out, "input.csv"), fallback_out, manifest_without_rows, character())
stopifnot(ans2$core_complete)
report2 <- readLines(file.path(fallback_out, "genie_validation_report.md"), encoding = "UTF-8", warn = FALSE)
stopifnot(any(grepl(decode_unicode_escapes("<U+5B8C><U+6574> 4 <U+9053><U+5019><U+9009><U+9898><U+8FDB><U+5165>"), report2, fixed = TRUE)))

raw_no_overall <- file.path(out, "genie_results_no_overall.rds")
raw_no_overall_obj <- res
raw_no_overall_obj$overall <- NULL
saveRDS(raw_no_overall_obj, raw_no_overall)
no_overall_out <- file.path(out, "no_overall")
dir.create(no_overall_out, recursive = TRUE, showWarnings = FALSE)
ans3 <- generate_genie_report(raw_no_overall, file.path(out, "input.csv"), no_overall_out, manifest, character())
stopifnot(ans3$core_complete)
stopifnot(file.exists(file.path(no_overall_out, "genie_overall_final_items.csv")))
primary_no_overall <- readLines(file.path(no_overall_out, "genie_final_items.csv"), encoding = "UTF-8", warn = FALSE)
type_no_overall <- readLines(file.path(no_overall_out, "genie_type_level_final_items.csv"), encoding = "UTF-8", warn = FALSE)
stopifnot(identical(primary_no_overall, type_no_overall))


empty_raw <- file.path(out, "empty_results.rds")
saveRDS(list(item_type_level = list()), empty_raw)
empty_out <- file.path(out, "empty_results")
dir.create(empty_out, recursive = TRUE, showWarnings = FALSE)
ans4 <- generate_genie_report(empty_raw, file.path(out, "input.csv"), empty_out, manifest, character())
stopifnot(ans4$core_complete)

cat("genie_report smoke OK: ", out, "\n", sep = "")
