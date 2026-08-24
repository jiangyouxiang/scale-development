# Standard AIGENIE/local_GENIE post-processing and reporting.
# This file is sourced by generated run_genie.R and can also be called directly.

.decode_one <- function(x) {
  if (is.na(x) || !grepl("<U\\+[0-9A-Fa-f]{4,6}>", x, perl = TRUE)) return(x)
  hits <- regmatches(x, gregexpr("<U\\+[0-9A-Fa-f]{4,6}>", x, perl = TRUE))[[1]]
  if (length(hits) == 0 || identical(hits, character(0))) return(x)
  repl <- vapply(hits, function(h) {
    cp <- suppressWarnings(strtoi(gsub("^<U\\+|>$", "", h, perl = TRUE), base = 16L))
    if (is.na(cp)) h else intToUtf8(cp)
  }, character(1), USE.NAMES = FALSE)
  regmatches(x, gregexpr("<U\\+[0-9A-Fa-f]{4,6}>", x, perl = TRUE)) <- list(repl)
  enc2utf8(x)
}

decode_unicode_escapes <- function(x) {
  if (is.character(x)) return(vapply(x, .decode_one, character(1), USE.NAMES = FALSE))
  x
}

decode_names <- function(x) {
  if (is.null(x)) return(x)
  n <- names(x)
  if (!is.null(n)) names(x) <- decode_unicode_escapes(n)
  x
}

decode_df <- function(df) {
  if (is.null(df)) return(NULL)
  if (!is.data.frame(df)) return(df)
  names(df) <- decode_unicode_escapes(names(df))
  for (j in seq_along(df)) if (is.character(df[[j]])) df[[j]] <- decode_unicode_escapes(df[[j]])
  df
}

as_num <- function(x, default = NA_real_) {
  if (length(x) == 0 || is.null(x) || is.na(x[[1]])) return(default)
  y <- suppressWarnings(as.numeric(x[[1]]))
  ifelse(is.finite(y), y, default)
}

as_int <- function(x, default = NA_integer_) {
  y <- as_num(x, NA_real_)
  if (is.na(y)) default else as.integer(y)
}

safe_nrow <- function(x) if (is.null(x)) 0L else if (is.data.frame(x) || is.matrix(x)) nrow(x) else 0L

read_json_safely <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE)) return(list())
  tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
}

count_csv_data_rows <- function(path) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) return(NA_integer_)
  size <- file.info(path)$size
  if (is.na(size) || size <= 0) return(0L)
  raw <- readBin(path, what = "raw", n = size)
  if (!length(raw)) return(0L)
  n_lines <- sum(raw == as.raw(10))
  if (!identical(raw[[length(raw)]], as.raw(10))) n_lines <- n_lines + 1L
  max(0L, as.integer(n_lines - 1L))
}

rbind_fill <- function(parts) {
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (!length(parts)) return(data.frame(stringsAsFactors = FALSE))
  cols <- unique(unlist(lapply(parts, names)))
  parts <- lapply(parts, function(d) {
    d <- as.data.frame(d, stringsAsFactors = FALSE)
    for (nm in setdiff(cols, names(d))) d[[nm]] <- rep(NA_character_, nrow(d))
    d[cols]
  })
  do.call(rbind, parts)
}

safe_write_csv <- function(df, path) {
  if (is.null(df)) df <- data.frame(stringsAsFactors = FALSE)
  df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), con)
  if (!ncol(df)) return(invisible(path))
  csv_escape <- function(x) {
    x <- as.character(x)
    x[is.na(x)] <- ""
    x <- enc2utf8(x)
    paste0('"', gsub('"', '""', x, fixed = TRUE), '"')
  }
  lines <- c(
    paste(vapply(names(df), csv_escape, character(1)), collapse = ","),
    if (nrow(df)) apply(df, 1, function(r) paste(vapply(r, csv_escape, character(1)), collapse = ",")) else character()
  )
  writeBin(charToRaw(enc2utf8(paste0(paste(lines, collapse = "\r\n"), "\r\n"))), con)
  invisible(path)
}

warning_category <- function(message) {
  m <- tolower(message)
  if (grepl("lc_|locale|c\\.utf-8|setting lc", m, perl = TRUE)) return("locale")
  if (grepl("<u\\+|unicode|encoding|utf-8|utf8", m, perl = TRUE)) return("encoding")
  if (grepl("python|reticulate|package|namespace|aigenie|eganet", m, perl = TRUE)) return("dependency")
  if (grepl("converg|singular|failed|error|nan|infinite|bootstrap|bootega|uva", m, perl = TRUE)) return("computation")
  "other"
}

collect_warnings <- function(warnings = character(), output_dir = ".") {
  raw <- as.character(warnings %||% character())
  preflight <- file.path(output_dir, "genie_preflight_warnings.txt")
  if (file.exists(preflight)) raw <- c(raw, readLines(preflight, encoding = "UTF-8", warn = FALSE))
  log_file <- file.path(output_dir, "genie_run.log")
  if (file.exists(log_file)) {
    log_lines <- readLines(log_file, encoding = "UTF-8", warn = FALSE)
    log_lines <- log_lines[grepl("Warning|warning|Setting LC_|failed", log_lines)]
    raw <- c(raw, log_lines)
  }
  raw <- decode_unicode_escapes(raw)
  raw <- trimws(raw[nzchar(trimws(raw))])
  raw <- unique(raw)
  if (!length(raw)) return(data.frame(warning_id = integer(), category = character(), message = character(), stringsAsFactors = FALSE))
  data.frame(warning_id = seq_along(raw), category = vapply(raw, warning_category, character(1)), message = raw, stringsAsFactors = FALSE)
}

