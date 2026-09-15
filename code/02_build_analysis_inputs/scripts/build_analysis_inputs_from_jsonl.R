# install.packages(c("dplyr", "purrr", "jsonlite", "stringr", "tidyr"))
library(dplyr)
library(purrr)
library(jsonlite)
library(stringr)
library(tidyr)

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "data"))) {
  stop("Run this script from the code project root.")
}

# ==========================================
# 1. Settings and paths
# ==========================================
# Directory layout relative to the code project root:
#   data/intermediate_hdata/wave_list_for_llm_join_<variant>.rds
#   data/llm_outputs/outcome/<variant>/  (JSONL files, including subdirectories)
# Variants: "1290", "1290_original_scale", "1500", "1500_original_scale".
# Output: data/analysis_inputs/analyse_<variant>.csv

hdata_dir   <- file.path(PROJECT_ROOT, "data", "intermediate_hdata")
outcome_dir <- file.path(PROJECT_ROOT, "data", "llm_outputs", "outcome")
analysis_input_dir <- file.path(PROJECT_ROOT, "data", "analysis_inputs")
dir.create(analysis_input_dir, showWarnings = FALSE, recursive = TRUE)

# Process only nosft_*__prompt_w* JSONL files produced by the prompt workflow.
jsonl_pattern <- "^nosft_.*\\.jsonl$"

# Columns to extract from JSONL, including its respondent key.
target_columns    <- c("id", "label", "predict")
survey_join_key   <- "lfdn"   # Respondent key in the survey / wave-list RDS.
jsonl_subject_col <- "id"     # Respondent key in JSONL.

# ==========================================
# 2. Helper functions
# ==========================================

# nosft_{LLM}__prompt_w{NN}.jsonl                  → variant = baseline
# nosft_{LLM}__prompt_w{NN}_baseline_notime.jsonl  → variant = baseline_notime
# nosft_{LLM}__prompt_w{NN}_tanchored.jsonl        → variant = tanchored
# nosft_{LLM}__prompt_w{NN}_trajectory.jsonl       → variant = trajectory
parse_nosft_jsonl_metadata <- function(file_name) {
  if (!grepl("^nosft_.+__prompt_w\\d+", file_name)) {
    return(list(
      llm_model = NA_character_,
      wave_info = NA_character_,
      prompt_variant = NA_character_
    ))
  }
  llm_model <- sub("^nosft_(.+?)__prompt_.*$", "\\1", file_name)
  m <- str_match(file_name, "__prompt_(w\\d+)([^\\.]*)\\.jsonl\\s*$")
  if (any(is.na(m[1L, ]))) {
    return(list(llm_model = llm_model, wave_info = NA_character_, prompt_variant = NA_character_))
  }
  wave_info <- m[1L, 2L]
  rest <- m[1L, 3L]
  prompt_variant <- if (is.na(rest) || !nzchar(rest)) "baseline" else sub("^_", "", rest)
  list(llm_model = llm_model, wave_info = wave_info, prompt_variant = prompt_variant)
}

labelled_classes <- c(
  "haven_labelled", "haven_labelled_spss", "labelled", "vctrs_vctr"
)

# Remove the class and attributes from haven_labelled columns to expose their
# underlying values and avoid vctrs attribute conflicts in bind_rows / left_join.
strip_to_base <- function(x) {
  if (inherits(x, labelled_classes)) {
    attributes(x) <- NULL
  }
  x
}

# Map haven_labelled values to the text stored in their labels attribute.
# Without labels, return the underlying values as text; leave other columns as is.
labelled_to_label_chr <- function(x) {
  if (!inherits(x, labelled_classes)) return(x)
  labs <- attr(x, "labels")
  raw <- x; attributes(raw) <- NULL
  if (is.null(labs) || length(labs) == 0L) return(as.character(raw))
  lab_codes <- labs; attributes(lab_codes) <- NULL
  lab_text  <- names(labs)
  out <- as.character(raw)
  ix <- match(raw, lab_codes)
  has <- !is.na(ix)
  out[has] <- lab_text[ix[has]]
  out
}

