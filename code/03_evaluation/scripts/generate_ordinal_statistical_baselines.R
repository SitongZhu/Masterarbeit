#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(purrr)
  library(ordinal)
})

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "03_evaluation"))) {
  stop("Run this script from the code project root.")
}

load_evaluation_definitions <- function(script_path) {
  lines <- readLines(script_path, warn = FALSE)
  cut_at <- grep("^csv_files <-", lines)[1] - 1L
  eval(parse(text = paste(lines[seq_len(cut_at)], collapse = "\n")),
       envir = .GlobalEnv)
}

load_evaluation_definitions(
  file.path(PROJECT_ROOT, "03_evaluation", "scripts", "analyse_all_variants.R")
)

ANALYSIS_INPUT_DIR <- file.path(PROJECT_ROOT, "data", "analysis_inputs")
EVALUATION_ROOT <- file.path(PROJECT_ROOT, "outputs", "evaluation")
TABLE_DIR <- file.path(EVALUATION_ROOT, "tables")
dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)

variant_spec <- tibble::tribble(
  ~variant, ~task, ~representation, ~outcome_variable,
  "1290", "Climate-growth grouped", "grouped", "1290",
  "1290_original_scale", "Climate-growth original", "original_scale", "1290",
  "1500", "Left-right grouped", "grouped", "1500",
  "1500_original_scale", "Left-right original", "original_scale", "1500"
)

variant_filter <- commandArgs(trailingOnly = TRUE)
variant_filter <- variant_filter[!startsWith(variant_filter, "--")]
env_filter <- Sys.getenv("ANALYSE_VARIANTS", unset = "")
if (length(variant_filter) == 0L && nzchar(env_filter)) {
  variant_filter <- unlist(strsplit(env_filter, ",", fixed = TRUE))
}
variant_filter <- trimws(variant_filter)
variant_filter <- variant_filter[nzchar(variant_filter)]
if (length(variant_filter) > 0L) {
  variant_spec <- variant_spec %>% filter(variant %in% variant_filter)
}
if (nrow(variant_spec) == 0L) stop("No requested variants were found.")

skip_model_run <- Sys.getenv("SKIP_ORDINAL_MODEL_RUN", unset = "") %in%
  c("1", "true", "TRUE", "yes", "YES")

prepare_raw_statistical_light <- function(csv_path) {
  raw <- read_csv(
    csv_path,
    col_select = c(
      tidyselect::any_of(c(
        "wave_id_from_list", "wave", "lfdn", "id", "label", "predict",
        "llm_model", "model", "prompt_variant", "vorwelle_label"
      )),
      tidyselect::starts_with("kp_"),
      tidyselect::starts_with("pi_")
    ),
    show_col_types = FALSE,
    progress = FALSE
  )
  raw <- raw %>%
    mutate(
      label = clean_text(label),
      predict = clean_text(predict),
      prompt_variant = clean_text(prompt_variant),
      wave = clean_text(
        if ("wave_id_from_list" %in% names(.)) wave_id_from_list else wave
      )
    )
  raw$model <- clean_text(
    if ("llm_model" %in% names(raw)) {
      coalesce(raw$llm_model,
               if ("model" %in% names(raw)) raw$model else NA_character_)
    } else if ("model" %in% names(raw)) {
      raw$model
    } else {
      NA_character_
    }
  )
  raw$lfdn <- clean_text(
    if ("lfdn" %in% names(raw)) raw$lfdn
    else if ("id" %in% names(raw)) raw$id
    else NA_character_
  )

  dict <- build_label_dict(raw$label)
  raw$label_cat <- match_to_category(raw$label, dict)
  raw$predict_cat <- match_to_category(raw$predict, dict)
  raw$vorwelle_label_cat <- if ("vorwelle_label" %in% names(raw)) {
    match_to_category(raw$vorwelle_label, dict)
  } else {
    NA_character_
  }
  attr(raw, "label_dict") <- dict
  raw
}

