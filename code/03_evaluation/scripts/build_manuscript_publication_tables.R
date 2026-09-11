#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
})

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
EVALUATION_ROOT <- file.path(PROJECT_ROOT, "outputs", "evaluation")
SOURCE_DIR <- file.path(EVALUATION_ROOT, "tables")
PUBLICATION_DIR <- file.path(EVALUATION_ROOT, "manuscript", "tables")
dir.create(PUBLICATION_DIR, recursive = TRUE, showWarnings = FALSE)

standardise_task <- function(x) {
  recode(
    x,
    "Climate-growth original" = "Climate-growth original scale",
    "Left-right original" = "Left-right original scale",
    .default = x
  )
}

task_to_variant <- c(
  "Climate-growth grouped" = "1290",
  "Climate-growth original scale" = "1290_original_scale",
  "Left-right grouped" = "1500",
  "Left-right original scale" = "1500_original_scale"
)

read_required <- function(filename) {
  path <- file.path(SOURCE_DIR, filename)
  if (!file.exists(path)) stop("Missing ordinal publication source: ", path)
  read_csv(path, show_col_types = FALSE)
}

rq1 <- read_required(
  "ordinal_covariates_only_statistical_baseline_comparison.csv"
) %>%
  filter(prompt_variant == "baseline_notime") %>%
  mutate(
    Task = standardise_task(Task),
    variant = unname(task_to_variant[Task]),
    baseline_specification = "expanding_window_ordinal_probit",
    publication_role = "RQ1 target-profile comparison",
    .after = Task
  )

rq2 <- read_required("ordinal_statistical_baseline_comparison.csv") %>%
  mutate(
    Task = standardise_task(Task),
    variant = unname(task_to_variant[Task]),
    baseline_specification = "expanding_window_ordinal_probit",
    publication_role = "RQ2 matched prior-state comparison",
    .after = Task
  )

if (n_distinct(rq1$Task) != 4L || nrow(rq1) != 20L ||
    any(count(rq1, Task)$n != 5L) ||
    any(count(rq1, Task, model)$n != 1L)) {
  stop("RQ1 ordinal publication table must contain one no-time row for five models and four tasks.")
}
required_rq1 <- c(
  "n_total", "accuracy_prompt", "accuracy_ordinal", "prompt_minus_ordinal"
)
if (any(!complete.cases(rq1[required_rq1]))) {
  stop("RQ1 ordinal publication table has missing primary quantities.")
}
if (any(abs(
  rq1$prompt_minus_ordinal -
    (rq1$accuracy_prompt - rq1$accuracy_ordinal)
) > 1e-12)) {
  stop("RQ1 prompt-minus-ordinal identity failed.")
}

if (n_distinct(rq2$Task) != 4L || nrow(rq2) != 20L ||
    any(count(rq2, Task)$n != 5L)) {
  stop("RQ2 ordinal publication table must contain five models for four tasks.")
}
required_rq2 <- c(
  "n_total", "accuracy_majority", "accuracy_cf", "accuracy_trajectory",
  "accuracy_ordinal", "trajectory_minus_cf", "trajectory_minus_ordinal"
)
if (any(!complete.cases(rq2[required_rq2]))) {
  stop("RQ2 ordinal publication table has missing primary quantities.")
}
if (any(abs(
  rq2$trajectory_minus_cf -
    (rq2$accuracy_trajectory - rq2$accuracy_cf)
) > 1e-12)) {
  stop("RQ2 trajectory-minus-carry-forward identity failed.")
}
if (any(abs(
  rq2$trajectory_minus_ordinal -
    (rq2$accuracy_trajectory - rq2$accuracy_ordinal)
) > 1e-12)) {
  stop("RQ2 trajectory-minus-ordinal identity failed.")
}

rq1_path <- file.path(
  PUBLICATION_DIR, "rq1_ordinal_covariates_only_comparison.csv"
)
rq2_path <- file.path(
  PUBLICATION_DIR, "rq2_ordinal_prior_state_comparison.csv"
)
write_csv(rq1, rq1_path)
write_csv(rq2, rq2_path)

manifest <- tibble(
  publication_file = c(basename(rq1_path), basename(rq2_path)),
  publication_role = c(
    "RQ1 target-profile comparison",
    "RQ2 matched prior-state comparison"
  ),
  baseline_specification = "expanding_window_ordinal_probit",
  source_file = c(
    "tables/ordinal_covariates_only_statistical_baseline_comparison.csv",
    "tables/ordinal_statistical_baseline_comparison.csv"
  ),
  rows = c(nrow(rq1), nrow(rq2)),
  md5 = unname(tools::md5sum(c(rq1_path, rq2_path)))
)
write_csv(manifest, file.path(PUBLICATION_DIR, "publication_manifest.csv"))

message("Wrote canonical ordinal publication tables to: ", PUBLICATION_DIR)