extract_level <- function(result, level, type_label, warnings_df) {
  final_items <- decode_df(result$final_items)
  start_n <- as_int(result$start_N, safe_nrow(final_items))
  final_n <- as_int(result$final_N, safe_nrow(final_items))
  if (is.na(final_n)) final_n <- safe_nrow(final_items)
  if (is.na(start_n) || start_n < final_n) start_n <- final_n
  uva <- result$UVA %||% list()
  boot <- result$bootEGA %||% list()
  uva_removed <- as_int(uva$n_removed, 0L)
  boot_removed <- as_int(boot$n_removed, 0L)
  redundant <- decode_df(uva$redundant_pairs)
  if (!is.null(redundant) && nrow(redundant)) {
    redundant$level <- level; redundant$type <- type_label
  }
  removed <- decode_df(boot$items_removed)
  if (!is.null(removed) && nrow(removed)) {
    removed$stage <- "bootEGA"; removed$level <- level; removed$type <- type_label
  }
  if (!is.null(final_items) && nrow(final_items)) {
    final_items$analysis_level <- level
    final_items$analysis_type <- type_label
    if ("type" %in% names(final_items) && !is.null(type_label)) final_items$type <- type_label
  }
  list(
    metrics = data.frame(
      level = level, type = type_label, start_N = start_n, final_N = final_n,
      removed_N = max(0L, start_n - final_n), removed_rate = if (start_n > 0) (start_n - final_n) / start_n else NA_real_,
      EGA_model = as.character(result$EGA.model_selected %||% NA_character_),
      initial_NMI_raw = as_num(result$initial_NMI), final_NMI_raw = as_num(result$final_NMI),
      delta_NMI_pp = (as_num(result$final_NMI) - as_num(result$initial_NMI)) * 100,
      UVA_removed = uva_removed, UVA_sweeps = as_num(uva$n_sweeps, 0),
      bootEGA_removed = boot_removed, warning_count = nrow(warnings_df), stringsAsFactors = FALSE
    ),
    final_items = final_items, redundant = redundant, removed = removed
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

blank_png <- function(path, label) {
  grDevices::png(path, width = 1200, height = 800, res = 130)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::plot.new(); graphics::title(main = label)
}

save_plot <- function(plot_object, path, label, width = 9, height = 6) {
  ok <- FALSE
  if (!is.null(plot_object) && requireNamespace("ggplot2", quietly = TRUE)) {
    ok <- isTRUE(tryCatch({ ggplot2::ggsave(path, plot = plot_object, width = width, height = height, dpi = 160, limitsize = FALSE); TRUE }, error = function(e) FALSE))
  }
  if (!ok) blank_png(path, label)
  invisible(ok)
}

make_figures <- function(metrics, primary_items, results, output_dir) {
  fig_dir <- file.path(output_dir, "figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  if (requireNamespace("ggplot2", quietly = TRUE) && nrow(metrics)) {
    m <- metrics
    m$label <- ifelse(m$level == "overall", "overall", m$type)
    nmi <- rbind(
      data.frame(label = m$label, phase = "initial", value = m$initial_NMI_raw),
      data.frame(label = m$label, phase = "final", value = m$final_NMI_raw)
    )
    nmi <- nmi[is.finite(nmi$value), , drop = FALSE]
    p1 <- ggplot2::ggplot(nmi, ggplot2::aes(label, value, fill = phase)) + ggplot2::geom_col(position = "dodge") + ggplot2::coord_cartesian(ylim = c(0, 1)) + ggplot2::labs(x = NULL, y = "NMI", fill = NULL) + ggplot2::theme_minimal() + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1))
    save_plot(p1, file.path(fig_dir, "nmi_before_after.png"), "NMI before/after")
    p2 <- ggplot2::ggplot(m, ggplot2::aes(label, start_N, fill = "start")) + ggplot2::geom_col() + ggplot2::geom_col(ggplot2::aes(y = final_N, fill = "final"), width = .55) + ggplot2::labs(x = NULL, y = "Items", fill = NULL) + ggplot2::theme_minimal() + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1))
    save_plot(p2, file.path(fig_dir, "item_reduction_by_type.png"), "Item reduction")
    wf <- rbind(
      data.frame(label = m$label, stage = "UVA", count = m$UVA_removed),
      data.frame(label = m$label, stage = "bootEGA", count = m$bootEGA_removed),
      data.frame(label = m$label, stage = "remaining", count = m$final_N)
    )
    p3 <- ggplot2::ggplot(wf, ggplot2::aes(label, count, fill = stage)) + ggplot2::geom_col() + ggplot2::labs(x = NULL, y = "Items", fill = NULL) + ggplot2::theme_minimal() + ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 35, hjust = 1))
    save_plot(p3, file.path(fig_dir, "removal_waterfall.png"), "UVA/bootEGA item flow")
  } else {
    for (nm in c("nmi_before_after.png", "item_reduction_by_type.png", "removal_waterfall.png")) blank_png(file.path(fig_dir, nm), nm)
  }
  if (!is.null(primary_items) && nrow(primary_items) && all(c("attribute", "EGA_com") %in% names(primary_items)) && requireNamespace("ggplot2", quietly = TRUE)) {
    h <- as.data.frame(table(attribute = decode_unicode_escapes(as.character(primary_items$attribute)), EGA_com = as.character(primary_items$EGA_com)), stringsAsFactors = FALSE)
    h <- h[h$Freq > 0, , drop = FALSE]
    p4 <- ggplot2::ggplot(h, ggplot2::aes(EGA_com, attribute, fill = Freq)) + ggplot2::geom_tile() + ggplot2::scale_fill_continuous(type = "viridis") + ggplot2::labs(x = "EGA community", y = "Preset attribute", fill = "n") + ggplot2::theme_minimal()
    save_plot(p4, file.path(fig_dir, "attribute_community_heatmap.png"), "Attribute/community heatmap")
  } else blank_png(file.path(fig_dir, "attribute_community_heatmap.png"), "Attribute/community heatmap unavailable")
  if (!is.null(results)) {
    export_plot <- function(obj, name) {
      if (!is.null(obj)) save_plot(obj, file.path(fig_dir, paste0(name, ".png")), name, 12, 8)
    }
    for (nm in names(results$item_type_level %||% list())) {
      safe <- gsub("[^[:alnum:]_-]+", "_", decode_unicode_escapes(nm))
      z <- results$item_type_level[[nm]]
      export_plot(z$network_plot, paste0("network_", safe))
      export_plot(z$stability_plot, paste0("stability_", safe))
    }
    if (!is.null(results$overall)) {
      export_plot(results$overall$network_plot, "network_overall")
      export_plot(results$overall$stability_plot, "stability_overall")
    }
  }
  list(dir = fig_dir, files = list.files(fig_dir, pattern = "\\.png$", full.names = FALSE))
}

