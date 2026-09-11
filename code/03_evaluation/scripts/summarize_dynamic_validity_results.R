#!/usr/bin/env Rscript

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "outputs", "evaluation"))) {
  stop("Run this script from the code project root after evaluation outputs exist.")
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tidyr)
})

EVALUATION_OUTPUT_ROOT <- Sys.getenv(
  "EVALUATION_OUTPUT_ROOT",
  unset = file.path(PROJECT_ROOT, "outputs", "evaluation")
)
EVALUATION_OUTPUT_ROOT <- normalizePath(EVALUATION_OUTPUT_ROOT, winslash = "/",
                                        mustWork = TRUE)

ANALYSIS_INPUT_DIR <- Sys.getenv(
  "ANALYSIS_INPUT_DIR",
  unset = file.path(PROJECT_ROOT, "data", "analysis_inputs")
)
ANALYSIS_INPUT_DIR <- normalizePath(ANALYSIS_INPUT_DIR, winslash = "/",
                                    mustWork = TRUE)

TABLE_DIR <- file.path(EVALUATION_OUTPUT_ROOT, "tables")
dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)

variants <- tibble::tribble(
  ~variant, ~task,
  "1290", "Climate-growth grouped",
  "1290_original_scale", "Climate-growth original scale",
  "1500", "Left-right grouped",
  "1500_original_scale", "Left-right original scale"
)

read_metric <- function(variant, subdir, file) {
  path <- file.path(EVALUATION_OUTPUT_ROOT, paste0("analysis_", variant),
                    "trajectory_analysis", subdir, file)
  read_csv(path, show_col_types = FALSE) %>%
    mutate(variant = variant, .before = 1)
}

read_statistical_baseline <- function(variant) {
  path <- file.path(
    EVALUATION_OUTPUT_ROOT, "manuscript", "tables",
    "rq2_ordinal_prior_state_comparison.csv"
  )
  empty <- tibble(
    variant = character(),
    model = character(),
    prompt_variant = character(),
    accuracy_majority = double(),
    accuracy_statistical = double(),
    accuracy_statistical_available = double(),
    trajectory_minus_majority = double(),
    trajectory_minus_statistical = double()
  )
  if (!file.exists(path)) return(empty)
  read_csv(path, show_col_types = FALSE) %>%
    filter(.data$variant == .env$variant) %>%
    transmute(
      variant, model, prompt_variant,
      accuracy_majority,
      accuracy_statistical = accuracy_ordinal,
      accuracy_statistical_available = accuracy_ordinal,
      trajectory_minus_majority,
      trajectory_minus_statistical = trajectory_minus_ordinal
    )
}

summary <- variants %>%
  mutate(data = map(variant, function(v) {
    self_corr <- read_metric(v, "self_trajectory",
                             "trajectory_delta_correlation.csv") %>%
      filter(prompt_variant == "trajectory") %>%
      select(variant, model, prompt_variant,
             rho_self = spearman_rho, n_self_corr = n)
    anchor_corr <- read_metric(v, "anchored_change",
                               "trajectory_delta_correlation.csv") %>%
      filter(prompt_variant == "trajectory") %>%
      select(variant, model, prompt_variant,
             rho_anchor = spearman_rho, n_anchor_corr = n)
    self_ccr <- read_metric(v, "self_trajectory",
                            "trajectory_change_capture_metrics.csv") %>%
      filter(prompt_variant == "trajectory") %>%
      select(variant, model, prompt_variant,
             ccr_self = ccr, cda_self = cda, dccr_self = dccr,
             n_self_total = n_total,
             n_self_changed = n_rare,
             n_self_captured = n_captured)
    anchor_ccr <- read_metric(v, "anchored_change",
                              "trajectory_change_capture_metrics.csv") %>%
      filter(prompt_variant == "trajectory") %>%
      select(variant, model, prompt_variant,
             ccr_anchor = ccr, cda_anchor = cda, dccr_anchor = dccr,
             n_anchor_total = n_total,
             n_anchor_changed = n_rare,
             n_anchor_captured = n_captured)
    persistence <- read_metric(v, "prior_state_persistence",
                               "prior_state_persistence_overall.csv") %>%
      filter(prompt_variant == "trajectory") %>%
      select(variant, model, prompt_variant,
             n_persistence = n_total,
             accuracy_cf, accuracy_trajectory, a_previous,
             trajectory_minus_cf, previous_agreement_minus_cf)
    statistical <- read_statistical_baseline(v) %>%
      filter(prompt_variant == "trajectory")

    self_corr %>%
      full_join(anchor_corr, by = c("variant", "model", "prompt_variant")) %>%
      full_join(self_ccr, by = c("variant", "model", "prompt_variant")) %>%
      full_join(anchor_ccr, by = c("variant", "model", "prompt_variant")) %>%
      full_join(persistence, by = c("variant", "model", "prompt_variant")) %>%
      full_join(statistical, by = c("variant", "model", "prompt_variant"))
  })) %>%
  select(task, data) %>%
  unnest(data) %>%
  mutate(model_short = case_when(
    str_detect(model, "Mistral") ~ "Mistral-7B",
    str_detect(model, "Llama-3_3-70B") ~ "Llama-3.3-70B",
    str_detect(model, "72B") ~ "Qwen2.5-72B",
    str_detect(model, "32B") ~ "Qwen2.5-32B",
    str_detect(model, "7B") ~ "Qwen2.5-7B",
    TRUE ~ model
  )) %>%
  arrange(factor(variant, levels = variants$variant), model_short)

