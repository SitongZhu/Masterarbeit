#!/usr/bin/env Rscript

# Build all thesis evaluation results and publication figures inside code/.
# Run from the code project root after archived LLM JSONL outputs are available.

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "03_evaluation"))) {
  stop("Run this script from the code project root.")
}

run_r <- function(path) {
  message("\n==== manuscript build: ", path, " ====")
  sys.source(file.path(PROJECT_ROOT, path),
             envir = new.env(parent = globalenv()))
}

run_system <- function(command, args, working_directory = PROJECT_ROOT) {
  old_directory <- getwd()
  on.exit(setwd(old_directory), add = TRUE)
  setwd(working_directory)
  message("\n==== manuscript build: ", command, " ", paste(args, collapse = " "), " ====")
  status <- system2(command, args = args)
  if (!identical(status, 0L)) {
    stop("External manuscript-build command failed with status ", status)
  }
}

args <- commandArgs(trailingOnly = TRUE)
skip_input_rebuild <- "--skip-input-rebuild" %in% args
resume_ordinal_tables <- "--resume-ordinal-tables" %in% args
resume_ordinal_models <- "--resume-ordinal-models" %in% args
resume_publication_figures <- "--resume-publication-figures" %in% args

if (resume_publication_figures) {
  message("\n==== manuscript build: resuming at publication figures ====")
} else if (!resume_ordinal_tables && !resume_ordinal_models) {
  run_r("03_evaluation/scripts/audit_trajectory_output_coverage.R")
  if (!skip_input_rebuild) {
    run_r("run_02a_build_and_clean_analysis_inputs.R")
  } else {
    message("\n==== manuscript build: using the already rebuilt analysis inputs ====")
  }
  run_r("03_evaluation/scripts/audit_analysis_input_lag_linkage.R")

  run_r("03_evaluation/scripts/analyse_1500_dynamic_chains.R")
  run_r("03_evaluation/scripts/analyse_all_variants.R")
} else {
  message("\n==== manuscript build: resuming at the ordinal publication stage ====")
}

if (!resume_publication_figures) {
old_skip_ordinal <- Sys.getenv("SKIP_ORDINAL_MODEL_RUN", unset = NA_character_)
if (resume_ordinal_tables) Sys.setenv(SKIP_ORDINAL_MODEL_RUN = "1")
run_r("03_evaluation/scripts/generate_ordinal_statistical_baselines.R")
if (is.na(old_skip_ordinal)) {
  Sys.unsetenv("SKIP_ORDINAL_MODEL_RUN")
} else {
  Sys.setenv(SKIP_ORDINAL_MODEL_RUN = old_skip_ordinal)
}
run_r("03_evaluation/scripts/summarise_ordinal_statistical_baselines.R")
run_r("03_evaluation/scripts/build_manuscript_publication_tables.R")
run_r("03_evaluation/scripts/summarize_dynamic_validity_results.R")
run_r("03_evaluation/scripts/generate_structural_fidelity_summary.R")

old_common_id <- Sys.getenv("COMMON_SAMPLE_RUN_ID", unset = NA_character_)
Sys.setenv(COMMON_SAMPLE_RUN_ID = "manuscript")
run_r("03_evaluation/scripts/common_sample_accuracy.R")
if (is.na(old_common_id)) {
  Sys.unsetenv("COMMON_SAMPLE_RUN_ID")
} else {
  Sys.setenv(COMMON_SAMPLE_RUN_ID = old_common_id)
}
run_r("03_evaluation/scripts/generate_parsing_retention_summary.R")

run_r("03_evaluation/scripts/generate_information_ladder_figure.R")
run_r("03_evaluation/scripts/generate_main_text_figures.R")
run_r("03_evaluation/scripts/generate_model_scale_robustness_figure.R")
}

python_candidates <- c(
  Sys.getenv("MANUSCRIPT_PYTHON", unset = ""),
  Sys.which("python"),
  Sys.which("python3")
)
python_candidates <- unique(python_candidates[nzchar(python_candidates)])
python_candidates <- python_candidates[file.exists(python_candidates)]
python_candidates <- python_candidates[vapply(
  python_candidates,
  function(candidate) {
    status <- suppressWarnings(system2(
      candidate, "--version", stdout = FALSE, stderr = FALSE
    ))
    identical(status, 0L)
  },
  logical(1)
)]
if (length(python_candidates) == 0L) {
  stop("A real Python interpreter was not found for publication figure generation.")
}
python <- python_candidates[[1]]
run_system(
  python,
  file.path("03_evaluation", "scripts", "generate_manuscript_result_rows.py")
)
run_system(
  python,
  file.path("03_evaluation", "scripts", "generate_publication_figures.py")
)


message("Full evaluation completed. Outputs: outputs/evaluation/")