md_escape <- function(x) gsub("\\|", "\\\\|", as.character(x), perl = TRUE)
md_table <- function(df) {
  if (is.null(df) || !nrow(df)) return("\uFF08\u65E0\u8BB0\u5F55\uFF09")
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  hdr <- paste(names(df), collapse = " | ")
  sep <- paste(rep("---", ncol(df)), collapse = " | ")
  rows <- apply(df, 1, function(r) paste(md_escape(r), collapse = " | "))
  paste(c(paste0("| ", hdr, " |"), paste0("| ", sep, " |"), paste0("| ", rows, " |")), collapse = "\n")
}

risk_flags <- function(metrics, warnings_df, primary_items) {
  flags <- character()
  if (any(metrics$final_NMI_raw < .50, na.rm = TRUE)) flags <- c(flags, "\u81F3\u5C11\u4E00\u4E2A\u5206\u6790\u5C42\u9762\u7684 final_NMI < .50")
  if (any(metrics$delta_NMI_pp < 0, na.rm = TRUE)) flags <- c(flags, "\u81F3\u5C11\u4E00\u4E2A\u5206\u6790\u5C42\u9762\u7684 NMI \u589E\u76CA\u4E3A\u8D1F")
  if (any(metrics$final_N < 4, na.rm = TRUE)) flags <- c(flags, "\u81F3\u5C11\u4E00\u4E2A\u5206\u6790\u5C42\u9762\u7684\u6700\u7EC8\u9898\u91CF\u5C11\u4E8E 4 \u9898")
  if (any(metrics$removed_rate > .50, na.rm = TRUE)) flags <- c(flags, "\u81F3\u5C11\u4E00\u4E2A\u5206\u6790\u5C42\u9762\u7684\u5220\u9664\u7387\u8D85\u8FC7 50%")
  if (nrow(primary_items) && all(c("attribute", "EGA_com") %in% names(primary_items))) {
    tab <- table(primary_items$attribute, primary_items$EGA_com)
    purity <- sum(apply(tab, 2, max)) / sum(tab)
    if (is.finite(purity) && purity < .50) flags <- c(flags, sprintf("attribute/EGA community \u5BF9\u5E94\u7EAF\u5EA6\u504F\u4F4E\uFF08%.1f%%\uFF09", purity * 100))
  }
  if (nrow(warnings_df) && any(warnings_df$category != "locale")) flags <- c(flags, "\u5B58\u5728\u975E locale \u7C7B warning\uFF0C\u9700\u8981\u4EBA\u5DE5\u590D\u6838")
  unique(flags)
}

