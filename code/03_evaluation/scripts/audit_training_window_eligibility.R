#!/usr/bin/env Rscript
# Compare full-input screening with screening restricted to each training window.
# Run from code/: Rscript 03_evaluation/scripts/audit_training_window_eligibility.R
#   INPUT_DIRECTORY OUTPUT_DIRECTORY REFERENCE_EVALUATION_DIRECTORY
# No models are fitted and no respondent-level records are exported.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3L) stop("Expected input, output, and reference evaluation directories.")
input_dir <- normalizePath(args[1], winslash = "/", mustWork = TRUE)
output_dir <- normalizePath(args[2], winslash = "/", mustWork = FALSE)
reference_dir <- normalizePath(args[3], winslash = "/", mustWork = TRUE)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
Sys.setenv(ANALYSIS_INPUT_DIR = input_dir, EVALUATION_OUTPUT_ROOT = output_dir)

# Load the maintained selector and preprocessing helpers without running analyses.
core_path <- "03_evaluation/scripts/analyse_all_variants.R"
lines <- readLines(core_path, encoding = "UTF-8", warn = FALSE)
end <- grep("^csv_files <-", lines)[1L] - 1L
eval(parse(text = lines[seq_len(end)]), envir = .GlobalEnv)
ordinal_path <- "03_evaluation/scripts/generate_ordinal_statistical_baselines.R"
expressions <- parse(ordinal_path, encoding = "UTF-8")
for (expr in expressions) {
  if (is.call(expr) && identical(expr[[1]], as.name("<-")) &&
      identical(expr[[2]], as.name("prepare_raw_statistical_light"))) {
    eval(expr, envir = .GlobalEnv)
  }
}

effective_predictors <- function(data, columns) {
  columns[vapply(columns, function(col) {
    values <- as.character(data[[col]])
    values[is.na(values) | !nzchar(values)] <- STAT_BASELINE_MISSING_LEVEL
    length(unique(values)) >= 2L
  }, logical(1))]
}
join_names <- function(x) paste(x, collapse = ";")
window_rows <- list()
feature_rows <- list()
diagnostic_rows <- list()
variants <- c("1290", "1290_original_scale", "1500", "1500_original_scale")