out <- file.path(EVALUATION_OUTPUT_ROOT,
                 "dynamic_validity_prior_state_summary.csv")
write_csv(summary, out)

model_levels <- c(
  "Mistral-7B", "Qwen2.5-32B", "Qwen2.5-7B", "Qwen2.5-72B",
  "Llama-3.3-70B"
)

format3 <- function(x) {
  ifelse(is.na(x), NA_character_, sprintf("%.3f", x))
}

format_gain <- function(x) {
  ifelse(
    is.na(x),
    NA_character_,
    ifelse(x > 0, paste0("+", sprintf("%.3f", x)), sprintf("%.3f", x))
  )
}

write_markdown_table <- function(data, path) {
  escape_cell <- function(x) {
    x <- ifelse(is.na(x), "", as.character(x))
    str_replace_all(x, fixed("|"), "\\\\|")
  }
  rows <- apply(data, 1, function(row) {
    paste0("| ", paste(escape_cell(row), collapse = " | "), " |")
  })
  header <- paste0("| ", paste(names(data), collapse = " | "), " |")
  rule <- paste0("| ", paste(rep("---", ncol(data)), collapse = " | "), " |")
  writeLines(c(header, rule, rows), path, useBytes = TRUE)
}

write_latex_table <- function(data, path) {
  escape_cell <- function(x) {
    x <- ifelse(is.na(x), "", as.character(x))
    x <- str_replace_all(x, fixed("&"), "\\\\&")
    x <- str_replace_all(x, fixed("%"), "\\\\%")
    x <- str_replace_all(x, fixed("_"), "\\\\_")
    x
  }
  rows <- apply(data, 1, function(row) {
    paste0(paste(escape_cell(row), collapse = " & "), " \\\\")
  })
  header <- paste0(
    paste(escape_cell(names(data)), collapse = " & "),
    " \\\\"
  )
  alignment <- paste0("ll", paste(rep("r", ncol(data) - 2L),
                                  collapse = ""))
  writeLines(
    c(
      paste0("\\begin{tabular}{", alignment, "}"),
      "\\toprule",
      header,
      "\\midrule",
      rows,
      "\\bottomrule",
      "\\end{tabular}"
    ),
    path,
    useBytes = TRUE
  )
}

dynamic_display <- summary %>%
  mutate(
    task = factor(task, levels = variants$task),
    model_short = factor(model_short, levels = model_levels)
  ) %>%
  arrange(task, model_short) %>%
  transmute(
    Task = as.character(task),
    Model = as.character(model_short),
    `Traj. acc.` = format3(accuracy_trajectory),
    `CF acc.` = format3(accuracy_cf),
    `Gain over CF` = format_gain(trajectory_minus_cf),
    `Prev. agree` = format3(a_previous),
    rho_self = format3(rho_self),
    rho_anchor = format3(rho_anchor),
    CCR_self = format3(ccr_self),
    CDA_self = format3(cda_self),
    DCCR_self = format3(dccr_self),
    CCR_anchor = format3(ccr_anchor),
    CDA_anchor = format3(cda_anchor),
    DCCR_anchor = format3(dccr_anchor)
  )

dynamic_csv <- file.path(TABLE_DIR, "dynamic_diagnostics_table.csv")
write_csv(dynamic_display, dynamic_csv)
write_markdown_table(
  dynamic_display,
  file.path(TABLE_DIR, "dynamic_diagnostics_table.md")
)
write_latex_table(
  dynamic_display,
  file.path(TABLE_DIR, "dynamic_diagnostics_table.tex")
)