prepare_ordinal_predictors <- function(data, predictor_cols, predictor_levels,
                                       category_levels, keep_outcome = TRUE) {
  out <- data
  for (col in predictor_cols) {
    values <- as.character(out[[col]])
    values[is.na(values) | !nzchar(values)] <- STAT_BASELINE_MISSING_LEVEL
    allowed <- predictor_levels[[col]]
    values[!(values %in% allowed)] <- STAT_BASELINE_OTHER_LEVEL
    out[[col]] <- factor(values, levels = allowed)
  }
  if (keep_outcome) {
    out$label_ordered <- ordered(out$label_cat, levels = category_levels)
  }
  out
}

align_test_levels <- function(train, test, predictor_cols) {
  for (col in predictor_cols) {
    train_values <- as.character(train[[col]])
    observed_levels <- sort(unique(train_values[!is.na(train_values)]))
    if (length(observed_levels) == 0L) next
    modal <- names(sort(table(train_values), decreasing = TRUE))[1]
    test_values <- as.character(test[[col]])
    test_values[!(test_values %in% observed_levels)] <- modal
    train[[col]] <- factor(train_values, levels = observed_levels)
    test[[col]] <- factor(test_values, levels = observed_levels)
  }
  list(train = train, test = test)
}

fit_expanding_ordinal <- function(data, predictor_cols, category_levels,
                                  baseline_name, min_n = 50L) {
  predictor_levels <- lapply(predictor_cols, function(col) {
    values <- as.character(data[[col]])
    values[is.na(values) | !nzchar(values)] <- STAT_BASELINE_MISSING_LEVEL
    sort(unique(c(values, STAT_BASELINE_MISSING_LEVEL,
                  STAT_BASELINE_OTHER_LEVEL)))
  })
  names(predictor_levels) <- predictor_cols

  wave_index <- data %>%
    distinct(wave, wave_order) %>%
    arrange(wave_order, wave)
  prediction_rows <- list()
  diagnostic_rows <- list()
  threshold_rows <- list()
  nominal_rows <- list()

  for (idx in seq_len(nrow(wave_index))) {
    wave_value <- wave_index$wave[[idx]]
    wave_order_value <- wave_index$wave_order[[idx]]
    train_raw <- data %>% filter(wave_order < wave_order_value)
    test_raw <- data %>% filter(wave == wave_value)

    empty_prediction <- function(model_name = "not_estimated") {
      test_raw %>%
        transmute(
          lfdn, wave, wave_order, label_cat,
          ordinal_pred_cat = NA_character_,
          ordinal_model = model_name,
          n_train = nrow(train_raw), n_test = nrow(test_raw),
          predictor_count = 0L
        )
    }

    if (nrow(train_raw) < min_n || nrow(test_raw) == 0L) {
      prediction_rows[[length(prediction_rows) + 1L]] <- empty_prediction()
      diagnostic_rows[[length(diagnostic_rows) + 1L]] <- tibble(
        wave = wave_value, wave_order = wave_order_value,
        ordinal_model = "not_estimated", n_train = nrow(train_raw),
        n_test = nrow(test_raw), predictor_count = 0L,
        predictors_used = NA_character_, n_classes = NA_integer_,
        convergence_code = NA_integer_, convergence_message = NA_character_,
        log_likelihood = NA_real_, max_gradient = NA_real_,
        hessian_condition = NA_real_, iterations_outer = NA_integer_,
        iterations_inner = NA_integer_, threshold_count = NA_integer_,
        thresholds_finite = NA, thresholds_strictly_ordered = NA,
        min_threshold_gap = NA_real_, probability_rows_valid = NA,
        max_probability_sum_error = NA_real_
      )
      next
    }

    train <- prepare_ordinal_predictors(
      train_raw, predictor_cols, predictor_levels, category_levels, TRUE
    ) %>% filter(!is.na(label_ordered))
    test <- prepare_ordinal_predictors(
      test_raw, predictor_cols, predictor_levels, category_levels, FALSE
    )
    model_predictors <- predictor_cols[vapply(predictor_cols, function(col) {
      length(unique(as.character(train[[col]]))) >= 2L
    }, logical(1))]

    if (nrow(train) < min_n ||
        length(unique(as.character(train$label_ordered))) < 2L ||
        length(model_predictors) == 0L) {
      prediction_rows[[length(prediction_rows) + 1L]] <- empty_prediction()
      next
    }

    aligned <- align_test_levels(train, test, model_predictors)
    train <- aligned$train
    test <- aligned$test
    ordinal_form <- as.formula(
      paste("label_ordered ~", paste(sprintf("`%s`", model_predictors),
                                      collapse = " + "))
    )
    design_terms <- delete.response(terms(ordinal_form))
    design_train_full <- model.matrix(design_terms, data = train)
    design_test_full <- model.matrix(design_terms, data = test)
    intercept_col <- which(colnames(design_train_full) == "(Intercept)")
    if (length(intercept_col) > 0L) {
      design_train_full <- design_train_full[, -intercept_col, drop = FALSE]
      design_test_full <- design_test_full[, -intercept_col, drop = FALSE]
    }
    design_qr <- qr(design_train_full, tol = 1e-7, LAPACK = FALSE)
    independent_columns <- sort(design_qr$pivot[seq_len(design_qr$rank)])
    design_train <- design_train_full[, independent_columns, drop = FALSE]
    design_test <- design_test_full[, independent_columns, drop = FALSE]
    design_names <- paste0("x", seq_len(ncol(design_train)))
    colnames(design_train) <- design_names
    colnames(design_test) <- design_names
    model_train <- data.frame(
      label_ordered = train$label_ordered,
      design_train,
      check.names = FALSE
    )
    model_test <- data.frame(design_test, check.names = FALSE)
    fit_form <- as.formula(
      paste("label_ordered ~", paste(design_names, collapse = " + "))
    )
    outcome_proportions <- prop.table(table(model_train$label_ordered))
    cumulative_proportions <- cumsum(as.numeric(outcome_proportions))
    threshold_start <- qnorm(pmin(
      pmax(cumulative_proportions[-length(cumulative_proportions)], 1e-6),
      1 - 1e-6
    ))
    fit_start <- c(rep(0, ncol(design_train)), threshold_start)
    fit_error <- NA_character_
    fit <- tryCatch(
      suppressWarnings(MASS::polr(
        fit_form, data = model_train, method = "probit", Hess = FALSE,
        model = TRUE, start = fit_start
      )),
      error = function(e) {
        fit_error <<- conditionMessage(e)
        NULL
      }
    )

    message("ordinal ", baseline_name, ": target ", wave_value,
            " n_train=", nrow(train), " n_test=", nrow(test),
            " predictors=", length(model_predictors))

    if (is.null(fit)) {
      prediction_rows[[length(prediction_rows) + 1L]] <-
        empty_prediction("fit_failed")
      diagnostic_rows[[length(diagnostic_rows) + 1L]] <- tibble(
        wave = wave_value, wave_order = wave_order_value,
        ordinal_model = "fit_failed", n_train = nrow(train),
        n_test = nrow(test), predictor_count = length(model_predictors),
        predictors_used = paste(model_predictors, collapse = ";"),
        n_classes = length(unique(as.character(train$label_ordered))),
        convergence_code = NA_integer_, convergence_message = fit_error,
        log_likelihood = NA_real_, max_gradient = NA_real_,
        hessian_condition = NA_real_, iterations_outer = NA_integer_,
        iterations_inner = NA_integer_, threshold_count = NA_integer_,
        thresholds_finite = NA, thresholds_strictly_ordered = NA,
        min_threshold_gap = NA_real_, probability_rows_valid = NA,
        max_probability_sum_error = NA_real_
      )
      next
    }

    newdata <- model_test
    class_prediction_error <- NA_character_
    probability_prediction_error <- NA_character_
    probability_prediction <- tryCatch({
      coefficient_names <- names(fit$coefficients)
      missing_columns <- setdiff(coefficient_names, names(newdata))
      if (length(missing_columns) > 0L) {
        stop("missing retained design columns: ",
             paste(missing_columns, collapse = ", "))
      }
      linear_predictor <- drop(
        as.matrix(newdata[, coefficient_names, drop = FALSE]) %*%
          fit$coefficients
      )
      cumulative_probability <- vapply(
        as.numeric(fit$zeta),
        function(threshold) pnorm(threshold - linear_predictor),
        numeric(length(linear_predictor))
      )
      if (is.null(dim(cumulative_probability))) {
        cumulative_probability <- matrix(
          cumulative_probability, ncol = length(fit$zeta)
        )
      }
      probabilities <- cbind(
        cumulative_probability[, 1L],
        if (ncol(cumulative_probability) > 1L) {
          cumulative_probability[, -1L, drop = FALSE] -
            cumulative_probability[, -ncol(cumulative_probability), drop = FALSE]
        } else {
          NULL
        },
        1 - cumulative_probability[, ncol(cumulative_probability)]
      )
      colnames(probabilities) <- fit$lev
      probabilities[abs(probabilities) < 1e-12] <- 0
      probabilities
    }, error = function(e) {
      probability_prediction_error <<- conditionMessage(e)
      NULL
    })
    class_prediction <- tryCatch(
      {
        if (is.null(probability_prediction)) {
          stop(probability_prediction_error)
        }
        fit$lev[max.col(probability_prediction, ties.method = "first")]
      },
      error = function(e) {
        class_prediction_error <<- conditionMessage(e)
        rep(NA_character_, nrow(test))
      }
    )
    if (!is.na(class_prediction_error) ||
        !is.na(probability_prediction_error)) {
      message(
        "ordinal prediction failed for ", baseline_name, " at ", wave_value,
        ": class=", class_prediction_error,
        "; probabilities=", probability_prediction_error
      )
    }

    model_id <- paste0("expanding_window_ordinal_probit_", baseline_name)
    prediction_rows[[length(prediction_rows) + 1L]] <- test_raw %>%
      transmute(
        lfdn, wave, wave_order, label_cat,
        ordinal_pred_cat = class_prediction,
        ordinal_model = model_id,
        n_train = nrow(train), n_test = nrow(test),
        predictor_count = length(model_predictors)
      )

    thresholds <- as.numeric(fit$zeta)
    threshold_names <- names(fit$zeta)
    threshold_gaps <- diff(thresholds)
    probability_valid <- !is.null(probability_prediction) &&
      all(is.finite(probability_prediction)) &&
      all(probability_prediction >= -1e-10) &&
      all(probability_prediction <= 1 + 1e-10)
    probability_sum_error <- if (is.null(probability_prediction)) {
      NA_real_
    } else {
      max(abs(rowSums(probability_prediction) - 1), na.rm = TRUE)
    }
    niter <- fit$niter
    diagnostic_rows[[length(diagnostic_rows) + 1L]] <- tibble(
      wave = wave_value, wave_order = wave_order_value,
      ordinal_model = model_id, n_train = nrow(train), n_test = nrow(test),
      predictor_count = length(model_predictors),
      design_column_count = ncol(design_train),
      predictors_used = paste(model_predictors, collapse = ";"),
      n_classes = length(unique(as.character(train$label_ordered))),
      convergence_code = as.integer(fit$convergence),
      class_prediction_error = class_prediction_error,
      probability_prediction_error = probability_prediction_error,
      convergence_message = if (!is.null(fit$message)) {
        as.character(fit$message)
      } else if (identical(as.integer(fit$convergence), 0L)) {
        "successful convergence"
      } else {
        NA_character_
      },
      log_likelihood = as.numeric(logLik(fit)),
      max_gradient = NA_real_,
      hessian_condition = NA_real_,
      iterations_outer = if (length(niter) >= 1L) as.integer(niter[[1]]) else NA_integer_,
      iterations_inner = if (length(niter) >= 2L) as.integer(niter[[2]]) else NA_integer_,
      threshold_count = length(thresholds),
      thresholds_finite = all(is.finite(thresholds)),
      thresholds_strictly_ordered = length(thresholds) < 2L ||
        all(threshold_gaps > 0),
      min_threshold_gap = if (length(threshold_gaps) > 0L) {
        min(threshold_gaps)
      } else {
        NA_real_
      },
      probability_rows_valid = probability_valid,
      max_probability_sum_error = probability_sum_error
    )
    threshold_rows[[length(threshold_rows) + 1L]] <- tibble(
      wave = wave_value, wave_order = wave_order_value,
      threshold = threshold_names, estimate = thresholds
    )

    if (idx == nrow(wave_index)) {
      clm_fit <- tryCatch(
        suppressWarnings(ordinal::clm(
          ordinal_form, data = train, link = "probit", Hess = TRUE,
          control = ordinal::clm.control(
            maxIter = 200L, gradTol = 1e-6, maxLineIter = 50L
          )
        )),
        error = function(e) NULL
      )
      nominal <- if (!is.null(clm_fit)) {
        tryCatch(
          suppressWarnings(ordinal::nominal_test(clm_fit)),
          error = function(e) NULL
        )
      } else {
        NULL
      }
      if (!is.null(nominal)) {
        nominal_df <- as.data.frame(nominal)
        nominal_rows[[length(nominal_rows) + 1L]] <- tibble(
          wave = wave_value,
          term = rownames(nominal_df),
          degrees_freedom = nominal_df[["Df"]],
          likelihood_ratio = nominal_df[["LRT"]],
          p_value = nominal_df[["Pr(>Chi)"]]
        ) %>% filter(term != "<none>")
      }
    }
  }

  list(
    predictions = bind_rows(prediction_rows),
    diagnostics = bind_rows(diagnostic_rows),
    thresholds = bind_rows(threshold_rows),
    nominal_tests = bind_rows(nominal_rows)
  )
}

