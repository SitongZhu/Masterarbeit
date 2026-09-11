#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(stringr)
})

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
INPUT_DIR <- file.path(PROJECT_ROOT, "data", "analysis_inputs")
HDATA_DIR <- file.path(PROJECT_ROOT, "data", "intermediate_hdata")
AUDIT_DIR <- file.path(
  PROJECT_ROOT, "outputs", "evaluation", "manuscript", "audits"
)
dir.create(AUDIT_DIR, recursive = TRUE, showWarnings = FALSE)

variants <- c("1290", "1290_original_scale", "1500", "1500_original_scale")

clean_value <- function(x) {
  x <- str_squish(as.character(x))
  x[!is.na(x) & x == ""] <- NA_character_
  x
}

audit_variant <- function(variant) {
  rds_path <- file.path(
    HDATA_DIR, paste0("wave_list_for_llm_join_", variant, ".rds")
  )
  csv_path <- file.path(INPUT_DIR, paste0("analyse_", variant, ".csv"))
  if (!file.exists(rds_path) || !file.exists(csv_path)) {
    stop("Missing lag-audit input for variant ", variant)
  }

  wave_list <- readRDS(rds_path)
  ordered_waves <- names(wave_list)
  ordered_waves <- ordered_waves[order(as.integer(str_extract(
    ordered_waves, "[0-9]+"
  )))]
  previous_map <- tibble(
    wave = ordered_waves,
    expected_previous_wave = c(NA_character_, head(ordered_waves, -1L))
  )
  human_lookup <- bind_rows(wave_list, .id = "wave") %>%
    transmute(
      lfdn = as.character(lfdn),
      expected_previous_wave = wave,
      expected_previous_label = clean_value(outcome)
    )

  expected <- bind_rows(wave_list, .id = "wave") %>%
    transmute(lfdn = as.character(lfdn), wave) %>%
    left_join(previous_map, by = "wave") %>%
    left_join(
      human_lookup,
      by = c("lfdn", "expected_previous_wave")
    )

  observed <- read_csv(
    csv_path,
    col_select = any_of(c(
      "lfdn", "wave_id_from_list", "previous_wave_id", "vorwelle_label",
      "llm_model", "prompt_variant"
    )),
    show_col_types = FALSE,
    progress = FALSE
  ) %>%
    transmute(
      lfdn = as.character(lfdn),
      wave = wave_id_from_list,
      previous_wave_id,
      previous_label = clean_value(vorwelle_label),
      model = llm_model,
      prompt_variant
    ) %>%
    filter(prompt_variant == "trajectory", !is.na(model)) %>%
    left_join(expected, by = c("lfdn", "wave")) %>%
    mutate(
      wave_link_correct = previous_wave_id == expected_previous_wave,
      label_link_correct = previous_label == expected_previous_label,
      wave_link_correct = coalesce(wave_link_correct, FALSE),
      label_link_correct = coalesce(label_link_correct, FALSE)
    )

  first_target <- if (startsWith(variant, "1290")) "w11" else "w14"
  observed %>%
    summarise(
      variant = variant,
      trajectory_rows = n(),
      linked_rows = sum(!is.na(previous_label)),
      incorrect_wave_links = sum(!wave_link_correct),
      incorrect_label_links = sum(!label_link_correct),
      first_target = first_target,
      first_target_rows = sum(wave == first_target),
      first_target_linked_rows = sum(
        wave == first_target & !is.na(previous_label)
      )
    )
}

summary <- bind_rows(lapply(variants, audit_variant))
write_csv(summary, file.path(AUDIT_DIR, "lag_linkage_audit.csv"))
print(summary, n = Inf)

failed <- with(
  summary,
  incorrect_wave_links > 0L | incorrect_label_links > 0L |
    first_target_rows == 0L | first_target_rows != first_target_linked_rows
)
if (any(failed)) stop("Lag-linkage audit failed for one or more variants.")

message("Lag-linkage audit passed for all manuscript variants.")
