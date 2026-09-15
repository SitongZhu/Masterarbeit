#!/usr/bin/env Rscript
# Fit synthetic baselines and verify descriptive handling of repeated respondents.
local({
  repository <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  temporary <- tempfile("auxiliary_contracts_")
  dir.create(file.path(temporary, "data/analysis_inputs"), recursive = TRUE)
  dir.create(file.path(temporary, "03_evaluation/scripts"), recursive = TRUE)
  stopifnot(file.copy(file.path(repository, "code/03_evaluation/scripts/numeric_response_parser.R"),
                     file.path(temporary, "03_evaluation/scripts/numeric_response_parser.R")))
  on.exit({setwd(repository); unlink(temporary, recursive = TRUE)}, add = TRUE)
  setwd(temporary)
  core <- new.env(parent = globalenv())
  lines <- readLines(file.path(repository, "code/03_evaluation/scripts/analyse_all_variants.R"),
                     encoding = "UTF-8")
  end <- grep("^csv_files <-", lines)[1L] - 1L
  eval(parse(text = lines[seq_len(end)]), core)
  read_output <- function(directory, name) {
    readr::read_csv(file.path(directory, name), show_col_types = FALSE)
  }

  raw <- tidyr::expand_grid(lfdn = as.character(1:60), wave = c("w10", "w11", "w14")) %>%
    dplyr::mutate(label_cat = as.character((as.integer(lfdn)-1L) %% 3L + 1L),
                  kp_test = label_cat,
                  vorwelle_label_cat = ifelse(wave == "w10", NA_character_, label_cat),
                  predict_cat = ifelse(wave == "w11", "wrong", label_cat),
                  model = "test", prompt_variant = "trajectory")
  # Unparsed LLM answers remain failures in the common comparison denominator.
  raw$predict_cat[raw$wave == "w14" & raw$lfdn == "1"] <- NA_character_
  trajectory_dir <- file.path(temporary, "trajectory")
  core$run_module_statistical_baselines(raw, "1500", trajectory_dir, min_n = 50L)
  rows <- read_output(trajectory_dir, "trajectory_baseline_row_comparison.csv")
  overall <- read_output(trajectory_dir, "statistical_baseline_comparison_overall.csv")
  by_wave <- read_output(trajectory_dir, "statistical_baseline_comparison_by_wave.csv")
  stopifnot(nrow(rows) == 120L, sum(!is.na(rows$statistical_pred_cat)) == 60L,
            overall$n_input == 120L, overall$n_comparison == 60L, overall$n_total == 60L,
            overall$accuracy_statistical == 1, isTRUE(all.equal(overall$accuracy_trajectory, 59/60)),
            overall$n_cf_correct == 60L, overall$accuracy_cf == 1,
            overall$n_majority_correct == 20L, isTRUE(all.equal(overall$accuracy_majority, 1/3)),
            isTRUE(all.equal(overall$trajectory_minus_statistical, -1/60)))
  first_wave <- by_wave[by_wave$wave == "w11", ]
  accuracy_cols <- c("accuracy_statistical", "accuracy_trajectory", "accuracy_cf", "accuracy_majority")
  stopifnot(first_wave$n_input == 60L, first_wave$n_comparison == 0L,
            all(is.na(first_wave[accuracy_cols])))

  # The companion covariates-only path has the same unavailable-wave issue.
  raw$prompt_variant <- "baseline_notime"
  covariates_dir <- file.path(temporary, "covariates")
  core$run_module_covariates_only_statistical_baseline(raw, "1500", covariates_dir, min_n = 90L)
  overall <- read_output(covariates_dir, "covariates_only_nontrajectory_comparison_overall.csv")
  by_wave <- read_output(covariates_dir, "covariates_only_nontrajectory_comparison_by_wave.csv")
  stopifnot(overall$n_input == 120L, overall$n_total == 60L,
            overall$accuracy_statistical == 1, isTRUE(all.equal(overall$accuracy_prompt, 59/60)),
            overall$n_majority_correct == 20L, isTRUE(all.equal(overall$accuracy_majority, 1/3)),
            is.na(by_wave$accuracy_prompt[by_wave$wave == "w11"]))

  # Repeating identical personal outcomes does not create more respondents.
  people <- tibble::tibble(lfdn = as.character(1:100), wave = "w10",
                          model = "test", prompt_variant = "trajectory", subgroup = "A",
                          correct = rep(c(TRUE, FALSE), each = 50))
  retired <- c("subgroup_bias_prop_tests_by_wave.csv", "subgroup_bias_prop_tests_overall.csv",
               "subgroup_bias_logistic_regression.csv")
  for (waves in c(1L, 10L)) {
    repeated <- dplyr::bind_rows(lapply(seq_len(waves), function(w) {
      result <- people
      result$wave <- paste0("w", w)
      result
    }))
    directory <- file.path(temporary, paste0("subgroup_", waves))
    dir.create(directory)
    for (name in c(retired, "unrelated.txt")) writeLines("existing output", file.path(directory, name))
    core$run_module_subgroup_correctness(
      repeated, directory, subgroup_vars = "subgroup", source_vars = "subgroup",
      subgroup_fn = identity, outcome_fn = function(x) x$correct, min_n = 1L)
    summary <- read_output(directory, "subgroup_correctness_overall.csv")
    stopifnot(summary$n == 100L * waves, summary$n_respondents == 100L,
              summary$n_missing_lfdn == 0L, summary$accuracy == .5,
              !any(c("se", "ci_low", "ci_high", "p_value") %in% names(summary)),
              !any(file.exists(file.path(directory, retired))),
              file.exists(file.path(directory, "unrelated.txt")),
              file.exists(file.path(directory, "subgroup_correctness_overall.png")))
  }
  cat("PASS: matched auxiliary baselines, missing predictions, and repeated-respondent descriptive summaries.\n")
  cat("SVG dependency version:", as.character(utils::packageVersion("svglite")), "\n")
})