generate_genie_report <- function(raw_results_path, input_file, output_dir = dirname(raw_results_path), manifest_file = NULL, warnings = character()) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  raw <- readRDS(raw_results_path)
  results <- raw
  results <- decode_names(results)
  warnings_df <- collect_warnings(warnings, output_dir)
  manifest <- read_json_safely(manifest_file)
  input <- if (file.exists(input_file)) suppressWarnings(tryCatch(
    utils::read.csv(input_file, fileEncoding = "UTF-8-BOM", encoding = "UTF-8", stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) tryCatch(utils::read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE), error = function(e2) NULL)
  )) else NULL
  if (!is.null(input)) input <- decode_df(input)
  type_parts <- list(); redundant_parts <- list(); removed_parts <- list(); metric_parts <- list()
  item_levels <- raw$item_type_level %||% list()
  for (nm in names(item_levels)) {
    type_label <- decode_unicode_escapes(nm)
    z <- item_levels[[nm]]
    part <- extract_level(z, "item_type_level", type_label, warnings_df)
    metric_parts[[length(metric_parts) + 1L]] <- part$metrics
    type_parts[[length(type_parts) + 1L]] <- part$final_items
    redundant_parts[[length(redundant_parts) + 1L]] <- part$redundant
    removed_parts[[length(removed_parts) + 1L]] <- part$removed
  }
  overall_part <- NULL
  if (!is.null(raw$overall)) {
    overall_part <- extract_level(raw$overall, "overall", "overall", warnings_df)
    metric_parts[[length(metric_parts) + 1L]] <- overall_part$metrics
    redundant_parts[[length(redundant_parts) + 1L]] <- overall_part$redundant
    removed_parts[[length(removed_parts) + 1L]] <- overall_part$removed
  }
  metrics <- rbind_fill(metric_parts)
  type_final <- rbind_fill(type_parts)
  overall_final <- if (!is.null(overall_part)) overall_part$final_items else data.frame(stringsAsFactors = FALSE)
  primary_final <- if (!is.null(overall_part) && nrow(overall_final)) overall_final else type_final
  safe_write_csv(metrics, file.path(output_dir, "genie_metrics_summary.csv"))
  safe_write_csv(rbind_fill(redundant_parts), file.path(output_dir, "genie_redundant_pairs.csv"))
  safe_write_csv(rbind_fill(removed_parts), file.path(output_dir, "genie_removed_items.csv"))
  safe_write_csv(primary_final, file.path(output_dir, "genie_final_items.csv"))
  safe_write_csv(type_final, file.path(output_dir, "genie_type_level_final_items.csv"))
  safe_write_csv(overall_final, file.path(output_dir, "genie_overall_final_items.csv"))
  safe_write_csv(warnings_df, file.path(output_dir, "genie_warnings.csv"))
  session_lines <- c("# GENIE session information", paste0("generated_at: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")), paste0("R version: ", R.version.string), paste0("Sys.getlocale: ", Sys.getlocale()), paste0("input_file: ", normalizePath(input_file, winslash = "/", mustWork = FALSE)), capture.output(sessionInfo()))
  writeLines(session_lines, file.path(output_dir, "genie_session_info.txt"), useBytes = TRUE)
  figures <- make_figures(metrics, primary_final, raw, output_dir)
  flags <- risk_flags(metrics, warnings_df, primary_final)
  provider <- manifest$provider %||% "unknown"
  model <- manifest$embedding_model %||% "unknown"
  input_n <- suppressWarnings(as.integer(manifest$input_rows %||% NA_integer_))
  if (is.na(input_n) || input_n <= 1L) input_n <- count_csv_data_rows(input_file)
  if (!is.null(input) && (is.na(input_n) || nrow(input) > input_n)) input_n <- nrow(input)
  redundant_all <- rbind_fill(redundant_parts)
  removed_all <- rbind_fill(removed_parts)
  safe_write_csv(redundant_all, file.path(output_dir, "genie_redundant_pairs.csv"))
  safe_write_csv(removed_all, file.path(output_dir, "genie_removed_items.csv"))
  overall_row <- metrics[metrics$level == "overall", , drop = FALSE]
  type_rows <- metrics[metrics$level == "item_type_level", , drop = FALSE]
  fmt_num <- function(x, digits = 3) {
    y <- suppressWarnings(as.numeric(x[[1]] %||% NA_real_))
    if (length(y) == 0L || is.na(y) || !is.finite(y)) "NA" else formatC(y, format = "f", digits = digits)
  }
  fmt_pct <- function(x, digits = 1) {
    y <- suppressWarnings(as.numeric(x[[1]] %||% NA_real_))
    if (length(y) == 0L || is.na(y) || !is.finite(y)) "NA" else paste0(formatC(y * 100, format = "f", digits = digits), "%")
  }
  fmt_pp <- function(x, digits = 2) {
    y <- suppressWarnings(as.numeric(x[[1]] %||% NA_real_))
    if (length(y) == 0L || is.na(y) || !is.finite(y)) "NA" else paste0(ifelse(y >= 0, "+", ""), formatC(y, format = "f", digits = digits), " \u4E2A\u767E\u5206\u70B9")
  }
  interpret_nmi <- function(initial, final, delta) {
    ini <- suppressWarnings(as.numeric(initial)); fin <- suppressWarnings(as.numeric(final)); d <- suppressWarnings(as.numeric(delta))
    if (any(!is.finite(c(ini, fin, d)))) return("NMI \u6570\u636E\u4E0D\u5B8C\u6574\uFF0C\u4E0D\u80FD\u5BF9\u7B5B\u67E5\u524D\u540E\u7684\u8BED\u4E49\u2014\u793E\u533A\u5BF9\u5E94\u5173\u7CFB\u4F5C\u5B9A\u91CF\u5224\u65AD\u3002")
    strength <- if (fin >= .70) "\u8F83\u5F3A" else if (fin >= .50) "\u4E2D\u7B49" else "\u504F\u5F31"
    direction <- if (d > 0) "\u7B5B\u67E5\u540E\u6709\u6240\u6539\u5584" else if (d < 0) "\u7B5B\u67E5\u540E\u53CD\u800C\u4E0B\u964D" else "\u7B5B\u67E5\u524D\u540E\u57FA\u672C\u4E0D\u53D8"
    paste0("\u6700\u7EC8 NMI \u5904\u4E8E", strength, "\u6C34\u5E73\uFF1B", direction, "\u3002\u8FD9\u91CC\u7684 NMI \u662F\u9884\u8BBE\u5C5E\u6027\u4E0E EGA \u793E\u533A\u4E4B\u95F4\u7684\u5BF9\u5E94\u6307\u6807\uFF0C\u4E0D\u5E94\u88AB\u89E3\u91CA\u4E3A\u4FE1\u5EA6\u6216\u56E0\u5B50\u6548\u5EA6\u3002")
  }
  level_explanation <- function(r) {
    nm <- as.character(r[["type"]]); start <- as_int(r[["start_N"]], 0L); final <- as_int(r[["final_N"]], 0L)
    removed <- as_int(r[["removed_N"]], max(0L, start - final)); uva <- as_int(r[["UVA_removed"]], 0L); boot <- as_int(r[["bootEGA_removed"]], 0L)
    sweep <- fmt_num(r[["UVA_sweeps"]], 0); rate <- fmt_pct(r[["removed_rate"]]); model <- as.character(r[["EGA_model"]] %||% "NA")
    paste0("- **", nm, "**\uFF1A\u4ECE ", start, " \u9053\u5B8C\u6574\u5019\u9009\u9898\u5F00\u59CB\uFF0CEGA \u6A21\u578B\u4E3A `", model, "`\u3002UVA \u5197\u4F59\u7B5B\u67E5\u62A5\u544A\u5220\u9664 ", uva, " \u9053\u9898\u3001\u626B\u63CF ", sweep, " \u8F6E\uFF1BbootEGA \u7A33\u5B9A\u6027\u7B5B\u67E5\u62A5\u544A\u5220\u9664 ", boot, " \u9053\u9898\u3002\u6700\u7EC8\u4FDD\u7559 ", final, " \u9053\uFF0C\u8F83\u8F93\u5165\u51CF\u5C11 ", removed, " \u9053\uFF08", rate, "\uFF09\u3002NMI \u4ECE ", fmt_num(r[["initial_NMI_raw"]]), " \u53D8\u4E3A ", fmt_num(r[["final_NMI_raw"]]), "\uFF08", fmt_pp(r[["delta_NMI_pp"]]), "\uFF09\u3002", interpret_nmi(r[["initial_NMI_raw"]], r[["final_NMI_raw"]], r[["delta_NMI_pp"]]), "")
  }
  summary_line <- if (nrow(overall_row)) {
    paste0("\u5B8C\u6574 ", input_n, " \u9053\u5019\u9009\u9898\u8FDB\u5165 GENIE \u8BED\u4E49\u7B5B\u67E5\uFF1Boverall \u5C42\u9762\u6700\u7EC8\u4FDD\u7559 ", overall_row$final_N, " \u9053\uFF0C\u5220\u9664\u7387\u4E3A ", fmt_pct(overall_row$removed_rate), "\u3002NMI \u4ECE ", fmt_num(overall_row$initial_NMI_raw), " \u53D8\u4E3A ", fmt_num(overall_row$final_NMI_raw), "\uFF08", fmt_pp(overall_row$delta_NMI_pp), "\uFF09\u3002")
  } else {
    paste0("\u5B8C\u6574 ", input_n, " \u9053\u5019\u9009\u9898\u8FDB\u5165 GENIE \u8BED\u4E49\u7B5B\u67E5\uFF1B\u672C\u6B21\u672A\u4EA7\u751F overall \u7ED3\u679C\uFF0C\u56E0\u6B64 primary final pool \u56DE\u9000\u4E3A type-level \u7ED3\u679C\u3002")
  }
  type_explanations <- if (nrow(type_rows)) vapply(seq_len(nrow(type_rows)), function(i) level_explanation(type_rows[i, , drop = FALSE]), character(1)) else "- \u6CA1\u6709\u53EF\u62A5\u544A\u7684 type-level \u7ED3\u679C\u3002"
  overall_explanation <- if (nrow(overall_row)) level_explanation(overall_row[1, , drop = FALSE]) else "- \u672C\u6B21\u6CA1\u6709\u8FD0\u884C\u6216\u6CA1\u6709\u8FD4\u56DE overall \u7ED3\u679C\u3002"
  level_difference <- if (nrow(overall_row) && nrow(type_rows)) {
    type_n <- sum(as.numeric(type_rows$final_N), na.rm = TRUE)
    paste0("type-level \u7ED3\u679C\u662F\u5206\u522B\u5728\u6BCF\u4E2A\u9884\u8BBE\u7EF4\u5EA6\u5185\u8FDB\u884C\u7684\u8BCA\u65AD\uFF0C\u6700\u7EC8\u5408\u8BA1 ", type_n, " \u9053\uFF1Boverall \u7ED3\u679C\u628A\u5B8C\u6574\u9898\u6C60\u653E\u5165\u540C\u4E00\u4E2A\u7F51\u7EDC\u4E2D\uFF0C\u6700\u7EC8\u4FDD\u7559 ", overall_row$final_N, " \u9053\u3002\u4E24\u8005\u56DE\u7B54\u7684\u95EE\u9898\u4E0D\u540C\uFF0Coverall \u7ED3\u679C\u4F18\u5148\u7528\u4E8E `genie_final_items.csv`\uFF0Ctype-level \u7ED3\u679C\u7528\u4E8E\u68C0\u67E5\u5404\u7EF4\u5EA6\u5185\u90E8\u7684\u5197\u4F59\u4E0E\u7A33\u5B9A\u6027\uFF1B\u4E0D\u80FD\u7528\u524D\u8005\u66FF\u4EE3\u540E\u8005\uFF0C\u4E5F\u4E0D\u80FD\u628A\u4E24\u8005\u9898\u6570\u76F8\u52A0\u540E\u5F53\u4F5C\u4E00\u4E2A\u6700\u7EC8\u91CF\u8868\u3002")
  } else "\u7531\u4E8E\u7F3A\u5C11\u4E00\u5C42\u7ED3\u679C\uFF0C\u672C\u6B21\u65E0\u6CD5\u6BD4\u8F83 type-level \u4E0E overall \u7684\u9898\u91CF\u5DEE\u5F02\u3002"
  community_explanation <- "\u672A\u751F\u6210 attribute \u00D7 EGA community \u5BF9\u5E94\u5173\u7CFB\uFF1Aprimary final items \u7F3A\u5C11 `attribute` \u6216 `EGA_com` \u5B57\u6BB5\u3002"
  if (nrow(primary_final) && all(c("attribute", "EGA_com") %in% names(primary_final))) {
    tab <- table(decode_unicode_escapes(as.character(primary_final$attribute)), as.character(primary_final$EGA_com))
    purity <- if (sum(tab) > 0) sum(apply(tab, 2, max)) / sum(tab) else NA_real_
    dominant <- if (length(tab)) apply(tab, 2, function(x) names(which.max(x))) else character()
    mapping <- if (length(dominant)) paste(paste0("community ", names(dominant), " \u4E3B\u8981\u5BF9\u5E94\u201C", dominant, "\u201D"), collapse = "\uFF1B") else "\u65E0\u53EF\u89E3\u91CA\u793E\u533A"
    community_explanation <- paste0("primary final pool \u4E2D\u5171\u8BC6\u522B\u51FA ", ncol(tab), " \u4E2A EGA community\uFF1B\u5C5E\u6027\u2014\u793E\u533A\u7684\u603B\u4F53\u5BF9\u5E94\u7EAF\u5EA6\u4E3A ", fmt_pct(purity), "\u3002", mapping, "\u3002\u7EAF\u5EA6\u8F83\u9AD8\u8BF4\u660E\u540C\u4E00\u9884\u8BBE\u5C5E\u6027\u7684\u9898\u9879\u66F4\u96C6\u4E2D\u4E8E\u540C\u4E00\u793E\u533A\uFF1B\u82E5\u591A\u4E2A\u5C5E\u6027\u6DF7\u5165\u540C\u4E00\u793E\u533A\u6216\u540C\u4E00\u5C5E\u6027\u5206\u6563\u5230\u591A\u4E2A\u793E\u533A\uFF0C\u5E94\u7ED3\u5408\u9898\u9762\u548C\u7406\u8BBA\u8FB9\u754C\u4EBA\u5DE5\u590D\u6838\u3002")
  }
  warning_explanation <- if (!nrow(warnings_df)) {
    "\u672C\u6B21\u6CA1\u6709\u8BB0\u5F55\u5230\u53BB\u91CD\u540E\u7684 warning\u3002\u4ECD\u5E94\u4FDD\u7559 session info\uFF0C\u5E76\u5728\u4E0D\u540C\u64CD\u4F5C\u7CFB\u7EDF\u6216\u4E0D\u540C embedding provider \u4E0B\u590D\u8DD1\u654F\u611F\u6027\u68C0\u67E5\u3002"
  } else {
    counts <- table(warnings_df$category)
    count_text <- paste(paste0(names(counts), "\u7C7B ", as.integer(counts), " \u6761"), collapse = "\uFF1B")
    paste0("\u672C\u6B21\u5171\u8BB0\u5F55 ", nrow(warnings_df), " \u6761\u53BB\u91CD\u540E\u7684 warning\uFF08", count_text, "\uFF09\u3002locale/encoding \u7C7B warning \u4E3B\u8981\u63D0\u793A\u8FD0\u884C\u73AF\u5883\uFF1Bdependency/computation/other \u7C7B warning \u53EF\u80FD\u5F71\u54CD\u7ED3\u679C\uFF0C\u5E94\u5728\u89E3\u91CA\u6700\u7EC8\u9898\u6C60\u524D\u9010\u6761\u68C0\u67E5\u3002")
  }
  diagnostic_files <- setdiff(figures$files, c("nmi_before_after.png", "item_reduction_by_type.png", "removal_waterfall.png", "attribute_community_heatmap.png"))
  diagnostic_links <- if (length(diagnostic_files)) paste0("- [", diagnostic_files, "](figures/", diagnostic_files, ")") else "- \u6CA1\u6709\u989D\u5916\u7684 network/stability \u56FE\u8FD4\u56DE\u3002"
  report_lines <- c(
    "# GENIE / local_GENIE \u8BED\u4E49\u7B5B\u67E5\u5206\u6790\u62A5\u544A", "", "## 1. \u6267\u884C\u6458\u8981", "", summary_line,
    "", "\u672C\u62A5\u544A\u91C7\u7528\u8BBA\u6587\u5F0F\u7ED3\u679C\u62A5\u544A\u53E3\u5F84\uFF0C\u660E\u786E\u533A\u5206\u8F93\u5165\u9898\u6C60\u3001type-level \u8BCA\u65AD\u3001overall \u4E3B\u7ED3\u679C\u4EE5\u53CA warning\u3002\u6240\u6709\u8FDB\u5165 GENIE \u7684\u9898\u9879\u5747\u6765\u81EA\u7528\u6237\u786E\u8BA4\u540E\u7684\u5B8C\u6574\u5019\u9009\u9898\u6C60\uFF1B\u4EFB\u4F55 final items \u90FD\u662F\u9A8C\u8BC1\u8F93\u51FA\uFF0C\u4E0D\u4F1A\u88AB\u91CD\u65B0\u4F5C\u4E3A\u672C\u8F6E\u8F93\u5165\u3002",
    "", "## 2. \u8F93\u5165\u3001provider \u4E0E\u8FD0\u884C\u914D\u7F6E", "", sprintf("- \u8F93\u5165\u6587\u4EF6\uFF1A`%s`", input_file), sprintf("- \u8F93\u5165\u9898\u6570\uFF1A%s", input_n), sprintf("- provider\uFF1A`%s`", provider), sprintf("- embedding model\uFF1A`%s`", model), sprintf("- run.overall\uFF1A`%s`", ifelse(isTRUE(manifest$run_overall), "TRUE", "FALSE")), sprintf("- UVA cut-off\uFF1A`%s`", manifest$uva_cut_off %||% "unknown"), sprintf("- \u8F93\u5165 SHA-256\uFF1A`%s`", manifest$input_file_sha256 %||% "\u672A\u63D0\u4F9B"),
    "", "\u8F93\u5165\u51BB\u7ED3\u7684\u542B\u4E49\u662F\uFF1ACSV \u7684\u884C\u6570\u3001ID\u3001\u7EF4\u5EA6\u548C\u5C5E\u6027\u5206\u5E03\u5728\u9A8C\u8BC1\u5F00\u59CB\u524D\u5DF2\u88AB\u8BB0\u5F55\u5230 manifest\uFF1B\u8FD9\u4FDD\u8BC1\u540E\u7EED\u62A5\u544A\u53EF\u4EE5\u8FFD\u6EAF\u5230\u540C\u4E00\u4E2A\u5B8C\u6574\u9898\u6C60\uFF0C\u800C\u4E0D\u662F\u4E8B\u540E\u9009\u51FA\u7684\u7B80\u7248\u3002",
    "", "## 3. \u65B9\u6CD5\u4E0E\u89E3\u91CA\u6846\u67B6", "", "GENIE/local_GENIE \u5148\u5728\u9898\u9879\u6587\u672C embedding \u7A7A\u95F4\u4E2D\u8FDB\u884C\u7F51\u7EDC\u6784\u5EFA\uFF0C\u518D\u5206\u522B\u4F7F\u7528 UVA \u8BC6\u522B\u9AD8\u5EA6\u76F8\u4F3C\u6216\u5197\u4F59\u9898\u9879\uFF0C\u5E76\u7528 EGA/bootEGA \u68C0\u67E5\u7F51\u7EDC\u793E\u533A\u4E0E\u7A33\u5B9A\u6027\u3002\u62A5\u544A\u4E2D\u7684 `start_N` \u662F\u8BE5\u5C42\u9762\u7684\u8F93\u5165\u9898\u6570\uFF0C`final_N` \u662F\u8BE5\u5C42\u9762\u8FD4\u56DE\u7684\u4FDD\u7559\u9898\u6570\uFF0C`delta_NMI_pp` \u662F NMI \u53D8\u5316\u7684\u767E\u5206\u70B9\u800C\u4E0D\u662F\u6BD4\u4F8B\u3002UVA \u4E0E bootEGA \u7684\u5220\u9664\u6570\u662F\u8BCA\u65AD\u8FC7\u7A0B\u7684\u7EC4\u6210\u90E8\u5206\uFF0C\u4E0D\u80FD\u7B80\u5355\u76F8\u52A0\u89E3\u91CA\u4E3A\u4E24\u4E2A\u5B8C\u5168\u72EC\u7ACB\u7684\u5220\u9664\u96C6\u5408\u3002",
    "", "## 4. \u6838\u5FC3\u6307\u6807", "", md_table(metrics),
    "", "## 5. \u56FE\u8868\u4E0E\u56FE\u6CE8", "", "\u56FE 1 \u7528\u4E8E\u6BD4\u8F83\u7B5B\u67E5\u524D\u540E\u7684 NMI\uFF1B\u56FE 2 \u5C55\u793A\u5B8C\u6574\u9898\u6C60\u5230\u6700\u7EC8\u9898\u6C60\u7684\u6570\u91CF\u53D8\u5316\uFF1B\u56FE 3 \u5C55\u793A UVA\u3001bootEGA \u4E0E\u6700\u7EC8\u4FDD\u7559\u9898\u9879\u4E4B\u95F4\u7684\u6D41\u8F6C\uFF1B\u56FE 4 \u68C0\u67E5\u9884\u8BBE\u5C5E\u6027\u4E0E EGA \u793E\u533A\u7684\u5BF9\u5E94\u5173\u7CFB\u3002", "", "![NMI \u524D\u540E\u6BD4\u8F83](figures/nmi_before_after.png)", "", "![\u9898\u91CF\u524A\u51CF\u6BD4\u8F83](figures/item_reduction_by_type.png)", "", "![UVA/bootEGA \u6D41\u7A0B\u56FE](figures/removal_waterfall.png)", "", "![\u9884\u8BBE\u5C5E\u6027 \u00D7 EGA \u793E\u533A\u70ED\u56FE](figures/attribute_community_heatmap.png)", "", "\u989D\u5916\u8BCA\u65AD\u56FE\uFF1A", diagnostic_links,
    "", "## 6. Type-level \u7ED3\u679C", "", type_explanations,
    "", "## 7. Overall \u7ED3\u679C", "", overall_explanation, "", level_difference,
    "", "## 8. \u5C5E\u6027\u2014\u793E\u533A\u5BF9\u5E94\u5173\u7CFB", "", community_explanation,
    "", "## 9. \u5220\u9664\u9898\u9879\u3001\u5197\u4F59\u9898\u5BF9\u4E0E\u7A33\u5B9A\u6027", "", paste0("\u5171\u5BFC\u51FA ", nrow(removed_all), " \u6761 bootEGA \u5220\u9664\u8BB0\u5F55\uFF0C
\u4EE5\u53CA ", nrow(redundant_all), " \u6761 UVA \u5197\u4F59\u8BB0\u5F55\u3002\u5B8C\u6574\u5220\u9664\u660E\u7EC6\u89C1 `genie_removed_items.csv`\uFF1B\u5197\u4F59\u9898\u5BF9\u89C1 `genie_redundant_pairs.csv`\u3002\u5220\u9664\u8BB0\u5F55\u5E94\u4E0E\u9898\u9762\u3001\u7EF4\u5EA6\u8986\u76D6\u548C\u7406\u8BBA\u8FB9\u754C\u8054\u5408\u5BA1\u67E5\uFF0C\u800C\u4E0D\u80FD\u4EC5\u6309\u7B97\u6CD5\u7ED3\u679C\u673A\u68B0\u5220\u9898\u3002"),
    "", "## 10. Warnings\u3001\u7F16\u7801\u4E0E\u53EF\u590D\u73B0\u6027", "", warning_explanation, "", md_table(warnings_df), "", "\u8FD0\u884C\u73AF\u5883\u4E0E\u5305\u7248\u672C\u89C1 `genie_session_info.txt`\uFF1B\u8F93\u5165 hash\u3001provider\u3001\u6A21\u578B\u548C\u5173\u952E\u53C2\u6570\u89C1 `genie_input_manifest.json`\u3002\u82E5\u51FA\u73B0 Unicode \u5360\u4F4D\u7B26\uFF0C\u8BF4\u660E\u7ED3\u679C\u5BF9\u8C61\u5728\u8F93\u51FA\u94FE\u8DEF\u4E2D\u53D1\u751F\u4E86 Unicode escape\uFF0C\u672C\u62A5\u544A\u811A\u672C\u4F1A\u5C1D\u8BD5\u89E3\u7801\uFF0C\u4F46\u4ECD\u5EFA\u8BAE\u68C0\u67E5\u539F\u59CB RDS \u548C locale\u3002",
    "", "## 11. \u81EA\u52A8\u98CE\u9669\u63D0\u793A", "", if (length(flags)) paste0("- ", flags) else "\u672A\u89E6\u53D1\u9884\u8BBE\u81EA\u52A8\u98CE\u9669\u89C4\u5219\u3002\u98CE\u9669\u89C4\u5219\u7528\u4E8E\u63D0\u793A\u4EBA\u5DE5\u590D\u6838\uFF0C\u4E0D\u662F\u7EDF\u8BA1\u5B66\u663E\u8457\u6027\u68C0\u9A8C\u3002",
    "", "## 12. \u65B9\u6CD5\u8FB9\u754C\u4E0E\u540E\u7EED\u771F\u5B9E\u6837\u672C\u9A8C\u8BC1", "", "GENIE/local_GENIE \u662F\u57FA\u4E8E\u6587\u672C\u5D4C\u5165\u7684 in-silico \u8BED\u4E49\u7B5B\u67E5\u4E0E\u5185\u90E8\u524A\u51CF\u3002NMI\u3001UVA\u3001EGA \u548C bootEGA \u53CD\u6620\u7684\u662F\u6587\u672C\u8BED\u4E49\u51E0\u4F55\u3001\u5197\u4F59\u5173\u7CFB\u4EE5\u53CA\u5D4C\u5165\u6270\u52A8\u4E0B\u7684\u7A33\u5B9A\u6027\uFF0C\u4E0D\u80FD\u66FF\u4EE3\u5B66\u751F\u4F5C\u7B54\u6570\u636E\u4E0A\u7684\u5185\u90E8\u4E00\u81F4\u6027\u4FE1\u5EA6\u3001\u9879\u76EE\u5206\u6790\u3001EFA/CFA\u3001\u6D4B\u91CF\u4E0D\u53D8\u6027\u3001\u53CD\u5E94\u8FC7\u7A0B\u8BC1\u636E\u6216\u5916\u90E8\u6548\u6807\u6548\u5EA6\u3002\u8FDB\u5165\u6B63\u5F0F\u91CF\u8868\u524D\uFF0C\u5EFA\u8BAE\u8FDB\u884C\u4E13\u5BB6\u5185\u5BB9\u6548\u5EA6\u8BC4\u5BA1\u3001\u513F\u7AE5\u8BA4\u77E5\u8BBF\u8C08\u3001\u5C0F\u6837\u672C\u9884\u6D4B\u8BD5\u3001\u9879\u76EE\u5206\u5E03\u4E0E\u7F3A\u5931\u68C0\u67E5\uFF0C\u5E76\u5728\u72EC\u7ACB\u6837\u672C\u4E2D\u5B8C\u6210\u4FE1\u5EA6\u3001EFA/CFA\u3001\u6D4B\u91CF\u4E0D\u53D8\u6027\u548C\u6548\u6807\u5173\u8054\u6548\u5EA6\u9A8C\u8BC1\u3002",
    "", "## 13. \u4EA7\u7269\u6E05\u5355", "", "- `genie_input_manifest.json`\uFF1A\u51BB\u7ED3\u7684\u5B8C\u6574\u8F93\u5165\u53CA hash", "- `genie_results_raw.rds`\uFF1AAIGENIE \u539F\u59CB\u7ED3\u679C", "- `genie_validation_report.md`\uFF1A\u53EF\u590D\u73B0\u7684 Markdown \u4E2D\u95F4\u62A5\u544A", "- `genie_validation_report.docx`\uFF1A\u6B63\u5F0F\u4EA4\u4ED8\u7684\u8BBA\u6587\u5F0F Word \u62A5\u544A\uFF08\u7531\u540E\u5904\u7406\u811A\u672C\u751F\u6210\uFF09", "- `genie_metrics_summary.csv`\uFF1Atype-level/overall \u6307\u6807", "- `genie_final_items.csv`\uFF1Aprimary final pool\uFF0Coverall \u4F18\u5148", "- `genie_type_level_final_items.csv` / `genie_overall_final_items.csv`\uFF1A\u5206\u5C42\u7ED3\u679C", "- `genie_removed_items.csv` / `genie_redundant_pairs.csv`\uFF1A\u5220\u9664\u4E0E\u5197\u4F59\u660E\u7EC6", "- `genie_warnings.csv` / `genie_session_info.txt`\uFF1Awarning \u4E0E\u8FD0\u884C\u5BA1\u8BA1\u4FE1\u606F", "- `figures/`\uFF1A\u6838\u5FC3\u56FE\u8868\u3001network \u56FE\u548C stability \u56FE"
  )
  report_path <- file.path(output_dir, "genie_validation_report.md")
  writeLines(enc2utf8(report_lines), report_path, useBytes = TRUE)
  core <- c("genie_metrics_summary.csv", "genie_final_items.csv", "genie_type_level_final_items.csv", "genie_overall_final_items.csv", "genie_warnings.csv", "genie_session_info.txt", file.path("figures", c("nmi_before_after.png", "item_reduction_by_type.png", "removal_waterfall.png", "attribute_community_heatmap.png")))
  complete <- all(file.exists(file.path(output_dir, core)))
  list(status = if (complete && nrow(warnings_df) == 0) "completed_with_report" else if (complete) "completed_with_warnings" else "failed", report_path = report_path, core_complete = complete, warnings = warnings_df)
}

# Optional command-line mode for smoke tests and manual post-processing:
if (!interactive() && identical(Sys.getenv("GENIE_REPORT_DIRECT"), "1")) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 2) stop("GENIE_REPORT_DIRECT=1 requires raw_results.rds and input.csv")
  output <- ifelse(length(args) >= 3, args[[3]], dirname(normalizePath(args[[1]], mustWork = FALSE)))
  generate_genie_report(args[[1]], args[[2]], output)
}