# Normalize a single wave's data frame:
#   - kp_* / pi_* columns: use their value-label text.
#   - Other labelled columns: expose their underlying numeric/character values.
normalize_wave_df <- function(df) {
  nms <- names(df)
  for (i in seq_along(df)) {
    nm <- nms[[i]]
    x  <- df[[i]]
    if (grepl("^(kp|pi)", nm, ignore.case = TRUE)) {
      df[[i]] <- labelled_to_label_chr(x)
    } else {
      df[[i]] <- strip_to_base(x)
    }
  }
  df
}

# Remove the wave number from kp{wave}_ / kpa{wave}_ to retain kp_{suffix}.
harmonize_wave_df_kp_columns <- function(df, wave_list_name) {
  if (!grepl("^w\\d+$", wave_list_name, ignore.case = TRUE)) return(df)
  wn <- suppressWarnings(as.integer(sub("^w", "", wave_list_name, ignore.case = TRUE)))
  if (is.na(wn)) return(df)
  nm <- names(df)
  kp_rx <- sprintf("^kpa?%d_(.+)$", wn)
  is_my_kp <- grepl(kp_rx, nm, perl = TRUE)
  is_any_kp <- grepl("^kpa?[0-9]+_", nm, perl = TRUE)
  drop_ix <- is_any_kp & !is_my_kp
  if (any(drop_ix)) df <- df[, !drop_ix, drop = FALSE]
  nm2 <- names(df)
  ix <- grepl(sprintf("^kpa?%d_(.+)$", wn), nm2, perl = TRUE)
  if (any(ix)) names(df)[ix] <- sub(sprintf("^kpa?%d_(.+)$", wn), "kp_\\1", nm2[ix], perl = TRUE)
  df
}

# Locate the JSONL directory for a variant. Files may be stored directly in
# outcome/<variant>/ or in model subdirectories; discovery is recursive.
resolve_jsonl_dir <- function(variant) {
  base <- file.path(outcome_dir, variant)
  if (!dir.exists(base)) return(NULL)

  files <- list.files(
    path = base,
    pattern = jsonl_pattern,
    full.names = TRUE,
    recursive = TRUE
  )
  if (length(files) == 0L) return(NULL)
  base
}

# Discover variants from wave_list_for_llm_join_<variant>.rds in hdata_dir.
discover_variants <- function() {
  files <- list.files(hdata_dir, pattern = "^wave_list_for_llm_join_.+\\.rds$", full.names = FALSE)
  sub("^wave_list_for_llm_join_(.+)\\.rds$", "\\1", files)
}

