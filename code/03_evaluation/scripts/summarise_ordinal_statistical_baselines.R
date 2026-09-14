#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(purrr)
})

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
EVALUATION_ROOT <- file.path(PROJECT_ROOT, "outputs", "evaluation")
TABLE_DIR <- file.path(EVALUATION_ROOT, "tables")
dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)

variant_spec <- tibble::tribble(
  ~variant, ~task,
  "1290", "Climate-growth grouped",
  "1290_original_scale", "Climate-growth original",
  "1500", "Left-right grouped",
  "1500_original_scale", "Left-right original"
)

short_model <- function(model) {
  case_when(
    str_detect(model, "Mistral") ~ "Mistral-7B",
    str_detect(model, "Llama-3_3-70B") ~ "Llama-3.3-70B",
    str_detect(model, "72B") ~ "Qwen2.5-72B",
    str_detect(model, "32B") ~ "Qwen2.5-32B",
    str_detect(model, "7B") ~ "Qwen2.5-7B",
    TRUE ~ model
  )
}

format3 <- function(x) ifelse(is.na(x), NA_character_, sprintf("%.3f", x))

safe_max <- function(x) {
  if (length(x) == 0L || all(is.na(x))) return(NA_real_)
  max(x, na.rm = TRUE)
}

safe_min <- function(x) {
  if (length(x) == 0L || all(is.na(x))) return(NA_real_)
  min(x, na.rm = TRUE)
}

read_variant_comparison <- function(variant, task, filename) {
  read_csv(
    file.path(
      EVALUATION_ROOT, paste0("analysis_", variant),
      "statistical_baselines", filename
    ),
    show_col_types = FALSE
  ) %>%
    mutate(modal_category = as.character(modal_category)) %>%
    mutate(Task = task, .before = 1L)
}

covariates_compact <- map2_dfr(
  variant_spec$variant, variant_spec$task,
  ~ read_variant_comparison(
    .x, .y, "ordinal_covariates_only_comparison_overall.csv"
  )
) %>%
  mutate(Model = short_model(model)) %>%
  arrange(Task, prompt_variant, Model)

lag_compact <- map2_dfr(
  variant_spec$variant, variant_spec$task,
  ~ read_variant_comparison(.x, .y, "ordinal_lag_comparison_overall.csv")
) %>%
  mutate(Model = short_model(model)) %>%
  arrange(Task, Model)

covariates_display <- covariates_compact %>%
  transmute(
    Task,
    Prompt = prompt_label,
    Model,
    N = n_total,
    Modal = modal_category,
    PreviousWaveModal = format3(accuracy_majority),
    CovariatesOnly = format3(accuracy_ordinal),
    LLMPrompt = format3(accuracy_prompt),
    `Prompt-PreviousWaveModal` = format3(accuracy_prompt - accuracy_majority),
    `Prompt-Stat` = format3(prompt_minus_ordinal),
    NStat = n_total,
    PromptMAE = format3(prompt_mae),
    OrdinalMAE = format3(ordinal_mae),
    PromptWithinOne = format3(prompt_within_one),
    OrdinalWithinOne = format3(ordinal_within_one)
  )

lag_display <- lag_compact %>%
  transmute(
    Task,
    Model,
    N = n_total,
    Modal = modal_category,
    PreviousWaveModal = format3(accuracy_majority),
    CarryForward = format3(accuracy_cf),
    Statistical = format3(accuracy_ordinal),
    Trajectory = format3(accuracy_trajectory),
    `Traj-PreviousWaveModal` = format3(trajectory_minus_majority),
    `Traj-CF` = format3(trajectory_minus_cf),
    `Traj-Stat` = format3(trajectory_minus_ordinal),
    NStat = n_total,
    TrajectoryMAE = format3(trajectory_mae),
    OrdinalMAE = format3(ordinal_mae),
    TrajectoryWithinOne = format3(trajectory_within_one),
    OrdinalWithinOne = format3(ordinal_within_one)
  )

