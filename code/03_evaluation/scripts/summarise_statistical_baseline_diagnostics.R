#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(purrr)
})

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
evaluation_root <- file.path(project_root, "outputs", "evaluation")
table_dir <- file.path(evaluation_root, "tables")
dir.create(table_dir, recursive = TRUE, showWarnings = FALSE)

variant_spec <- tibble::tribble(
  ~variant, ~task, ~categories,
  "1290", "Climate-growth grouped", 3L,
  "1290_original_scale", "Climate-growth original scale", 7L,
  "1500", "Left-right grouped", 3L,
  "1500_original_scale", "Left-right original scale", 11L
)

read_fit_diagnostics <- function(variant, task, categories, baseline, filename) {
  path <- file.path(
    evaluation_root, paste0("analysis_", variant),
    "statistical_baselines", filename
  )
  diagnostics <- read_csv(path, show_col_types = FALSE) %>%
    filter(statistical_model != "not_estimated", !is.na(fit_convergence))

  diagnostics %>%
    summarise(
      variant = variant,
      task = task,
      baseline = baseline,
      categories = categories,
      estimated_fits = n(),
      converged_fits = sum(fit_convergence == 0L),
      iteration_limit_fits = sum(fit_convergence != 0L),
      max_iteration_limit = max(iteration_limit, na.rm = TRUE),
      n_train_min = min(n_train, na.rm = TRUE),
      n_train_max = max(n_train, na.rm = TRUE),
      predictor_count_min = min(predictor_count, na.rm = TRUE),
      predictor_count_max = max(predictor_count, na.rm = TRUE)
    )
}

convergence_summary <- pmap_dfr(
  variant_spec,
  function(variant, task, categories) {
    bind_rows(
      read_fit_diagnostics(
        variant, task, categories, "covariates_only",
        "covariates_only_multinomial_logit_diagnostics.csv"
      ),
      read_fit_diagnostics(
        variant, task, categories, "lag_and_covariates",
        "lag_covariate_multinomial_logit_diagnostics.csv"
      )
    )
  }
)
write_csv(
  convergence_summary,
  file.path(table_dir, "statistical_baseline_convergence_summary.csv")
)

stability_all <- variant_spec %>%
  filter(grepl("_original_scale$", variant)) %>%
  pmap_dfr(function(variant, task, categories) {
    path <- file.path(
      evaluation_root, paste0("analysis_", variant),
      "statistical_baselines", "covariates_only_iteration_stability.csv"
    )
    read_csv(path, show_col_types = FALSE) %>%
      mutate(variant = variant, task = task, categories = categories, .before = 1L)
  }) %>%
  group_by(variant, wave, wave_order) %>%
  mutate(
    final_accuracy = accuracy[iteration_limit == final_iteration_limit][1],
    final_deviance = deviance[iteration_limit == final_iteration_limit][1],
    accuracy_abs_diff_from_final = abs(accuracy - final_accuracy),
    deviance_abs_diff_from_final = abs(deviance - final_deviance),
    deviance_relative_diff_from_final = deviance_abs_diff_from_final / final_deviance
  ) %>%
  ungroup() %>%
  arrange(variant, wave_order, iteration_limit)

write_csv(
  stability_all,
  file.path(table_dir, "covariates_only_iteration_stability_all.csv")
)

stability_summary <- stability_all %>%
  group_by(task, categories, iteration_limit, final_iteration_limit) %>%
  summarise(
    estimated_fits = n(),
    converged_fits = sum(convergence == 0L),
    iteration_limit_fits = sum(convergence != 0L),
    min_prediction_agreement_with_final = min(
      prediction_agreement_with_final, na.rm = TRUE
    ),
    max_accuracy_abs_diff_from_final = max(
      accuracy_abs_diff_from_final, na.rm = TRUE
    ),
    max_deviance_relative_diff_from_final = max(
      deviance_relative_diff_from_final, na.rm = TRUE
    ),
    .groups = "drop"
  )

write_csv(
  stability_summary,
  file.path(table_dir, "covariates_only_iteration_stability_summary.csv")
)

archive_root <- file.path(
  evaluation_root, "numerical_stability_archive", "maxit_200"
)

if (dir.exists(archive_root)) {
  prediction_comparison <- pmap_dfr(
    variant_spec,
    function(variant, task, categories) {
      imap_dfr(
        list(
          covariates_only = "covariates_only_multinomial_logit_predictions.csv",
          lag_and_covariates = "lag_covariate_multinomial_logit_predictions.csv"
        ),
        function(filename, baseline) {
          old_path <- file.path(
            archive_root, paste0("analysis_", variant), filename
          )
          new_path <- file.path(
            evaluation_root, paste0("analysis_", variant),
            "statistical_baselines", filename
          )
          old <- read_csv(old_path, show_col_types = FALSE) %>%
            select(lfdn, wave, label_cat, old_prediction = statistical_pred_cat)
          new <- read_csv(new_path, show_col_types = FALSE) %>%
            select(lfdn, wave, label_cat, new_prediction = statistical_pred_cat)
          compared <- inner_join(
            old, new, by = c("lfdn", "wave", "label_cat")
          ) %>%
            filter(!is.na(old_prediction), !is.na(new_prediction))

          old_accuracy <- mean(compared$old_prediction == compared$label_cat)
          new_accuracy <- mean(compared$new_prediction == compared$label_cat)
          tibble(
            variant = variant,
            task = task,
            baseline = baseline,
            n_old = sum(!is.na(old$old_prediction)),
            n_new = sum(!is.na(new$new_prediction)),
            n_compared = nrow(compared),
            old_accuracy = old_accuracy,
            new_accuracy = new_accuracy,
            accuracy_change = new_accuracy - old_accuracy,
            prediction_agreement = mean(
              compared$old_prediction == compared$new_prediction
            )
          )
        }
      )
    }
  )
  write_csv(
    prediction_comparison,
    file.path(table_dir, "maxit_200_vs_2000_prediction_comparison.csv")
  )
}

message("Wrote consolidated convergence and stability diagnostics to: ", table_dir)
