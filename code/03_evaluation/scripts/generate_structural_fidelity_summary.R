#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
  library(purrr)
  library(tidyr)
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

load_evaluation_definitions(file.path(
  PROJECT_ROOT, "03_evaluation", "scripts", "analyse_all_variants.R"
))

INPUT_DIR <- file.path(PROJECT_ROOT, "data", "analysis_inputs")
TABLE_DIR <- file.path(PROJECT_ROOT, "outputs", "evaluation", "tables")
dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)

task_spec <- tibble::tribble(
  ~variant, ~task, ~scale_max,
  "1290_original_scale", "Climate-growth original scale", 7L,
  "1500_original_scale", "Left-right original scale", 11L
)

structural_covariates <- c(
  "kp_020", "kp_780", "kp_820", "pi_2280", "pi_2320", "pi_2591"
)

prompt_labels <- c(
  baseline_notime = "No-time",
  trajectory = "Trajectory"
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

read_structural_input <- function(spec) {
  path <- file.path(INPUT_DIR, paste0("analyse_", spec$variant, ".csv"))
  raw <- read_csv(
    path,
    col_select = c(
      any_of(c("wave_id_from_list", "wave", "llm_model", "model",
               "prompt_variant", "label", "predict")),
      all_of(structural_covariates)
    ),
    show_col_types = FALSE,
    progress = FALSE
  )
  raw <- raw %>%
    mutate(
      wave = clean_text(if ("wave_id_from_list" %in% names(.)) {
        wave_id_from_list
      } else {
        wave
      }),
      model = clean_text(if ("llm_model" %in% names(.)) {
        coalesce(llm_model, if ("model" %in% names(.)) model else NA_character_)
      } else {
        model
      }),
      prompt_variant = clean_text(prompt_variant),
      label = clean_text(label),
      predict = clean_text(predict)
    ) %>%
    filter(prompt_variant %in% names(prompt_labels))

  dict <- build_label_dict(raw$label)
  raw %>%
    mutate(
      human_category = match_to_category(label, dict),
      llm_category = match_to_category(predict, dict),
      human_response = encode_num(human_category, dict),
      llm_response = encode_num(llm_category, dict),
      model_label = short_model(model),
      prompt_label = unname(prompt_labels[prompt_variant]),
      task = spec$task,
      scale_max = spec$scale_max
    )
}

full_rank_design <- function(data) {
  design_data <- data %>%
    mutate(
      wave = factor(wave),
      across(all_of(structural_covariates), factor)
    )
  design_formula <- as.formula(paste(
    "~", paste(c(structural_covariates, "wave"), collapse = " + ")
  ))
  design_full <- model.matrix(design_formula, data = design_data)
  intercept <- which(colnames(design_full) == "(Intercept)")
  if (length(intercept) > 0L) {
    design_full <- design_full[, -intercept, drop = FALSE]
  }
  design_qr <- qr(design_full, tol = 1e-7, LAPACK = FALSE)
  independent <- sort(design_qr$pivot[seq_len(design_qr$rank)])
  design <- design_full[, independent, drop = FALSE]
  original_names <- colnames(design)
  model_names <- paste0("x", seq_len(ncol(design)))
  colnames(design) <- model_names
  list(
    design = design,
    model_names = model_names,
    original_names = original_names,
    covariate_names = model_names[!str_detect(original_names, "^wave")]
  )
}

fit_ols <- function(y, design) {
  fit <- lm.fit(cbind(`(Intercept)` = 1, design), y)
  coefficients <- fit$coefficients[-1L]
  names(coefficients) <- colnames(design)
  coefficients
}

fit_ordinal <- function(y, design, scale_max) {
  observed_levels <- sort(unique(y[is.finite(y)]))
  if (length(observed_levels) < 2L) {
    stop("Ordinal structural fit requires at least two observed categories.")
  }
  if (length(observed_levels) == 2L) {
    fit <- glm.fit(
      x = cbind(`(Intercept)` = 1, design),
      y = as.integer(y == observed_levels[2L]),
      family = binomial(link = "probit"),
      control = glm.control(maxit = 500L, epsilon = 1e-8)
    )
    coefficients <- fit$coefficients[-1L]
    names(coefficients) <- colnames(design)
    return(list(
      coefficients = coefficients,
      convergence = as.integer(!isTRUE(fit$converged)),
      thresholds_ordered = TRUE
    ))
  }
  fit_data <- data.frame(
    outcome = ordered(y, levels = observed_levels),
    design,
    check.names = FALSE
  )
  outcome_counts <- table(fit_data$outcome)
  cumulative_share <- cumsum(outcome_counts) / sum(outcome_counts)
  threshold_start <- qnorm(pmin(
    pmax(cumulative_share[-length(cumulative_share)], 1e-6),
    1 - 1e-6
  ))
  start_values <- c(rep(0, ncol(design)), threshold_start)
  formula <- as.formula(paste(
    "outcome ~", paste(colnames(design), collapse = " + ")
  ))
  fit <- suppressWarnings(MASS::polr(
    formula,
    data = fit_data,
    method = "probit",
    start = start_values,
    Hess = FALSE,
    model = FALSE,
    control = list(maxit = 500L, reltol = 1e-8)
  ))
  list(
    coefficients = coef(fit),
    convergence = as.integer(fit$convergence),
    thresholds_ordered = length(fit$zeta) < 2L || all(diff(fit$zeta) > 0)
  )
}

coefficient_metrics <- function(human, llm, terms) {
  human <- human[terms]
  llm <- llm[terms]
  valid <- is.finite(human) & is.finite(llm)
  human <- human[valid]
  llm <- llm[valid]
  tibble(
    coefficient_count = length(human),
    coefficient_correlation = if (length(human) >= 3L &&
        sd(human) > 0 && sd(llm) > 0) cor(human, llm) else NA_real_,
    sign_agreement = if (length(human) > 0L) {
      mean(sign(human) == sign(llm))
    } else {
      NA_real_
    }
  )
}

fit_stratum <- function(data, task, prompt, model, scale_max) {
  analysis <- data %>%
    filter(
      .data$task == .env$task,
      .data$prompt_label == .env$prompt,
      .data$model_label == .env$model
    ) %>%
    select(
      human_response, llm_response, wave,
      all_of(structural_covariates)
    ) %>%
    filter(
      !is.na(human_response), !is.na(llm_response), !is.na(wave),
      if_all(all_of(structural_covariates), ~ !is.na(.x))
    )

  if (nrow(analysis) < 50L || n_distinct(analysis$wave) < 2L) return(NULL)
  design_info <- full_rank_design(analysis)
  design <- design_info$design
  if (length(design_info$covariate_names) < 3L) return(NULL)

  ols_h <- fit_ols(analysis$human_response, design)
  ols_l <- fit_ols(analysis$llm_response, design)
  ordinal_h <- tryCatch(
    fit_ordinal(analysis$human_response, design, scale_max),
    error = function(e) NULL
  )
  ordinal_l <- tryCatch(
    fit_ordinal(analysis$llm_response, design, scale_max),
    error = function(e) NULL
  )
  if (is.null(ordinal_h) || is.null(ordinal_l)) return(NULL)

  ols_metrics <- coefficient_metrics(
    ols_h, ols_l, design_info$covariate_names
  ) %>% mutate(method = "OLS")
  ordinal_metrics <- coefficient_metrics(
    ordinal_h$coefficients, ordinal_l$coefficients,
    design_info$covariate_names
  ) %>% mutate(method = "Ordinal probit")

  metrics <- bind_rows(ols_metrics, ordinal_metrics) %>%
    mutate(
      task = .env$task,
      prompt = .env$prompt,
      model = .env$model,
      n = nrow(analysis),
      waves = n_distinct(analysis$wave),
      ordinal_human_convergence = ordinal_h$convergence,
      ordinal_llm_convergence = ordinal_l$convergence,
      ordinal_human_thresholds_ordered = ordinal_h$thresholds_ordered,
      ordinal_llm_thresholds_ordered = ordinal_l$thresholds_ordered,
      .before = 1L
    )

  term_map <- tibble(
    model_term = design_info$model_names,
    design_term = design_info$original_names
  ) %>% filter(model_term %in% design_info$covariate_names)
  term_rows <- bind_rows(
    tibble(
      model_term = design_info$covariate_names,
      human_coefficient = ols_h[design_info$covariate_names],
      llm_coefficient = ols_l[design_info$covariate_names],
      method = "OLS"
    ),
    tibble(
      model_term = design_info$covariate_names,
      human_coefficient = ordinal_h$coefficients[design_info$covariate_names],
      llm_coefficient = ordinal_l$coefficients[design_info$covariate_names],
      method = "Ordinal probit"
    )
  ) %>%
    left_join(term_map, by = "model_term") %>%
    mutate(
      task = .env$task, prompt = .env$prompt, model = .env$model,
      n = nrow(analysis),
      .before = 1L
    )

  list(metrics = metrics, terms = term_rows)
}

all_data <- map2_dfr(seq_len(nrow(task_spec)), task_spec$variant, function(i, v) {
  message("Reading structural input: ", v)
  read_structural_input(task_spec[i, ])
})

strata <- all_data %>%
  distinct(task, prompt_label, model_label, scale_max) %>%
  arrange(task, prompt_label, model_label)

results <- pmap(strata, function(task, prompt_label, model_label, scale_max) {
  message("Structural fits: ", task, " | ", prompt_label, " | ", model_label)
  fit_stratum(all_data, task, prompt_label, model_label, scale_max)
})
results <- compact(results)
if (length(results) == 0L) stop("No structural-fidelity strata were estimated.")

stratum_metrics <- map_dfr(results, "metrics")
term_coefficients <- map_dfr(results, "terms")

summary_table <- stratum_metrics %>%
  group_by(task, prompt, method) %>%
  summarise(
    configurations = n(),
    n_min = min(n),
    n_max = max(n),
    median_coefficient_correlation = median(
      coefficient_correlation, na.rm = TRUE
    ),
    min_coefficient_correlation = min(coefficient_correlation, na.rm = TRUE),
    max_coefficient_correlation = max(coefficient_correlation, na.rm = TRUE),
    median_sign_agreement = median(sign_agreement, na.rm = TRUE),
    min_sign_agreement = min(sign_agreement, na.rm = TRUE),
    max_sign_agreement = max(sign_agreement, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(task, prompt, method)

method_consistency <- stratum_metrics %>%
  select(task, prompt, model, method,
         coefficient_correlation, sign_agreement) %>%
  mutate(method = if_else(method == "Ordinal probit", "ordinal", "ols")) %>%
  pivot_wider(
    names_from = method,
    values_from = c(coefficient_correlation, sign_agreement),
    names_sep = "_"
  ) %>%
  summarise(
    strata = n(),
    correlation_between_method_specific_correlations = cor(
      coefficient_correlation_ols,
      coefficient_correlation_ordinal,
      use = "complete.obs"
    ),
    correlation_between_method_specific_sign_agreement = cor(
      sign_agreement_ols,
      sign_agreement_ordinal,
      use = "complete.obs"
    ),
    same_correlation_direction = mean(
      sign(coefficient_correlation_ols) ==
        sign(coefficient_correlation_ordinal),
      na.rm = TRUE
    )
  )

write_csv(
  stratum_metrics,
  file.path(TABLE_DIR, "structural_fidelity_stratum_metrics.csv")
)
write_csv(
  term_coefficients,
  file.path(TABLE_DIR, "structural_fidelity_term_coefficients.csv")
)
write_csv(
  summary_table,
  file.path(TABLE_DIR, "structural_fidelity_summary.csv")
)
write_csv(
  method_consistency,
  file.path(TABLE_DIR, "structural_fidelity_method_consistency.csv")
)

message("Wrote harmonized structural-fidelity summaries to: ", TABLE_DIR)
