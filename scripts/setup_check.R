# AIGENIE / GENIE environment check.
#
# Usage:
#   Rscript setup_check.R [validation_config.json]
#   source("setup_check.R")
#
# The selected provider is a decision-gate input. Without a config file this
# script performs only baseline checks and explains that provider-specific
# checks must be rerun after build_aigenie_call.py writes validation_config.json.
# Secrets are never printed.

has_failure <- FALSE

ok <- function(message) cat("  [OK] ", message, "\n", sep = "")
note <- function(message) cat("  [INFO] ", message, "\n", sep = "")
bad <- function(message, fix = NULL) {
  has_failure <<- TRUE
  cat("  [FAIL] ", message, "\n", sep = "")
  if (!is.null(fix)) cat("         Fix: ", fix, "\n", sep = "")
}
header <- function(message) cat("\n== ", message, " ==\n", sep = "")

running_from_source <- any(vapply(sys.frames(), function(frame) {
  !is.null(frame$ofile)
}, logical(1)))
should_exit <- !interactive() && !running_from_source

args <- commandArgs(trailingOnly = TRUE)
config_path <- if (length(args) >= 1) args[[1]] else "validation_config.json"
provider <- NULL
config <- NULL
provider_checks_enabled <- FALSE

header("Validation config")
if (file.exists(config_path)) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    bad("jsonlite is required to read validation_config.json",
        'install.packages("jsonlite")')
  } else {
    config <- tryCatch(jsonlite::fromJSON(config_path), error = function(e) {
      bad(paste0("validation config is not valid JSON: ", e$message))
      NULL
    })
    if (!is.null(config)) {
      if (is.null(config$provider) || !nzchar(as.character(config$provider))) {
        bad("validation config is missing a valid provider")
      } else {
        provider <- as.character(config$provider)
        provider_checks_enabled <- TRUE
        ok(paste0("provider selected: ", provider))
      }
    }
  }
} else {
  note(paste0("validation config not found: ", config_path))
  note("baseline checks only; rerun after build_aigenie_call.py writes validation_config.json")
}

header("R packages")
if (!provider_checks_enabled) {
  core_packages <- c("jsonlite", "reticulate", "ggplot2", "igraph", "patchwork", "EGAnet")
  note("no provider selected yet; checking packages commonly needed for GENIE validation")
} else if (identical(provider, "skip")) {
  core_packages <- c("jsonlite")
  note("skip provider only needs jsonlite for config parsing; run_genie.R will not load AIGENIE or EGAnet")
} else {
  core_packages <- c("jsonlite", "reticulate", "ggplot2", "igraph", "patchwork", "EGAnet", "AIGENIE")
}
for (package in unique(core_packages)) {
  if (requireNamespace(package, quietly = TRUE)) {
    ok(paste0(package, " installed"))
  } else {
    bad(paste0(package, " not installed"),
        sprintf('install.packages("%s")', package))
  }
}


header("Encoding and locale preflight")
locale_now <- Sys.getlocale()
note(paste0("Sys.getlocale(): ", locale_now))
if (identical(Sys.getlocale("LC_CTYPE"), "C") || grepl("(^|;)C($|;)", locale_now)) {
  note("R is running in C locale; GENIE may return literal <U+....> Unicode escapes. The standard genie_report.R post-processor will decode exports, but the environment should be noted in the report.")
}
locale_candidates <- if (.Platform$OS.type == "windows") {
  c("Chinese (Simplified)_China.65001", "Chinese (Simplified)_China.936", "C.UTF-8")
} else {
  c("C.UTF-8", "en_US.UTF-8")
}
locale_attempt <- FALSE
for (loc in locale_candidates) {
  locale_attempt <- suppressWarnings(tryCatch(!is.na(Sys.setlocale("LC_CTYPE", loc)), error = function(e) FALSE))
  if (locale_attempt) break
}
if (locale_attempt) {
  ok(paste0("LC_CTYPE can be set for this session: ", Sys.getlocale("LC_CTYPE")))
} else {
  note("No tested UTF-8 locale could be applied; this does not block GENIE, but the final report should classify locale warnings.")
}
roundtrip_file <- tempfile(fileext = ".txt")
roundtrip_probe <- "\u4E2D\u6587\u7F16\u7801 round-trip"
roundtrip_ok <- tryCatch({
  con <- file(roundtrip_file, open = "wb")
  writeBin(charToRaw(enc2utf8(roundtrip_probe)), con)
  close(con)
  identical(readLines(roundtrip_file, encoding = "UTF-8", warn = FALSE), roundtrip_probe)
}, error = function(e) FALSE)
if (roundtrip_ok) {
  ok("Chinese UTF-8 round-trip write/read works")
} else {
  note("Chinese UTF-8 round-trip check failed; rely on genie_report.R Unicode escape decoding and inspect outputs manually")
}
if (!is.null(config) && !is.null(config$genie_input_file)) {
  input_path <- as.character(config$genie_input_file)
  if (file.exists(input_path)) ok(paste0("GENIE input file exists: ", input_path)) else bad(paste0("GENIE input file missing: ", input_path))
}

header("Provider prerequisites")
if (!provider_checks_enabled) {
  note("provider-specific checks deferred until validation_config.json exists")
} else if (provider %in% c("openai", "jina", "huggingface")) {
  env_name <- switch(
    provider,
    openai = "OPENAI_API_KEY",
    jina = "JINA_API_KEY",
    huggingface = "HF_TOKEN"
  )
  if (nzchar(Sys.getenv(env_name))) {
    ok(paste0(env_name, " is set"))
  } else {
    bad(
      paste0(env_name, " is not set"),
      paste0("set ", env_name, " in the current R session or shell before running run_genie.R")
    )
  }
} else if (identical(provider, "precomputed")) {
  matrix_path <- if (!is.null(config$embedding_matrix)) {
    as.character(config$embedding_matrix)
  } else {
    ""
  }
  if (nzchar(matrix_path) && file.exists(matrix_path)) {
    ok(paste0("precomputed embedding matrix found: ", matrix_path))
  } else {
    bad("precomputed embedding matrix is missing or unreadable")
  }
} else if (identical(provider, "local")) {
  if (requireNamespace("AIGENIE", quietly = TRUE)) {
    ok("local_GENIE is available through AIGENIE")
    info <- tryCatch(AIGENIE::python_env_info(), error = function(e) NULL)
    if (!is.null(info)) {
      ok("AIGENIE Python environment is configured")
    } else {
      bad("AIGENIE Python environment is not initialized",
          "library(AIGENIE); ensure_aigenie_python()")
    }
  }
} else if (identical(provider, "skip")) {
  ok("validation is intentionally deferred; AIGENIE and EGAnet are not required for skip output")
} else {
  bad(paste0("unsupported provider: ", provider),
      "rebuild validation_config.json with provider openai, jina, huggingface, local, precomputed, or skip")
}

header("Summary")
if (has_failure) {
  cat("  One or more checks failed. Resolve failures before running run_genie.R.\n")
} else if (identical(provider, "skip")) {
  cat("  Items may be generated, but scale_validated must remain FALSE.\n")
} else if (provider_checks_enabled) {
  cat("  Provider checks complete. You may source(\"run_genie.R\") when ready.\n")
} else {
  cat("  Baseline checks complete. Choose a provider and generate validation_config.json next.\n")
}

if (should_exit) {
  quit(status = if (has_failure) 1 else 0)
}

invisible(!has_failure)