for (variant in variants) {
  message("Reading analytical input: ", variant)
  outcome <- sub("_.*$", "", variant)
  raw <- prepare_raw_statistical_light(file.path(input_dir, paste0("analyse_", variant, ".csv")))
  raw$wave_order <- parse_wave_order(raw$wave)
  candidates <- setdiff(grep("^(kp_|pi_)", names(raw), value = TRUE),
                        c(paste0("kp_", outcome), paste0("pi_", outcome)))
  full <- infer_covariate_columns(raw, outcome)
  # Retain every candidate when deduplicating, so a globally excluded predictor
  # can still be discovered by the training-window screen.
  human <- raw %>%
    select(lfdn, wave, wave_order, label_cat, vorwelle_label_cat, all_of(candidates)) %>%
    group_by(lfdn, wave, wave_order) %>%
    summarise(across(c(label_cat, vorwelle_label_cat, all_of(candidates)), first_non_missing),
              .groups = "drop") %>%
    filter(!is.na(lfdn), !is.na(wave_order), !is.na(label_cat))

  for (baseline in c("covariates_only", "lag_covariates")) {
    data <- if (baseline == "lag_covariates") {
      filter(human, !is.na(vorwelle_label_cat))
    } else human
    waves <- data %>% distinct(wave, wave_order) %>% arrange(wave_order, wave)
    for (i in seq_len(nrow(waves))) {
      target <- waves$wave[i]
      order <- waves$wave_order[i]
      train <- filter(data, wave_order < order)
      if (nrow(train) < STAT_BASELINE_MIN_N) next
      training_raw <- filter(raw, wave_order < order)
      raw_window <- infer_covariate_columns(training_raw, outcome)
      local <- infer_covariate_columns(train, outcome)
      previous <- effective_predictors(train, full)
      restricted <- effective_predictors(train, local)
      extra <- if (baseline == "lag_covariates") "vorwelle_label_cat" else character()
      fitted <- effective_predictors(train, c(extra, full))
      window_rows[[length(window_rows) + 1L]] <- tibble(
        variant, baseline, target_wave = target, n_train = nrow(train),
        global_count = length(full), raw_window_count = length(raw_window),
        training_count = length(local), global_predictors = join_names(full),
        raw_window_predictors = join_names(raw_window), training_predictors = join_names(local),
        raw_window_identical = identical(full, raw_window),
        eligibility_identical = identical(full, local),
        effective_predictors_identical = identical(previous, restricted),
        added = join_names(setdiff(local, full)), removed = join_names(setdiff(full, local)))

      for (col in candidates) {
        values <- train[[col]]
        feature_rows[[length(feature_rows) + 1L]] <- tibble(
          variant, baseline, target_wave = target, predictor = col,
          n_train = nrow(train), n_observed = sum(!is.na(values)),
          coverage = mean(!is.na(values)), observed_levels = length(unique(na.omit(values))),
          globally_eligible = col %in% full, training_eligible = col %in% local)
      }
      reference_names <- if (baseline == "covariates_only") {
        c("covariates_only_ordinal_probit_diagnostics.csv",
          "covariates_only_multinomial_logit_diagnostics.csv")
      } else {
        c("lag_covariate_ordinal_probit_diagnostics.csv", "lag_covariate_multinomial_logit_diagnostics.csv")
      }
      for (name in reference_names) {
        path <- file.path(reference_dir, paste0("analysis_", variant), "statistical_baselines", name)
        archived <- read_csv(path, show_col_types = FALSE, progress = FALSE) %>% filter(wave == target)
        stopifnot(nrow(archived) == 1L)
        column <- if ("predictors_used" %in% names(archived)) "predictors_used" else "covariates_used"
        recorded <- strsplit(archived[[column]][1], ";", fixed = TRUE)[[1]]
        # Multinomial lag diagnostics list only profile covariates in
        # covariates_used, while predictor_count also includes the lag factor.
        expected <- if (column == "covariates_used" && baseline == "lag_covariates") previous else fitted
        diagnostic_rows[[length(diagnostic_rows) + 1L]] <- tibble(
          variant, baseline, target_wave = target, reference_file = name,
          n_train_matches = archived$n_train[1] == nrow(train),
          fitted_predictors_match = identical(expected, recorded),
          predictor_count_matches = archived$predictor_count[1] == length(fitted))
      }
    }
  }
  message("Audited ", variant, ": ", join_names(full))
  rm(raw, human, data, train, training_raw)
  invisible(gc())
}
windows <- bind_rows(window_rows)
features <- bind_rows(feature_rows)
diagnostics <- bind_rows(diagnostic_rows)
write_csv(windows, file.path(output_dir, "training_window_eligibility.csv"))
write_csv(features, file.path(output_dir, "training_window_feature_counts.csv"))
write_csv(diagnostics, file.path(output_dir, "training_window_reference_checks.csv"))
summary <- list(training_windows = nrow(windows),
                windows_with_changed_eligibility = sum(!windows$eligibility_identical),
                windows_with_changed_raw_screen = sum(!windows$raw_window_identical),
                windows_with_changed_effective_predictors = sum(!windows$effective_predictors_identical),
                archived_fits_checked = nrow(diagnostics),
                archived_training_sizes_match = all(diagnostics$n_train_matches),
                archived_predictor_sets_match = all(diagnostics$fitted_predictors_match),
                archived_predictor_counts_match = all(diagnostics$predictor_count_matches),
                models_refitted = FALSE, llm_generations_rerun = FALSE)
jsonlite::write_json(summary, file.path(output_dir, "training_window_eligibility_summary.json"),
                     pretty = TRUE, auto_unbox = TRUE)
print(summary)
stopifnot(all(diagnostics$n_train_matches), all(diagnostics$fitted_predictors_match),
          all(diagnostics$predictor_count_matches))
