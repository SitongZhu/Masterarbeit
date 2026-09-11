#!/usr/bin/env Rscript
# Build common-sample analysis inputs and run the existing evaluation pipeline
# into a separate same-database output folder.

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "03_evaluation"))) {
  stop("Run this script from the code project root.")
}

run_script <- function(path) {
  message("\n==== running: ", path, " ====")
  sys.source(file.path(PROJECT_ROOT, path),
             envir = new.env(parent = globalenv()))
}

same_database_input_dir <- file.path(PROJECT_ROOT, "data",
                                     "analysis_inputs_same_database")
same_database_output_dir <- file.path(PROJECT_ROOT, "outputs",
                                      "evaluation_same_database")

Sys.setenv(
  COMMON_SAMPLE_SOURCE_INPUT_DIR = file.path(PROJECT_ROOT, "data",
                                             "analysis_inputs"),
  COMMON_SAMPLE_ANALYSIS_INPUT_DIR = same_database_input_dir
)

run_script("03_evaluation/scripts/build_common_sample_analysis_inputs.R")

Sys.setenv(
  ANALYSIS_INPUT_DIR = same_database_input_dir,
  EVALUATION_OUTPUT_ROOT = same_database_output_dir
)

run_script("03_evaluation/scripts/analyse_1500_dynamic_chains.R")
run_script("03_evaluation/scripts/analyse_all_variants.R")

message("\nSame-database evaluation complete.")
message("Same-database analysis inputs: ", same_database_input_dir)
message("Same-database evaluation outputs: ", same_database_output_dir)