metric_summary <- function(data, prediction_col, representation) {
  observed <- suppressWarnings(as.numeric(as.character(data$label_cat)))
  predicted <- suppressWarnings(as.numeric(as.character(data[[prediction_col]])))
  valid <- !is.na(observed) & !is.na(predicted)
  exact_match <- !is.na(data$label_cat) &
    !is.na(data[[prediction_col]]) &
    data[[prediction_col]] == data$label_cat
  tibble(
    accuracy = mean(exact_match),
    mae = if (representation == "original_scale" && any(valid)) {
      mean(abs(predicted[valid] - observed[valid]))
    } else {
      NA_real_
    },
    within_one_accuracy = if (representation == "original_scale" && any(valid)) {
      mean(abs(predicted[valid] - observed[valid]) <= 1)
    } else {
      NA_real_
    },
    n_ordinal_metric = sum(valid)
  )
}

compare_covariates_only <- function(row_comparison, ordinal_predictions,
                                    representation) {
  joined <- row_comparison %>%
    select(-any_of(c("ordinal_pred_cat", "ordinal_model"))) %>%
    mutate(lfdn = as.character(lfdn), wave = as.character(wave)) %>%
    left_join(
      ordinal_predictions %>%
        mutate(lfdn = as.character(lfdn), wave = as.character(wave)) %>%
        select(lfdn, wave, wave_order, ordinal_pred_cat, ordinal_model),
      by = c("lfdn", "wave", "wave_order")
    ) %>%
    filter(!is.na(ordinal_pred_cat))

  joined %>%
    group_by(model, prompt_variant, prompt_label) %>%
    group_modify(~ {
      llm_metrics <- metric_summary(.x, "predict_cat", representation)
      ordinal_metrics <- metric_summary(.x, "ordinal_pred_cat", representation)
      modal_categories <- unique(na.omit(.x$previous_wave_modal_category))
      tibble(
        n_total = nrow(.x),
        modal_category = if (length(modal_categories) == 1L) {
          as.character(modal_categories[[1]])
        } else {
          "Varies by previous wave"
        },
        accuracy_majority = mean(.x$previous_wave_modal_correct, na.rm = TRUE),
        accuracy_prompt = llm_metrics$accuracy,
        accuracy_ordinal = ordinal_metrics$accuracy,
        prompt_minus_ordinal = llm_metrics$accuracy - ordinal_metrics$accuracy,
        prompt_mae = llm_metrics$mae,
        ordinal_mae = ordinal_metrics$mae,
        prompt_within_one = llm_metrics$within_one_accuracy,
        ordinal_within_one = ordinal_metrics$within_one_accuracy,
        n_ordinal_metric = ordinal_metrics$n_ordinal_metric
      )
    }) %>%
    ungroup()
}