# ==========================================
# 3. Extract and clean LLM JSONL data
# ==========================================
extract_llm_data <- function(directory, pattern, extract_cols) {
  file_paths <- list.files(
    path = directory,
    pattern = pattern,
    full.names = TRUE,
    recursive = TRUE
  )
  file_paths <- file_paths[grepl("^nosft_.+__prompt_w\\d+", basename(file_paths), ignore.case = TRUE)]
  file_paths <- sort(file_paths)

  if (length(file_paths) == 0L) {
    stop("No JSONL files matching nosft_*__prompt_w* found in: ", directory)
  }
  duplicated_names <- unique(basename(file_paths)[duplicated(basename(file_paths))])
  if (length(duplicated_names) > 0L) {
    stop(
      "Duplicate JSONL basenames under ", directory, ": ",
      paste(duplicated_names, collapse = ", "),
      ". Keep one file per model/wave/prompt combination."
    )
  }

  combined_llm_df <- map_dfr(file_paths, function(file_path) {
    file_name <- basename(file_path)
    meta <- parse_nosft_jsonl_metadata(file_name)
    con <- file(file_path, open = "r", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
    df <- jsonlite::stream_in(con, verbose = FALSE)
    missing_columns <- setdiff(extract_cols, names(df))
    if (length(missing_columns)) {
      stop(file_name, " is missing required JSONL fields: ",
           paste(missing_columns, collapse = ", "))
    }
    if (!nrow(df)) stop("Empty generation file: ", file_name)
    numeric_id <- suppressWarnings(as.numeric(as.character(df[[jsonl_subject_col]])))
    if (any(!is.finite(numeric_id)) || anyDuplicated(numeric_id)) {
      stop("Missing, nonnumeric, or duplicate respondent IDs in ", file_name)
    }
    if (any(is.na(df$label) | !nzchar(trimws(as.character(df$label))))) {
      stop("Missing reference labels in ", file_name)
    }
    cols_to_keep <- extract_cols

    df %>%
      select(all_of(cols_to_keep)) %>%
      mutate(
        source_file = file_name,
        llm_model = meta$llm_model,
        wave_info = meta$wave_info,
        prompt_variant = meta$prompt_variant
      )
  })

  combined_llm_df
}

# ==========================================
# 4. Process one variant
# ==========================================
process_variant <- function(variant) {
  message("==== Processing variant: ", variant, " ====")

  rds_basename  <- sprintf("wave_list_for_llm_join_%s.rds", variant)
  rds_file_path <- file.path(hdata_dir, rds_basename)
  if (!file.exists(rds_file_path)) {
    stop("RDS file not found: ", rds_file_path)
  }

  jsonl_dir <- resolve_jsonl_dir(variant)
  if (is.null(jsonl_dir)) {
    stop("No JSONL directory found for ", variant, " (searched outcome/", variant,
         "/ and its subdirectories).")
  }
  message("  RDS  : ", rds_file_path)
  message("  JSONL: ", jsonl_dir)

  llm_predictions_df <- extract_llm_data(
    directory = jsonl_dir,
    pattern = jsonl_pattern,
    extract_cols = target_columns
  )

  if (!jsonl_subject_col %in% names(llm_predictions_df)) {
    stop("JSONL is missing column ", jsonl_subject_col, " (variant=", variant, ").")
  }

  # JSONL id and wave-list lfdn identify the same respondent.
  llm_predictions_df[[survey_join_key]] <- suppressWarnings(
    as.numeric(llm_predictions_df[[jsonl_subject_col]])
  )
  llm_predictions_df[["rds_basename"]] <- rds_basename
  llm_predictions_df[["variant"]]      <- variant

  bad_wave <- is.na(llm_predictions_df[["wave_info"]]) |
              llm_predictions_df[["wave_info"]] == ""
  if (any(bad_wave)) {
    warning(sum(bad_wave), " LLM rows have no wave_info parsed from filenames and were excluded (variant=",
            variant, ").")
    llm_predictions_df <- llm_predictions_df[!bad_wave, , drop = FALSE]
  }

  # Read the RDS and harmonize column names within each wave.
  original_wave_list <- readRDS(rds_file_path)
  wl_names <- names(original_wave_list)
  original_wave_list <- stats::setNames(
    Map(
      function(nm, d) normalize_wave_df(harmonize_wave_df_kp_columns(d, nm)),
      wl_names, original_wave_list
    ),
    wl_names
  )

  w0 <- original_wave_list[[1L]]
  if (!survey_join_key %in% names(w0)) {
    stop("RDS is missing key column ", survey_join_key, " (variant=", variant, ").")
  }

  # Flatten the wave list into a long data frame.
  # Attach the explicitly designated preceding survey wave before joining any
  # generations. The previous human state must come from the panel rather than
  # from lagging available output rows.
  original_combined_df <- bind_rows(original_wave_list, .id = "wave_id_from_list")
  # Historical files for unselected waves are reported but never enter this task.
  outside_waves <- !llm_predictions_df$wave_info %in% names(original_wave_list)
  if (any(outside_waves)) {
    message("Excluding ", sum(outside_waves), " archived rows from unselected waves.")
    llm_predictions_df <- llm_predictions_df[!outside_waves, , drop = FALSE]
  }
  reference_check <- llm_predictions_df %>%
    left_join(
      original_combined_df %>% transmute(
        lfdn, wave_info = wave_id_from_list, survey_reference = as.character(outcome)
      ),
      by = c("lfdn", "wave_info")
    )
  if (any(is.na(reference_check$survey_reference))) {
    stop("Generation IDs do not match the selected survey records for ", variant)
  }
  if (any(str_squish(as.character(reference_check$label)) !=
          str_squish(reference_check$survey_reference))) {
    stop("Archived reference labels disagree with the survey outcomes for ", variant)
  }
  ordered_waves <- names(original_wave_list)
  ordered_waves <- ordered_waves[order(suppressWarnings(
    as.integer(sub("^.*?([0-9]+).*$", "\\1", ordered_waves))
  ))]
  previous_wave_map <- tibble(
    wave_id_from_list = ordered_waves,
    previous_wave_id = c(NA_character_, head(ordered_waves, -1L))
  )

  duplicate_human_keys <- original_combined_df %>%
    count(.data[[survey_join_key]], wave_id_from_list, name = "n") %>%
    filter(n > 1L)
  if (nrow(duplicate_human_keys) > 0L) {
    stop("Duplicate respondent-wave keys in survey wave list for variant ", variant)
  }
  previous_human_lookup <- original_combined_df %>%
    transmute(
      !!survey_join_key := .data[[survey_join_key]],
      previous_wave_id = wave_id_from_list,
      vorwelle_label = as.character(outcome)
    )
  original_combined_df <- original_combined_df %>%
    left_join(previous_wave_map, by = "wave_id_from_list") %>%
    left_join(
      previous_human_lookup,
      by = c(survey_join_key, "previous_wave_id")
    )

  # Join by respondent ID (lfdn) and wave.
  final_joined_df <- left_join(
    original_combined_df,
    llm_predictions_df,
    by = c("lfdn", "wave_id_from_list" = "wave_info")
  )

  # Link predictions from the designated preceding wave.
  # Attach the prediction from the same designated preceding wave. This keeps
  # self-trajectory diagnostics explicit and prevents available-row lagging from
  # silently jumping over an absent generation.
  duplicate_prediction_keys <- llm_predictions_df %>%
    count(
      .data[[survey_join_key]], wave_info, llm_model, prompt_variant,
      name = "n"
    ) %>%
    filter(n > 1L)
  if (nrow(duplicate_prediction_keys) > 0L) {
    stop("Duplicate model respondent-wave keys for variant ", variant)
  }
  previous_prediction_lookup <- llm_predictions_df %>%
    transmute(
      !!survey_join_key := .data[[survey_join_key]],
      previous_wave_id = wave_info,
      llm_model,
      prompt_variant,
      vorwelle_predict = predict
    )
  final_joined_df <- final_joined_df %>%
    left_join(
      previous_prediction_lookup,
      by = c(
        survey_join_key,
        "previous_wave_id",
        "llm_model",
        "prompt_variant"
      )
    )

  out_path <- file.path(analysis_input_dir, sprintf("analyse_%s.csv", variant))
  write.csv(final_joined_df, out_path, row.names = FALSE, fileEncoding = "UTF-8")
  message("  -> wrote ", out_path, " (", nrow(final_joined_df), " rows)")

  invisible(final_joined_df)
}

# ==========================================
# 5. Discover and process all variants
# ==========================================
variants <- discover_variants()
if (length(variants) == 0L) {
  stop("Directory ", hdata_dir, " contains no wave_list_for_llm_join_*.rds files.")
}
message("Discovered variants: ", paste(variants, collapse = ", "))

for (v in variants) {
  process_variant(v)
  invisible(gc())
}
