#!/usr/bin/env Rscript
# Generate main-text figures under outputs/evaluation/.

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "03_evaluation"))) {
  stop("Run this script from the code project root.")
}

run_script <- function(path) {
  message("\n==== running: ", path, " ====")
  sys.source(file.path(PROJECT_ROOT, path),
             envir = new.env(parent = globalenv()))
}

run_script("03_evaluation/scripts/generate_information_ladder_figure.R")
run_script("03_evaluation/scripts/generate_main_text_figures.R")


message("Main-text figures written to outputs/evaluation/.")