compare_lag <- function(row_comparison, ordinal_predictions, representation) {
  joined <- row_comparison %>%
    select(-any_of(c("ordinal_pred_cat", "ordinal_model"))) %>%
    mutate(lfdn = as.character(lfdn), wave = as.character(wave)) %>%
    left_join(
      ordinal_predictions %>%
        mutate(lfdn = as.character(lfdn), wave = as.character(wave)) %>%
        select(lfdn, wave, wave_order, ordinal_pred_cat, ordinal_model),
      by = c("lfdn", "wave", "wave_order")
    ) %>%
    filter(!is.na(ordinal_pred_cat))

  joined %>%
    group_by(model, prompt_variant) %>%
    group_modify(~ {
      trajectory_metrics <- metric_summary(.x, "predict_cat", representation)
      ordinal_metrics <- metric_summary(.x, "ordinal_pred_cat", representation)
      modal_categories <- unique(na.omit(.x$previous_wave_modal_category))
      accuracy_majority <- mean(.x$previous_wave_modal_correct, na.rm = TRUE)
      accuracy_cf <- mean(.x$carry_forward_correct, na.rm = TRUE)
      tibble(
        n_total = nrow(.x),
        modal_category = if (length(modal_categories) == 1L) {
          as.character(modal_categories[[1]])
        } else {
          "Varies by previous wave"
        },
        accuracy_majority = accuracy_majority,
        accuracy_cf = accuracy_cf,
        accuracy_trajectory = trajectory_metrics$accuracy,
        accuracy_ordinal = ordinal_metrics$accuracy,
        trajectory_minus_majority = trajectory_metrics$accuracy - accuracy_majority,
        trajectory_minus_cf = trajectory_metrics$accuracy - accuracy_cf,
        trajectory_minus_ordinal = trajectory_metrics$accuracy - ordinal_metrics$accuracy,
        ordinal_minus_cf = ordinal_metrics$accuracy - accuracy_cf,
        trajectory_mae = trajectory_metrics$mae,
        ordinal_mae = ordinal_metrics$mae,
        trajectory_within_one = trajectory_metrics$within_one_accuracy,
        ordinal_within_one = ordinal_metrics$within_one_accuracy,
        n_ordinal_metric = ordinal_metrics$n_ordinal_metric
      )
    }) %>%
    ungroup()
}

