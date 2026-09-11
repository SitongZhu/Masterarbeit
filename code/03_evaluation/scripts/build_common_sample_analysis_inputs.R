#!/usr/bin/env Rscript
# Build same-database/common-sample analyse_<variant>.csv files.
#
# The output CSVs keep the original analyse_<variant>.csv columns and rows
# only for respondent-wave records that appear under all four prompt variants
# within the same variant x model x wave stratum.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
})

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "data"))) {
  stop("Run this script from the code project root.")
}

SOURCE_INPUT_DIR <- Sys.getenv(
  "COMMON_SAMPLE_SOURCE_INPUT_DIR",
  unset = file.path(PROJECT_ROOT, "data", "analysis_inputs")
)
COMMON_SAMPLE_INPUT_DIR <- Sys.getenv(
  "COMMON_SAMPLE_ANALYSIS_INPUT_DIR",
  unset = file.path(PROJECT_ROOT, "data", "analysis_inputs_same_database")
)
SOURCE_INPUT_DIR <- normalizePath(SOURCE_INPUT_DIR, winslash = "/",
                                  mustWork = TRUE)
COMMON_SAMPLE_INPUT_DIR <- normalizePath(COMMON_SAMPLE_INPUT_DIR,
                                         winslash = "/",
                                         mustWork = FALSE)
dir.create(COMMON_SAMPLE_INPUT_DIR, showWarnings = FALSE, recursive = TRUE)

REQUIRED_PROMPTS <- c("baseline", "baseline_notime", "tanchored", "trajectory")
DEFAULT_VARIANTS <- c("1290", "1290_original_scale", "1500", "1500_original_scale")

clean_text <- function(x) {
  x <- as.character(x)
  x <- str_squish(x)
  x[!is.na(x) & x == ""] <- NA_character_
  x
}

parse_wave_order <- function(wave) {
  suppressWarnings(as.integer(str_extract(wave, "[0-9]+")))
}

resolve_variants <- function() {
  env_variants <- Sys.getenv("ANALYSE_VARIANTS", unset = "")
  if (!nzchar(env_variants)) return(DEFAULT_VARIANTS)
  variants <- trimws(unlist(strsplit(env_variants, ",", fixed = TRUE)))
  variants[nzchar(variants)]
}

add_common_sample_keys <- function(df) {
  df %>%
    mutate(
      .row_id = row_number(),
      .wave_key = clean_text(
        if ("wave_id_from_list" %in% names(.)) {
          wave_id_from_list
        } else if ("wave" %in% names(.)) {
          wave
        } else {
          NA_character_
        }
      ),
      .wave_order_key = parse_wave_order(.wave_key),
      .model_key = clean_text(
        if ("llm_model" %in% names(.)) {
          coalesce(llm_model, if ("model" %in% names(.)) model else NA_character_)
        } else if ("model" %in% names(.)) {
          model
        } else {
          NA_character_
        }
      ),
      .respondent_key = clean_text(
        if ("lfdn" %in% names(.)) {
          lfdn
        } else if ("id" %in% names(.)) {
          id
        } else {
          NA_character_
        }
      ),
      .prompt_key = clean_text(prompt_variant)
    )
}

summarise_rows <- function(df, label) {
  df %>%
    count(.model_key, .prompt_key, .wave_key, .wave_order_key,
          name = paste0("n_", label)) %>%
    rename(model = .model_key, prompt_variant = .prompt_key,
           wave = .wave_key, wave_order = .wave_order_key)
}

build_one_variant <- function(variant) {
  source_csv <- file.path(SOURCE_INPUT_DIR, paste0("analyse_", variant, ".csv"))
  out_csv <- file.path(COMMON_SAMPLE_INPUT_DIR, paste0("analyse_", variant, ".csv"))
  if (!file.exists(source_csv)) {
    stop("Missing source CSV: ", source_csv)
  }

  message("Building same-database input for ", basename(source_csv))
  raw <- read_csv(source_csv, show_col_types = FALSE, progress = FALSE)
  original_cols <- names(raw)
  keyed <- add_common_sample_keys(raw)

  before <- summarise_rows(keyed, "full")

  eligible <- keyed %>%
    filter(
      !is.na(.wave_key),
      !is.na(.model_key),
      !is.na(.respondent_key),
      .prompt_key %in% REQUIRED_PROMPTS
    )

  common_keys <- eligible %>%
    distinct(.model_key, .wave_key, .wave_order_key,
             .respondent_key, .prompt_key) %>%
    group_by(.model_key, .wave_key, .wave_order_key, .respondent_key) %>%
    summarise(
      n_required_prompts_present = sum(REQUIRED_PROMPTS %in% .prompt_key),
      prompts_present = paste(sort(unique(.prompt_key)), collapse = ";"),
      .groups = "drop"
    ) %>%
    filter(n_required_prompts_present == length(REQUIRED_PROMPTS))

  filtered <- keyed %>%
    semi_join(
      common_keys,
      by = c(".model_key", ".wave_key", ".wave_order_key", ".respondent_key")
    ) %>%
    filter(.prompt_key %in% REQUIRED_PROMPTS) %>%
    arrange(.row_id)

  after <- summarise_rows(filtered, "same_database")

  retention <- before %>%
    left_join(after, by = c("model", "prompt_variant", "wave", "wave_order")) %>%
    mutate(
      variant = variant,
      n_same_database = coalesce(n_same_database, 0L),
      n_dropped = n_full - n_same_database,
      same_database_share = n_same_database / pmax(n_full, 1L)
    ) %>%
    select(variant, model, prompt_variant, wave, wave_order,
           n_full, n_same_database, n_dropped, same_database_share) %>%
    arrange(variant, model, wave_order, prompt_variant)

  common_size <- common_keys %>%
    count(.model_key, .wave_key, .wave_order_key,
          name = "n_common_respondent_wave") %>%
    transmute(
      variant = variant,
      model = .model_key,
      wave = .wave_key,
      wave_order = .wave_order_key,
      n_common_respondent_wave
    ) %>%
    arrange(variant, model, wave_order)

  filtered %>%
    select(all_of(original_cols)) %>%
    write_csv(out_csv)

  message("  wrote ", out_csv, " (", nrow(filtered), " rows)")
  list(retention = retention, common_size = common_size)
}

variants <- resolve_variants()
message("Source inputs: ", SOURCE_INPUT_DIR)
message("Same-database inputs: ", COMMON_SAMPLE_INPUT_DIR)
message("Variants: ", paste(variants, collapse = ", "))

results <- lapply(variants, build_one_variant)
retention <- bind_rows(lapply(results, `[[`, "retention"))
common_size <- bind_rows(lapply(results, `[[`, "common_size"))

write_csv(retention,
          file.path(COMMON_SAMPLE_INPUT_DIR, "same_database_retention_summary.csv"))
write_csv(common_size,
          file.path(COMMON_SAMPLE_INPUT_DIR, "same_database_set_sizes.csv"))

message("Same-database analysis inputs complete.")