write_csv(
  covariates_compact,
  file.path(TABLE_DIR, "ordinal_covariates_only_statistical_baseline_comparison.csv")
)
write_csv(
  covariates_display,
  file.path(TABLE_DIR, "ordinal_covariates_only_statistical_baseline_comparison_display.csv")
)
write_csv(
  lag_compact,
  file.path(TABLE_DIR, "ordinal_statistical_baseline_comparison.csv")
)
write_csv(
  lag_display,
  file.path(TABLE_DIR, "ordinal_statistical_baseline_comparison_display.csv")
)

# Generic publication inputs point to the primary ordinal-probit estimates.
write_csv(
  covariates_compact,
  file.path(TABLE_DIR, "covariates_only_statistical_baseline_comparison.csv")
)
write_csv(
  covariates_display,
  file.path(TABLE_DIR, "covariates_only_statistical_baseline_comparison_display.csv")
)
write_csv(
  lag_compact,
  file.path(TABLE_DIR, "statistical_baseline_comparison.csv")
)
write_csv(
  lag_display,
  file.path(TABLE_DIR, "statistical_baseline_comparison_display.csv")
)

read_diagnostics <- function(variant, task, baseline, filename) {
  read_csv(
    file.path(
      EVALUATION_ROOT, paste0("analysis_", variant),
      "statistical_baselines", filename
    ),
    show_col_types = FALSE
  ) %>% mutate(variant = variant, task = task, baseline = baseline, .before = 1L)
}

diagnostics <- pmap_dfr(variant_spec, function(variant, task) {
  bind_rows(
    read_diagnostics(
      variant, task, "covariates_only",
      "covariates_only_ordinal_probit_diagnostics.csv"
    ),
    read_diagnostics(
      variant, task, "lag_and_covariates",
      "lag_covariate_ordinal_probit_diagnostics.csv"
    )
  )
})
write_csv(diagnostics, file.path(TABLE_DIR, "ordinal_probit_diagnostics_all.csv"))

diagnostic_summary <- diagnostics %>%
  filter(ordinal_model != "not_estimated") %>%
  group_by(variant, task, baseline) %>%
  summarise(
    estimated_fits = n(),
    converged_fits = sum(convergence_code == 0L, na.rm = TRUE),
    finite_threshold_fits = sum(thresholds_finite, na.rm = TRUE),
    ordered_threshold_fits = sum(thresholds_strictly_ordered, na.rm = TRUE),
    valid_probability_fits = sum(probability_rows_valid, na.rm = TRUE),
    max_absolute_gradient = safe_max(max_gradient),
    max_hessian_condition = safe_max(hessian_condition),
    min_threshold_gap = safe_min(min_threshold_gap),
    .groups = "drop"
  )
write_csv(
  diagnostic_summary,
  file.path(TABLE_DIR, "ordinal_probit_diagnostics_summary.csv")
)

read_nominal <- function(variant, task, baseline, filename) {
  path <- file.path(
    EVALUATION_ROOT, paste0("analysis_", variant),
    "statistical_baselines", filename
  )
  result <- read_csv(path, show_col_types = FALSE)
  if (nrow(result) == 0L) return(tibble())
  result %>% mutate(
    variant = variant, task = task, baseline = baseline, .before = 1L
  )
}

nominal_tests <- pmap_dfr(variant_spec, function(variant, task) {
  bind_rows(
    read_nominal(
      variant, task, "covariates_only",
      "covariates_only_ordinal_probit_nominal_tests.csv"
    ),
    read_nominal(
      variant, task, "lag_and_covariates",
      "lag_covariate_ordinal_probit_nominal_tests.csv"
    )
  )
})
write_csv(
  nominal_tests,
  file.path(TABLE_DIR, "ordinal_probit_parallel_slopes_tests.csv")
)

# Matched, unrounded specification comparisons are generated from predictions
# by build_thesis_result_tables.py.
message("Wrote consolidated ordinal-probit tables to: ", TABLE_DIR)