covariates_comparisons <- list()
lag_comparisons <- list()

for (spec_index in seq_len(nrow(variant_spec))) {
  spec <- variant_spec[spec_index, ]
  csv_path <- file.path(
    ANALYSIS_INPUT_DIR, paste0("analyse_", spec$variant, ".csv")
  )
  message("ordinal statistical baselines: ", spec$variant)
  out_dir <- file.path(
    EVALUATION_ROOT, paste0("analysis_", spec$variant),
    "statistical_baselines"
  )
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (skip_model_run) {
    cov_predictions <- read_csv(
      file.path(out_dir, "covariates_only_ordinal_probit_predictions.csv"),
      show_col_types = FALSE
    )
    lag_predictions <- read_csv(
      file.path(out_dir, "lag_covariate_ordinal_probit_predictions.csv"),
      show_col_types = FALSE
    )
    cov_comparison <- compare_covariates_only(
      read_csv(
        file.path(out_dir, "covariates_only_nontrajectory_row_comparison.csv"),
        show_col_types = FALSE
      ),
      cov_predictions, spec$representation
    ) %>% mutate(Task = spec$task, .before = 1L)
    lag_comparison <- compare_lag(
      read_csv(
        file.path(out_dir, "trajectory_baseline_row_comparison.csv"),
        show_col_types = FALSE
      ),
      lag_predictions, spec$representation
    ) %>% mutate(Task = spec$task, .before = 1L)
    write_csv(
      cov_comparison,
      file.path(out_dir, "ordinal_covariates_only_comparison_overall.csv")
    )
    write_csv(
      lag_comparison,
      file.path(out_dir, "ordinal_lag_comparison_overall.csv")
    )
    covariates_comparisons[[length(covariates_comparisons) + 1L]] <-
      cov_comparison
    lag_comparisons[[length(lag_comparisons) + 1L]] <- lag_comparison
    rm(cov_predictions, lag_predictions, cov_comparison, lag_comparison)
    invisible(gc())
    next
  }

  raw <- prepare_raw_statistical_light(csv_path)
  dict <- attr(raw, "label_dict")
  category_levels <- ordered_category_levels(
    dict, c(raw$label_cat, raw$vorwelle_label_cat)
  )
  base_df <- raw %>% mutate(wave_order = parse_wave_order(wave))
  covariates <- infer_covariate_columns(base_df, spec$outcome_variable)
  covariates <- covariates[vapply(covariates, function(col) {
    length(unique(na.omit(base_df[[col]]))) >= 2L
  }, logical(1))]

  current_df <- base_df %>%
    select(lfdn, wave, wave_order, label_cat, all_of(covariates)) %>%
    group_by(lfdn, wave, wave_order) %>%
    summarise(
      label_cat = first_non_missing(label_cat),
      across(all_of(covariates), first_non_missing),
      .groups = "drop"
    ) %>%
    filter(!is.na(lfdn), !is.na(wave_order), !is.na(label_cat))

  transition_df <- base_df %>%
    select(lfdn, wave, wave_order, label_cat, vorwelle_label_cat,
           all_of(covariates)) %>%
    group_by(lfdn, wave, wave_order) %>%
    summarise(
      label_cat = first_non_missing(label_cat),
      vorwelle_label_cat = first_non_missing(vorwelle_label_cat),
      across(all_of(covariates), first_non_missing),
      .groups = "drop"
    ) %>%
    filter(!is.na(lfdn), !is.na(wave_order), !is.na(label_cat),
           !is.na(vorwelle_label_cat))

  cov_fit <- fit_expanding_ordinal(
    current_df, covariates, category_levels, "covariates_only"
  )
  lag_fit <- fit_expanding_ordinal(
    transition_df, c("vorwelle_label_cat", covariates), category_levels,
    "lag_covariates"
  )
  write_csv(cov_fit$predictions,
            file.path(out_dir, "covariates_only_ordinal_probit_predictions.csv"))
  write_csv(cov_fit$diagnostics,
            file.path(out_dir, "covariates_only_ordinal_probit_diagnostics.csv"))
  write_csv(cov_fit$thresholds,
            file.path(out_dir, "covariates_only_ordinal_probit_thresholds.csv"))
  write_csv(cov_fit$nominal_tests,
            file.path(out_dir, "covariates_only_ordinal_probit_nominal_tests.csv"))
  write_csv(lag_fit$predictions,
            file.path(out_dir, "lag_covariate_ordinal_probit_predictions.csv"))
  write_csv(lag_fit$diagnostics,
            file.path(out_dir, "lag_covariate_ordinal_probit_diagnostics.csv"))
  write_csv(lag_fit$thresholds,
            file.path(out_dir, "lag_covariate_ordinal_probit_thresholds.csv"))
  write_csv(lag_fit$nominal_tests,
            file.path(out_dir, "lag_covariate_ordinal_probit_nominal_tests.csv"))

  cov_predictions <- cov_fit$predictions
  lag_predictions <- lag_fit$predictions
  rm(raw, base_df, current_df, transition_df, cov_fit, lag_fit)
  invisible(gc())

  cov_row_path <- file.path(
    out_dir, "covariates_only_nontrajectory_row_comparison.csv"
  )
  lag_row_path <- file.path(out_dir, "trajectory_baseline_row_comparison.csv")
  cov_comparison <- compare_covariates_only(
    read_csv(cov_row_path, show_col_types = FALSE),
    cov_predictions, spec$representation
  ) %>% mutate(Task = spec$task, .before = 1L)
  rm(cov_predictions)
  invisible(gc())
  lag_comparison <- compare_lag(
    read_csv(lag_row_path, show_col_types = FALSE),
    lag_predictions, spec$representation
  ) %>% mutate(Task = spec$task, .before = 1L)
  write_csv(
    cov_comparison,
    file.path(out_dir, "ordinal_covariates_only_comparison_overall.csv")
  )
  write_csv(
    lag_comparison,
    file.path(out_dir, "ordinal_lag_comparison_overall.csv")
  )
  covariates_comparisons[[length(covariates_comparisons) + 1L]] <- cov_comparison
  lag_comparisons[[length(lag_comparisons) + 1L]] <- lag_comparison
  rm(lag_predictions, cov_comparison, lag_comparison)
  invisible(gc())
}

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
covariates_compact <- bind_rows(covariates_comparisons) %>%
  mutate(Model = short_model(model)) %>%
  arrange(Task, prompt_variant, Model)
