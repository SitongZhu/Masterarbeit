#!/usr/bin/env Rscript

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "03_evaluation"))) {
  stop("Run this script from the code project root.")
}

run_script <- function(path) {
  message("\n==== running: ", path, " ====")
  sys.source(file.path(PROJECT_ROOT, path),
             envir = new.env(parent = globalenv()))
}

run_script("03_evaluation/scripts/analyse_1500_dynamic_chains.R")
run_script("03_evaluation/scripts/analyse_all_variants.R")

message("\nEvaluation complete.")
message("Evaluation outputs: ",
        file.path(PROJECT_ROOT, "outputs", "evaluation"))