load_evaluation_helpers <- function() {
  script_path <- file.path(
    PROJECT_ROOT, "03_evaluation", "scripts", "analyse_all_variants.R"
  )
  lines <- readLines(script_path, warn = FALSE)
  boundary <- grep("^csv_files <-", lines)[1]
  if (is.na(boundary) || boundary <= 1L) {
    stop("Could not find execution boundary in ", script_path)
  }
  eval(parse(text = lines[seq_len(boundary - 1L)]), envir = globalenv())
}

load_evaluation_helpers()

read_stable_changing <- function(variant, task) {
  path <- file.path(ANALYSIS_INPUT_DIR, paste0("analyse_", variant, ".csv"))
  if (!file.exists(path)) {
    stop("Missing analysis input: ", path)
  }

  raw <- read_csv(
    path,
    col_select = any_of(c(
      "label", "predict", "llm_model", "model", "prompt_variant",
      "vorwelle_label"
    )),
    show_col_types = FALSE,
    progress = FALSE
  )
  dict <- build_label_dict(raw$label)

  raw %>%
    mutate(
      model = coalesce(
        if ("llm_model" %in% names(.)) as.character(llm_model)
        else NA_character_,
        if ("model" %in% names(.)) as.character(model)
        else NA_character_
      ),
      label_cat = match_to_category(label, dict),
      predict_cat = match_to_category(predict, dict),
      previous_cat = match_to_category(vorwelle_label, dict),
      prompt_variant = str_to_lower(clean_text(prompt_variant))
    ) %>%
    filter(
      prompt_variant == "trajectory",
      !is.na(model),
      !is.na(label_cat),
      !is.na(previous_cat)
    ) %>%
    mutate(
      human_stable = label_cat == previous_cat,
      prediction_correct = !is.na(predict_cat) &
        predict_cat == label_cat
    ) %>%
    group_by(model) %>%
    summarise(
      n_stable = sum(human_stable),
      n_changed = sum(!human_stable),
      stable_share = mean(human_stable),
      accuracy_stable = sum(prediction_correct & human_stable) /
        sum(human_stable),
      accuracy_changed = sum(prediction_correct & !human_stable) /
        sum(!human_stable),
      .groups = "drop"
    ) %>%
    mutate(variant = variant, task = task, .before = 1)
}

stable_changing <- map2_dfr(
  variants$variant,
  variants$task,
  read_stable_changing
) %>%
  mutate(
    model_short = case_when(
      str_detect(model, "Mistral") ~ "Mistral-7B",
      str_detect(model, "Llama-3_3-70B") ~ "Llama-3.3-70B",
      str_detect(model, "72B") ~ "Qwen2.5-72B",
      str_detect(model, "32B") ~ "Qwen2.5-32B",
      str_detect(model, "7B") ~ "Qwen2.5-7B",
      TRUE ~ model
    )
  ) %>%
  left_join(
    summary %>%
      select(variant, model, ccr_anchor),
    by = c("variant", "model")
  ) %>%
  mutate(
    task = factor(task, levels = variants$task),
    model_short = factor(model_short, levels = model_levels)
  ) %>%
  arrange(task, model_short)

stable_display <- stable_changing %>%
  transmute(
    Task = as.character(task),
    Model = as.character(model_short),
    `Stable N` = format(n_stable, big.mark = ",", scientific = FALSE,
                        trim = TRUE),
    `Changed N` = format(n_changed, big.mark = ",", scientific = FALSE,
                         trim = TRUE),
    `Stable share` = format3(stable_share),
    `Acc. stable` = format3(accuracy_stable),
    `Acc. changed` = format3(accuracy_changed),
    `Stable-change gap` = format3(accuracy_stable - accuracy_changed),
    `False persistence among changers` = format3(1 - ccr_anchor),
    `Anchored CCR` = format3(ccr_anchor)
  )

stable_csv <- file.path(TABLE_DIR, "stable_changing_split_table.csv")
write_csv(stable_display, stable_csv)
write_csv(
  stable_display,
  file.path(TABLE_DIR, "stable_changing_split_table_display.csv")
)
write_markdown_table(
  stable_display,
  file.path(TABLE_DIR, "stable_changing_split_table.md")
)
write_latex_table(
  stable_display,
  file.path(TABLE_DIR, "stable_changing_split_table.tex")
)

print(
  summary %>%
    select(task, model_short, rho_self, rho_anchor,
           ccr_self, cda_self, dccr_self,
           ccr_anchor, cda_anchor, dccr_anchor,
           accuracy_cf, accuracy_trajectory, a_previous,
           accuracy_majority, accuracy_statistical) %>%
    mutate(across(where(is.numeric), ~ round(.x, 3))),
  n = Inf
)
message("wrote ", out)
message("wrote ", dynamic_csv)
message("wrote ", stable_csv)
