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

# Part 2a: after the external LLM run, merge JSONL outputs back to the survey
# wave lists and clean the generated analyse_<variant>.csv files.
run_script("run_02a_build_and_clean_analysis_inputs.R")

# Optional dynamic-chain diagnostic for the clustered 1500 outcome. Running it
# before the main evaluator lets the final PNG organizer collect these figures.
run_script("03_evaluation/scripts/analyse_1500_dynamic_chains.R")

# Part 2b: run the full evaluation pipeline.
run_script("03_evaluation/scripts/analyse_all_variants.R")

message("\nBuild inputs and evaluation complete.")
message("Analysis inputs: ",
        file.path(PROJECT_ROOT, "data", "analysis_inputs"))
message("Evaluation outputs: ",
        file.path(PROJECT_ROOT, "outputs", "evaluation"))
message("Organized PNGs: ",
        file.path(PROJECT_ROOT, "outputs", "evaluation",
                  "organized_analysis_pngs"))