lag_compact <- bind_rows(lag_comparisons) %>%
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

multinomial_snapshots <- c(
  "covariates_only_statistical_baseline_comparison.csv",
  "covariates_only_statistical_baseline_comparison_display.csv",
  "statistical_baseline_comparison.csv",
  "statistical_baseline_comparison_display.csv"
)
for (filename in multinomial_snapshots) {
  source_path <- file.path(TABLE_DIR, filename)
  snapshot_path <- file.path(TABLE_DIR, paste0("multinomial_", filename))
  if (file.exists(source_path) && !file.exists(snapshot_path)) {
    file.copy(source_path, snapshot_path)
  }
}

write_csv(covariates_compact,
          file.path(TABLE_DIR, "ordinal_covariates_only_statistical_baseline_comparison.csv"))
write_csv(covariates_display,
          file.path(TABLE_DIR, "ordinal_covariates_only_statistical_baseline_comparison_display.csv"))
write_csv(lag_compact,
          file.path(TABLE_DIR, "ordinal_statistical_baseline_comparison.csv"))
write_csv(lag_display,
          file.path(TABLE_DIR, "ordinal_statistical_baseline_comparison_display.csv"))

# Publication scripts read these generic paths. They now point to the primary
# ordinal-probit estimates; multinomial versions remain archived above.
write_csv(covariates_compact,
          file.path(TABLE_DIR, "covariates_only_statistical_baseline_comparison.csv"))
write_csv(covariates_display,
          file.path(TABLE_DIR, "covariates_only_statistical_baseline_comparison_display.csv"))
write_csv(lag_compact,
          file.path(TABLE_DIR, "statistical_baseline_comparison.csv"))
write_csv(lag_display,
          file.path(TABLE_DIR, "statistical_baseline_comparison_display.csv"))

message("Ordinal-probit statistical baselines complete.")
