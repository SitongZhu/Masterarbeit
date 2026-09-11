#!/usr/bin/env Rscript

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

prepare_raw_light <- function(csv_path) {
  raw <- readr::read_csv(
    csv_path,
    col_select = tidyselect::any_of(c(
      "wave_id_from_list", "wave", "label", "predict", "llm_model", "model",
      "prompt_variant", "vorwelle_label"
    )),
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
    } else NA_character_
  )

  dict <- build_label_dict(raw$label)
  raw$label_cat <- match_to_category(raw$label, dict)
  raw$predict_cat <- match_to_category(raw$predict, dict)
  raw$vorwelle_label_cat <- if ("vorwelle_label" %in% names(raw)) {
    match_to_category(raw$vorwelle_label, dict)
  } else {
    NA_character_
  }
  raw$label_num <- encode_num(raw$label_cat, dict)
  raw$predict_num <- encode_num(raw$predict_cat, dict)
  raw$vorwelle_label_num <- encode_num(raw$vorwelle_label_cat, dict)
  raw
}

csv_files <- list.files(
  ANALYSIS_INPUT_DIR,
  pattern = "^analyse_.+\\.csv$",
  full.names = TRUE
)
if (length(csv_files) == 0L) {
  stop("No analyse_*.csv files found in ", ANALYSIS_INPUT_DIR, ".")
}

variant_filter <- commandArgs(trailingOnly = TRUE)
env_filter <- Sys.getenv("ANALYSE_VARIANTS", unset = "")
if (length(variant_filter) == 0L && nzchar(env_filter)) {
  variant_filter <- unlist(strsplit(env_filter, ",", fixed = TRUE))
}
variant_filter <- trimws(variant_filter)
variant_filter <- variant_filter[nzchar(variant_filter)]
if (length(variant_filter) > 0L) {
  keep <- sub("^analyse_(.+)\\.csv$", "\\1", basename(csv_files)) %in%
    variant_filter
  csv_files <- csv_files[keep]
}

for (csv_path in csv_files) {
  variant <- sub("^analyse_(.+)\\.csv$", "\\1", basename(csv_path))
  message("prior-state persistence: ", variant)
  raw <- prepare_raw_light(csv_path)
  out_dir <- file.path(EVALUATION_OUTPUT_ROOT, paste0("analysis_", variant),
                       "trajectory_analysis", "prior_state_persistence")
  run_module_prior_state_persistence(raw, out_dir)
}

message("prior-state persistence generation complete.")
