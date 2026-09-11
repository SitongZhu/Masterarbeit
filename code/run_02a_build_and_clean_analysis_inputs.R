#!/usr/bin/env Rscript

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "02_build_analysis_inputs"))) {
  stop("Run this script from the code project root.")
}

run_script <- function(path) {
  message("\n==== running: ", path, " ====")
  sys.source(file.path(PROJECT_ROOT, path),
             envir = new.env(parent = globalenv()))
}

# Merge copied LLM JSONL outputs with the survey wave-list RDS files.
run_script("02_build_analysis_inputs/scripts/build_analysis_inputs_from_jsonl.R")

# Clean/normalize model predictions in the generated analyse_<variant>.csv files.
# This step maps fuzzy textual LLM answers onto valid Human label categories.
run_script("02_build_analysis_inputs/scripts/fuzzy_match_predictions.R")

message("\nAnalysis input build and cleaning complete.")
message("Cleaned analysis inputs: ",
        file.path(PROJECT_ROOT, "data", "analysis_inputs"))
