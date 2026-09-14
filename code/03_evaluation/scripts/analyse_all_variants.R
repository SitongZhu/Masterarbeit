#!/usr/bin/env Rscript
# analyse_all_variants.R
# Run the analysis pipeline for all data/analysis_inputs/analyse_<variant>.csv.
# Outputs are written under outputs/evaluation/analysis_<variant>/.
# Includes accuracy, pooled distributions, temporal diagnostics, subgroup
# analyses and multinomial baselines. Final structural fidelity has its own script.
suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(ggplot2)
  library(broom)
  library(scales)
  library(viridis)
  library(patchwork)
})

# Factor reference levels and categorical ties must not depend on the host locale.
if (!identical(Sys.setlocale("LC_COLLATE", "C"), "C")) {
  stop("The C collation is required for reproducible factor reference levels.")
}
options(contrasts = c("contr.treatment", "contr.poly"))

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "data"))) {
  stop("Run this script from the code project root.")
}
ANALYSIS_INPUT_DIR <- Sys.getenv(
  "ANALYSIS_INPUT_DIR",
  unset = file.path(PROJECT_ROOT, "data", "analysis_inputs")
)
EVALUATION_OUTPUT_ROOT <- Sys.getenv(
  "EVALUATION_OUTPUT_ROOT",
  unset = file.path(PROJECT_ROOT, "outputs", "evaluation")
)
ANALYSIS_INPUT_DIR <- normalizePath(ANALYSIS_INPUT_DIR, winslash = "/",
                                    mustWork = TRUE)
EVALUATION_OUTPUT_ROOT <- normalizePath(EVALUATION_OUTPUT_ROOT, winslash = "/",
                                        mustWork = FALSE)
dir.create(EVALUATION_OUTPUT_ROOT, showWarnings = FALSE, recursive = TRUE)
MIN_N_STRATUM        <- 30L
MIN_N_COVARIATE      <- 30L
MIN_FRAC_COVARIATE   <- 0.02
MIN_LEVELS_COVARIATE <- 2L
MAX_LEVELS_COVARIATE <- 20L

SUBGROUP_SOURCE_VARS <- c("pi_2280", "pi_2591", "pi_2320")
SUBGROUP_INDEPENDENT_VARS <- c("sex", "income_band", "education_band")
SUBGROUP_MIN_N <- 30L
SUBGROUP_OUTCOME_NAME <- "correct_prediction"

CONFUSION_MIN_N <- 1L
CHANGE_CAPTURE_MIN_RARE_N <- 30L
CHANGE_CAPTURE_MIN_CAPTURED_N <- 10L
STAT_BASELINE_MIN_N <- 50L
STAT_BASELINE_MISSING_LEVEL <- "__MISSING__"
STAT_BASELINE_OTHER_LEVEL <- "__OTHER__"
STAT_BASELINE_MAXIT <- 2000L
STAT_BASELINE_STABILITY_LIMITS <- c(200L, 500L, 1000L, 2000L)

HEATMAP_FILL_COLOURS <- c("#F7FCF5", "#D9F0D3", "#A1D99B",
                          "#41AB5D", "#238B45")

make_subgroup_outcome <- function(df) {
  !is.na(df$label_cat) & !is.na(df$predict_cat) & df$label_cat == df$predict_cat
}

make_subgroup_variables <- function(df) {
  income_num <- suppressWarnings(as.numeric(str_extract(df$pi_2591, "[0-9]+")))
  df %>%
    mutate(
      sex = pi_2280,
      income_band = case_when(
        is.na(pi_2591) | pi_2591 == "NA" ~ NA_character_,
        str_detect(str_to_lower(pi_2591), "unter 500") ~ "low_income",
        !is.na(income_num) & income_num < 1500 ~ "low_income",
        !is.na(income_num) & income_num < 3000 ~ "middle_income",
        !is.na(income_num) ~ "high_income",
        TRUE ~ NA_character_
      ),
      education_band = case_when(
        pi_2320 %in% c("Hauptschulabschluss", "Realschulabschluss") ~
          "before_university_track",
        pi_2320 %in% c("Fachhochschulreife", "Abitur") ~
          "university_track_or_higher",
        TRUE ~ NA_character_
      )
    )
}

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
clean_text <- function(x) {
  x <- as.character(x)
  x <- str_squish(x)
  is_empty <- !is.na(x) & x == ""


  x[is_empty] <- NA_character_
  x
}

parse_wave_order <- function(wave) {
  as.integer(str_extract(wave, "[0-9]+"))
}

# Data-driven category matching.
# Data-driven category matching.

# Normalize text for category matching.
normalize_str <- function(s) {
  s <- tolower(enc2utf8(as.character(s)))
  # Repair common UTF-8-as-Latin-1 mojibake and normalize German characters.
  s <- gsub("\u00e3\u00bc", "ue", s, fixed = TRUE)
  s <- gsub("\u00e3\u00a4", "ae", s, fixed = TRUE)
  s <- gsub("\u00e3\u00b6", "oe", s, fixed = TRUE)
  s <- gsub("\u00e3\u0178", "ss", s, fixed = TRUE)
  s <- gsub("\u00e4", "ae", s, fixed = TRUE)
  s <- gsub("\u00f6", "oe", s, fixed = TRUE)
  s <- gsub("\u00fc", "ue", s, fixed = TRUE)
  s <- gsub("\u00df", "ss", s, fixed = TRUE)
  s <- sub("^\\s*[0-9]+\\s*[\\.\\):]\\s*", "", s, perl = TRUE)
  s
}

# Split normalized text into content tokens.
content_tokens <- function(s, min_len = 4L) {
  s <- normalize_str(s)
  toks <- unlist(strsplit(s, "[^a-z0-9]+", perl = TRUE))
  toks <- toks[!is.na(toks) & nchar(toks) >= min_len]
  unique(toks)
}



build_label_dict <- function(label_col) {
  cats <- clean_text(label_col)

  cats <- cats[!is.na(cats)]
  cats <- cats[nzchar(cats, keepNA = FALSE)]
  cats <- unique(cats)
  if (length(cats) == 0L) {
    return(list(cats = character(0), tokens = list(),
                ordered = character(0), is_numeric = FALSE))
  }
  is_num <- all(grepl("^-?\\d+(\\.\\d+)?$", cats))
  if (is_num) {
    ordered <- cats[order(as.numeric(cats))]
    tokens  <- setNames(as.list(ordered), ordered)
    return(list(cats = ordered, tokens = tokens,
                ordered = ordered, is_numeric = TRUE,
                scores = NULL))
  }

  norm_cats <- normalize_str(cats)
  is_1290_cluster <- all(c(
    any(str_detect(norm_cats, "bekaempfung.*klimawandels")),
    any(str_detect(norm_cats, "mittelposition")),
    any(str_detect(norm_cats, "wirtschaftswachstum"))
  ))
  if (is_1290_cluster && length(cats) == 3L) {
    scores <- case_when(
      str_detect(norm_cats, "bekaempfung.*klimawandels") ~ -1,
      str_detect(norm_cats, "mittelposition") ~ 0,
      str_detect(norm_cats, "wirtschaftswachstum") ~ 1,
      TRUE ~ NA_real_
    )
    if (all(!is.na(scores))) {
      ordered <- cats[order(scores)]
      tokens_per <- lapply(cats, content_tokens)
      names(tokens_per) <- cats
      freq <- table(unlist(tokens_per))
      distinguishing <- lapply(tokens_per, function(toks) {
        if (length(toks) == 0L) return(character(0))
        uniq <- toks[as.integer(freq[toks]) == 1L]
        if (length(uniq) == 0L) toks else uniq
      })
      return(list(cats = cats, tokens = distinguishing,
                  ordered = ordered, is_numeric = FALSE,
                  scores = setNames(scores, cats)))
    }
  }

  is_1500_cluster <- all(c(
    any(norm_cats == "links"),
    any(norm_cats == "neutral"),
    any(norm_cats == "rechts")
  ))
  if (is_1500_cluster && length(cats) == 3L) {
    scores <- case_when(
      norm_cats == "links" ~ -1,
      norm_cats == "neutral" ~ 0,
      norm_cats == "rechts" ~ 1,
      TRUE ~ NA_real_
    )
    if (all(!is.na(scores))) {
      ordered <- cats[order(scores)]
      tokens_per <- lapply(cats, content_tokens)
      names(tokens_per) <- cats
      freq <- table(unlist(tokens_per))
      distinguishing <- lapply(tokens_per, function(toks) {
        if (length(toks) == 0L) return(character(0))
        uniq <- toks[as.integer(freq[toks]) == 1L]
        if (length(uniq) == 0L) toks else uniq
      })
      return(list(cats = cats, tokens = distinguishing,
                  ordered = ordered, is_numeric = FALSE,
                  scores = setNames(scores, cats)))
    }
  }

  tokens_per <- lapply(cats, content_tokens)
  names(tokens_per) <- cats
  freq <- table(unlist(tokens_per))
  distinguishing <- lapply(tokens_per, function(toks) {
    if (length(toks) == 0L) return(character(0))
    uniq <- toks[as.integer(freq[toks]) == 1L]
    if (length(uniq) == 0L) toks else uniq
  })
  list(cats = cats, tokens = distinguishing,
       ordered = sort(cats), is_numeric = FALSE,
       scores = NULL)
}


match_to_category <- function(text, dict) {
  text_c <- clean_text(text)
  n <- length(text_c)
  out <- rep(NA_character_, n)
  if (length(dict$cats) == 0L || n == 0L) return(out)

  K <- length(dict$cats)
  positions <- matrix(.Machine$integer.max, nrow = n, ncol = K,
                      dimnames = list(NULL, dict$cats))
  text_safe <- text_c
  text_safe[is.na(text_safe)] <- ""
  if (dict$is_numeric) {
    for (j in seq_len(K)) {
      pat <- sprintf("(?<![0-9])%s(?![0-9])",
                     gsub(".", "\\.", dict$cats[j], fixed = TRUE))
      p <- as.integer(regexpr(pat, text_safe, perl = TRUE))
      p[is.na(p) | p < 0L] <- .Machine$integer.max
      positions[, j] <- p
    }
  } else {
    text_n <- normalize_str(text_safe)
    text_n <- gsub("[^a-z0-9]+", " ", text_n, perl = TRUE)
    text_n[is.na(text_n)] <- ""
    for (j in seq_len(K)) {
      toks <- dict$tokens[[dict$cats[j]]]
      if (length(toks) == 0L) next
      pat <- sprintf("\\b(?:%s)\\b", paste(toks, collapse = "|"))
      p <- as.integer(regexpr(pat, text_n, perl = TRUE))
      p[is.na(p) | p < 0L] <- .Machine$integer.max
      positions[, j] <- p
    }
  }
  best <- max.col(-positions, ties.method = "first")
  has_hit <- positions[cbind(seq_len(n), best)] < .Machine$integer.max
  out[has_hit] <- dict$cats[best[has_hit]]
  out
}


# Encode matched categories as numeric values for regressions and deltas.
# Numeric Likert categories keep their numeric scale; text categories use dictionary order.
encode_num <- function(cat_chr, dict) {
  if (length(dict$cats) == 0L) return(rep(NA_real_, length(cat_chr)))
  if (dict$is_numeric) suppressWarnings(as.numeric(cat_chr))
  else if (!is.null(dict$scores)) unname(dict$scores[cat_chr])
  else                  as.numeric(match(cat_chr, dict$ordered))
}

ordered_category_levels <- function(dict, observed = character(0)) {
  levels <- if (!is.null(dict) && length(dict$ordered) > 0L) {
    dict$ordered
  } else {
    sort(unique(na.omit(observed)))
  }
  if (length(levels) == 0L) return(levels)

  if (!is.null(dict) && !is.null(dict$scores)) {
    scores <- unname(dict$scores[levels])
    if (all(!is.na(scores))) return(levels[order(scores)])
  }

  numeric_levels <- suppressWarnings(as.numeric(levels))
  if (all(!is.na(numeric_levels))) {
    return(levels[order(numeric_levels)])
  }

  norm <- normalize_str(levels)
  is_1290_cluster <- all(c(
    any(str_detect(norm, "bekaempfung.*klimawandels")),
    any(norm == "mittelposition"),
    any(str_detect(norm, "wirtschaftswachstum"))
  ))
  if (is_1290_cluster) {
    scores <- case_when(
      str_detect(norm, "bekaempfung.*klimawandels") ~ -1,
      norm == "mittelposition" ~ 0,
      str_detect(norm, "wirtschaftswachstum") ~ 1,
      TRUE ~ NA_real_
    )
    if (all(!is.na(scores))) return(levels[order(scores)])
  }

  known_orders <- list(
    c("links", "neutral", "rechts"),
    c("left", "neutral", "right"),
    c("low", "middle", "high")
  )
  for (ord in known_orders) {
    idx <- match(norm, ord)
    if (all(!is.na(idx))) return(levels[order(idx)])
  }

  levels
}

category_fill_values <- function(category_levels) {
  if (length(category_levels) == 0L) return(character(0))

  norm <- normalize_str(category_levels)
  values <- setNames(rep(NA_character_, length(category_levels)),
                     category_levels)

  is_1290_cluster <- all(c(
    any(str_detect(norm, "bekaempfung.*klimawandels")),
    any(norm == "mittelposition"),
    any(str_detect(norm, "wirtschaftswachstum"))
  ))
  if (is_1290_cluster) {
    values[str_detect(norm, "bekaempfung.*klimawandels")] <- "#5F8F4E"
    values[norm == "mittelposition"] <- "#B9B9B9"
    values[str_detect(norm, "wirtschaftswachstum")] <- "#C78E3D"
    if (all(!is.na(values))) return(values)
  }

  if (length(category_levels) == 3L &&
      all(c("links", "neutral", "rechts") %in% norm)) {
    values[norm == "links"] <- "#C75A54"
    values[norm == "neutral"] <- "#B9B9B9"
    values[norm == "rechts"] <- "#315C8A"
    return(values)
  }

  if (length(category_levels) == 3L &&
      all(c("left", "neutral", "right") %in% norm)) {
    values[norm == "left"] <- "#C75A54"
    values[norm == "neutral"] <- "#B9B9B9"
    values[norm == "right"] <- "#315C8A"
    return(values)
  }

  numeric_levels <- suppressWarnings(as.numeric(category_levels))
  if (all(!is.na(numeric_levels))) {
    ramp <- grDevices::colorRampPalette(c("#C75A54", "#D8D3C7", "#315C8A"))
    return(setNames(ramp(length(category_levels)), category_levels))
  }

  qualitative <- c(
    "#315C8A", "#C75A54", "#5F8F4E", "#8A6BBE",
    "#D39C45", "#6AA5A9", "#8A8A8A", "#B76E79"
  )
  if (length(category_levels) <= length(qualitative)) {
    return(setNames(qualitative[seq_along(category_levels)], category_levels))
  }

  setNames(grDevices::colorRampPalette(qualitative)(length(category_levels)),
           category_levels)
}

aggregate_category_fill_values <- function(category_levels) {
  if (length(category_levels) == 0L) return(character(0))

  if (length(category_levels) == 1L) {
    return(setNames("#B9B9B9", category_levels))
  }

  if (length(category_levels) == 3L) {
    return(setNames(c("#C75A54", "#B9B9B9", "#315C8A"),
                    category_levels))
  }

  ramp <- grDevices::colorRampPalette(c("#C75A54", "#D8D3C7", "#315C8A"))
  setNames(ramp(length(category_levels)), category_levels)
}

prompt_variant_levels <- function(observed = character(0)) {
  observed <- unique(na.omit(as.character(observed)))
  preferred <- c("baseline", "baseline_notime", "tanchored", "trajectory")
  c(preferred[preferred %in% observed],
    sort(setdiff(observed, preferred)))
}

prompt_variant_colour_values <- function(prompt_levels) {
  prompt_levels <- as.character(prompt_levels)
  values <- c(
    baseline = "#F8766D",
    baseline_notime = "#7CAE00",
    tanchored = "#00BFC4",
    trajectory = "#C77CFF"
  )

  missing <- setdiff(prompt_levels, names(values))
  if (length(missing) > 0L) {
    fallback <- c(
      "#A6761D", "#666666", "#E7298A", "#7570B3",
      "#1B9E77", "#D95F02", "#66A61E", "#E6AB02"
    )
    values <- c(values,
                setNames(rep(fallback, length.out = length(missing)),
                         missing))
  }
  values[prompt_levels]
}

infer_covariate_columns <- function(df, outcome_variable, exclude = character(0)) {
  candidate <- grep("^(kp_|pi_)", names(df), value = TRUE)
  candidate <- setdiff(
    candidate,
    c(paste0("kp_", outcome_variable),
      paste0("pi_", outcome_variable),
      exclude)
  )
  candidate[vapply(candidate, function(col) {
    v <- df[[col]]
    n_valid <- sum(!is.na(v))
    if (n_valid < MIN_N_COVARIATE) return(FALSE)
    if (n_valid / nrow(df) < MIN_FRAC_COVARIATE) return(FALSE)
    n_unique <- length(na.omit(unique(v)))
    n_unique >= MIN_LEVELS_COVARIATE && n_unique <= MAX_LEVELS_COVARIATE
  }, logical(1))]
}

first_non_missing <- function(x) {
  idx <- which(!is.na(x))
  if (length(idx) == 0L) x[NA_integer_][1] else x[idx[1]]
}

modal_value <- function(x) {
  x <- as.character(x)
  x <- x[!is.na(x)]
  if (length(x) == 0L) return(NA_character_)
  counts <- sort(table(x), decreasing = TRUE)
  names(counts)[1]
}

align_newdata_levels <- function(newdata, fit, train_data) {
  for (col in names(fit$xlevels)) {
    fit_levels <- fit$xlevels[[col]]
    # A factor can carry levels defined from later waves. Presence in xlevels
    # does not establish that a level occurred in this training sample.
    observed <- unique(as.character(train_data[[col]]))
    allowed <- fit_levels[fit_levels %in% observed]
    if (!length(allowed)) stop("No observed training levels for predictor ", col)
    values <- as.character(newdata[[col]])
    fallback <- modal_value(as.character(train_data[[col]]))
    if (is.na(fallback) || !(fallback %in% allowed)) fallback <- allowed[1]
    values[is.na(values) | !(values %in% allowed)] <- fallback
    newdata[[col]] <- factor(values, levels = fit_levels)
  }
  newdata
}

build_previous_wave_modal_lookup <- function(df) {
  human_by_wave <- df %>%
    filter(!is.na(lfdn), !is.na(wave), !is.na(wave_order),
           !is.na(label_cat)) %>%
    group_by(lfdn, wave, wave_order) %>%
    summarise(label_cat = first_non_missing(label_cat), .groups = "drop")

  human_by_wave %>%
    group_by(wave, wave_order) %>%
    summarise(
      wave_modal_category = modal_value(label_cat),
      n_wave_labels = n(),
      .groups = "drop"
    ) %>%
    arrange(wave_order, wave) %>%
    mutate(
      previous_wave = lag(wave),
      previous_wave_order = lag(wave_order),
      previous_wave_modal_category = lag(wave_modal_category),
      n_previous_wave_labels = lag(n_wave_labels)
    ) %>%
    select(wave, wave_order, previous_wave, previous_wave_order,
           previous_wave_modal_category, n_previous_wave_labels)
}

run_module_safe <- function(label, expr) {
  tryCatch(
    force(expr),
    error = function(e) {
      stop(label, " failed: ", conditionMessage(e), call. = FALSE)
    }
  )
}

slug <- function(x) gsub("[^A-Za-z0-9]+", "_", x)

organize_analysis_pngs <- function(project_root = EVALUATION_OUTPUT_ROOT) {
  out_root <- file.path(project_root, "organized_analysis_pngs")
  dir.create(out_root, showWarnings = FALSE, recursive = TRUE)

  analysis_dirs <- list.dirs(project_root, full.names = TRUE, recursive = FALSE)
  analysis_dirs <- analysis_dirs[grepl("^analysis_.+", basename(analysis_dirs))]
  copied <- 0L

  for (analysis_dir in analysis_dirs) {
    variant <- sub("^analysis_", "", basename(analysis_dir))
    png_files <- list.files(
      analysis_dir,
      pattern = "\\.png$",
      recursive = TRUE,
      full.names = TRUE
    )
    if (length(png_files) == 0L) next

    analysis_norm <- normalizePath(analysis_dir, winslash = "/",
                                   mustWork = TRUE)
    for (png_file in png_files) {
      png_norm <- normalizePath(png_file, winslash = "/", mustWork = TRUE)
      rel <- substring(png_norm, nchar(analysis_norm) + 2L)
      parts <- strsplit(rel, "/", fixed = TRUE)[[1]]
      if (length(parts) < 2L) next

      target_subdir <- do.call(file.path,
                               as.list(parts[-length(parts)]))
      target_dir <- file.path(out_root, target_subdir)
      dir.create(target_dir, showWarnings = FALSE, recursive = TRUE)

      source_name <- parts[length(parts)]
      ext <- tools::file_ext(source_name)
      stem <- tools::file_path_sans_ext(source_name)
      target_name <- if (nzchar(ext)) {
        paste0(stem, "_", variant, ".", ext)
      } else {
        paste0(stem, "_", variant)
      }
      copied <- copied + as.integer(file.copy(
        png_norm,
        file.path(target_dir, target_name),
        overwrite = TRUE
      ))
    }
  }

  message("Organized ", copied, " PNG files into: ", out_root)
  invisible(copied)
}

write_statistical_baseline_display_table <- function(
    project_root = EVALUATION_OUTPUT_ROOT) {
  variants <- tibble::tribble(
    ~variant, ~task,
    "1290", "Climate-growth grouped",
    "1290_original_scale", "Climate-growth original",
    "1500", "Left-right grouped",
    "1500_original_scale", "Left-right original"
  )

  pieces <- lapply(seq_len(nrow(variants)), function(i) {
    path <- file.path(
      project_root,
      paste0("analysis_", variants$variant[[i]]),
      "statistical_baselines",
      "statistical_baseline_comparison_overall.csv"
    )
    if (!file.exists(path)) return(tibble())
    read_csv(path, show_col_types = FALSE) %>%
      mutate(
        Task = variants$task[[i]],
        modal_category = as.character(modal_category),
        .before = 1
      )
  })
  compact <- bind_rows(pieces)
  if (nrow(compact) == 0L) {
    warning("No trajectory statistical-baseline comparison files found.")
    return(invisible(NULL))
  }

  compact <- compact %>%
    mutate(
      Model = case_when(
        str_detect(model, "Mistral") ~ "Mistral-7B",
        str_detect(model, "Llama-3_3-70B") ~ "Llama-3.3-70B",
        str_detect(model, "72B") ~ "Qwen2.5-72B",
        str_detect(model, "32B") ~ "Qwen2.5-32B",
        str_detect(model, "7B") ~ "Qwen2.5-7B",
        TRUE ~ model
      )
    ) %>%
    arrange(factor(Task, levels = variants$task), Model)

  tables_dir <- file.path(project_root, "tables")
  dir.create(tables_dir, showWarnings = FALSE, recursive = TRUE)
  write_csv(
    compact,
    file.path(tables_dir, "statistical_baseline_comparison.csv")
  )

  format3 <- function(x) {
    ifelse(is.na(x), NA_character_, sprintf("%.3f", x))
  }
  display <- compact %>%
    transmute(
      Task,
      Model,
      N = n_total,
      Modal = modal_category,
      PreviousWaveModal = format3(accuracy_majority),
      CarryForward = format3(accuracy_cf),
      Statistical = format3(accuracy_statistical),
      Trajectory = format3(accuracy_trajectory),
      `Traj-PreviousWaveModal` = format3(trajectory_minus_majority),
      `Traj-CF` = format3(trajectory_minus_cf),
      `Traj-Stat` = format3(trajectory_minus_statistical),
      NStat = n_statistical_pred_available
    )
  out <- file.path(tables_dir,
                   "statistical_baseline_comparison_display.csv")
  write_csv(display, out)
  message("Wrote: ", out)
  invisible(display)
}


combine_plots_by_wave <- function(plot_records, out_dir, file_prefix,
                                  cell_w = 5, cell_h = 4) {
  if (length(plot_records) == 0L) return(invisible(NULL))
  waves <- unique(vapply(plot_records, `[[`, character(1), "wave"))
  for (wv in waves) {
    recs <- Filter(function(r) identical(r$wave, wv), plot_records)
    if (length(recs) == 0L) next
    models  <- sort(unique(vapply(recs, `[[`, character(1), "model")))
    prompts <- sort(unique(vapply(recs, `[[`, character(1), "prompt_variant")))
    nR <- length(models); nC <- length(prompts)

    cells <- vector("list", nR * nC)
    for (k in seq_along(recs)) {
      r <- match(recs[[k]]$model,          models)
      c <- match(recs[[k]]$prompt_variant, prompts)
      idx <- (r - 1L) * nC + c

      cells[[idx]] <- recs[[k]]$plot +
        labs(title = sprintf("%s  /  %s",
                             recs[[k]]$model,
                             recs[[k]]$prompt_variant)) +
        theme(plot.title = element_text(size = 9, face = "bold"))
    }
    for (i in seq_len(nR * nC)) {
      if (is.null(cells[[i]])) cells[[i]] <- plot_spacer()
    }
    combined <- wrap_plots(cells, nrow = nR, ncol = nC) +
      plot_annotation(
        title = sprintf("Wave = %s   (rows = model, columns = prompt variant)", wv),
        theme = theme(plot.title = element_text(size = 12, face = "bold"))
      )
    fname <- sprintf("%s_w%s.png", file_prefix, wv)
    ggsave(file.path(out_dir, fname), combined,
           width  = max(cell_w * nC, 8),
           height = max(cell_h * nR, 5),
           dpi = 150, limitsize = FALSE)
  }
}

combine_heatmap_plots_by_wave <- function(plot_records, out_dir, file_prefix,
                                          mode_label,
                                          cell_w = 5, cell_h = 5.5) {
  if (length(plot_records) == 0L) return(invisible(NULL))
  waves <- unique(vapply(plot_records, `[[`, character(1), "wave"))
  for (wv in waves) {
    recs <- Filter(function(r) identical(r$wave, wv), plot_records)
    if (length(recs) == 0L) next
    models <- sort(unique(vapply(recs, `[[`, character(1), "model")))

    cells <- vector("list", length(models))
    for (k in seq_along(recs)) {
      idx <- match(recs[[k]]$model, models)
      cells[[idx]] <- recs[[k]]$plot +
        labs(title = recs[[k]]$model, subtitle = NULL) +
        theme(plot.title = element_text(size = 10, face = "bold"))
    }
    for (i in seq_along(cells)) {
      if (is.null(cells[[i]])) cells[[i]] <- plot_spacer()
    }

    combined <- wrap_plots(cells, nrow = 1, guides = "collect") +
      plot_annotation(
        title = sprintf("Trajectory Delta H by Delta L Heatmaps: Wave = %s (%s)",
                        wv, mode_label),
        theme = theme(plot.title = element_text(size = 12, face = "bold"))
      ) &
      theme(legend.position = "right")
    fname <- sprintf("%s_w%s_combined.png", file_prefix, wv)
    ggsave(file.path(out_dir, fname), combined,
           width = max(cell_w * length(models), 8),
           height = cell_h,
           dpi = 150, limitsize = FALSE)
  }
}

combine_heatmap_plots_all <- function(plot_records, out_dir, file_prefix,
                                      mode_label,
                                      cell_w = 4.2, cell_h = 3.8) {
  if (length(plot_records) == 0L) return(invisible(NULL))
  wave_tbl <- tibble(
    wave = unique(vapply(plot_records, `[[`, character(1), "wave"))
  ) %>%
    mutate(wave_order = parse_wave_order(wave)) %>%
    arrange(wave_order, wave)
  waves <- wave_tbl$wave
  models <- sort(unique(vapply(plot_records, `[[`, character(1), "model")))
  nR <- length(waves)
  nC <- length(models)

  cells <- vector("list", nR * nC)
  for (k in seq_along(plot_records)) {
    r <- match(plot_records[[k]]$wave, waves)
    c <- match(plot_records[[k]]$model, models)
    idx <- (r - 1L) * nC + c
    cells[[idx]] <- plot_records[[k]]$plot +
      labs(title = sprintf("%s / %s", plot_records[[k]]$wave,
                           plot_records[[k]]$model),
           subtitle = NULL) +
      theme(plot.title = element_text(size = 8, face = "bold"))
  }
  for (i in seq_len(nR * nC)) {
    if (is.null(cells[[i]])) cells[[i]] <- plot_spacer()
  }

  combined <- wrap_plots(cells, nrow = nR, ncol = nC, guides = "collect") +
    plot_annotation(
      title = sprintf("Trajectory Delta H by Delta L Heatmaps (%s)", mode_label),
      subtitle = "Rows are waves; columns are models. All panels use the same Delta H, Delta L, and row-percent scales.",
      theme = theme(plot.title = element_text(size = 13, face = "bold"),
                    plot.subtitle = element_text(size = 10))
    ) &
    theme(legend.position = "right")

  fname <- sprintf("%s_all_combined.png", file_prefix)
  ggsave(file.path(out_dir, fname), combined,
         width = max(cell_w * nC, 10),
         height = max(cell_h * nR, 8),
         dpi = 150, limitsize = FALSE)
}

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
prepare_raw <- function(csv_path) {
  raw <- read_csv(csv_path, show_col_types = FALSE)
  raw <- raw %>%
    mutate(
      label          = clean_text(label),
      predict        = clean_text(predict),
      prompt_variant = clean_text(prompt_variant),
      wave           = clean_text(
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
  raw$lfdn <- clean_text(
    if ("lfdn" %in% names(raw)) raw$lfdn
    else if ("id" %in% names(raw)) raw$id
    else NA_character_
  )
  required <- c("label", "predict", "model", "prompt_variant", "wave", "lfdn")
  if (!all(required %in% names(raw))) {
    stop(basename(csv_path), " is missing required columns: ",
         paste(setdiff(required, names(raw)), collapse = ", "))
  }


  dict <- build_label_dict(raw$label)
  has_vw_label   <- "vorwelle_label"   %in% names(raw)
  has_vw_predict <- "vorwelle_predict" %in% names(raw)

  raw$label_cat   <- match_to_category(raw$label,   dict)
  raw$predict_cat <- match_to_category(raw$predict, dict)
  raw$label_num   <- encode_num(raw$label_cat,   dict)
  raw$predict_num <- encode_num(raw$predict_cat, dict)

  if (has_vw_label) {
    raw$vorwelle_label_cat <- match_to_category(raw$vorwelle_label, dict)
    raw$vorwelle_label_num <- encode_num(raw$vorwelle_label_cat, dict)
  } else {
    raw$vorwelle_label_cat <- NA_character_
    raw$vorwelle_label_num <- NA_real_
  }
  if (has_vw_predict) {
    raw$vorwelle_predict_cat <- match_to_category(raw$vorwelle_predict, dict)
    raw$vorwelle_predict_num <- encode_num(raw$vorwelle_predict_cat, dict)
  } else {
    raw$vorwelle_predict_cat <- NA_character_
    raw$vorwelle_predict_num <- NA_real_
  }

  attr(raw, "label_dict") <- dict
  raw
}

# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
run_module_accuracy <- function(raw, out_dir) {
  message("  [3] accuracy summary ...")
  acc <- raw %>%
    mutate(correct        = !is.na(label_cat) & !is.na(predict_cat) &
                            label_cat == predict_cat,
           parsed_predict = !is.na(predict_cat),
           parsed_label   = !is.na(label_cat)) %>%
    group_by(model, prompt_variant, wave) %>%
    summarise(
      n_total          = n(),
      n_parsed_label   = sum(parsed_label),
      n_parsed_predict = sum(parsed_predict),
      n_correct        = sum(correct, na.rm = TRUE),
      accuracy         = round(n_correct / n_total, 4),
      accuracy_parsed  = round(
        n_correct / pmax(sum(parsed_label & parsed_predict), 1L), 4),
      .groups = "drop"
    )
  write_csv(acc, file.path(out_dir, "accuracy_summary.csv"))
  if (nrow(acc) == 0L) return(invisible(NULL))
  p <- ggplot(acc, aes(x = prompt_variant, y = accuracy, fill = model)) +
    geom_col(position = position_dodge()) +
    facet_wrap(~ wave, scales = "free_x") +
    scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
    labs(title = "Accuracy by Model, Prompt Variant, and Wave",
         x = "Prompt variant", y = "Accuracy") +
    theme_minimal() +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(out_dir, "accuracy_by_wave.png"), p,
         width = 14, height = 8, dpi = 150)
}

# -----------------------------------------------------------------------------

run_module_aggregate_prediction <- function(raw, out_dir) {
  message("  [3b] aggregate prediction ...")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  df <- raw %>%
    filter(!is.na(label_cat), !is.na(predict_cat),
           !is.na(label_num), !is.na(predict_num)) %>%
    mutate(wave_order = parse_wave_order(wave))
  if (nrow(df) == 0L) {
    warning("  [3b] No valid parsed label/predict rows; skipping.")
    return(invisible(NULL))
  }

  dict <- attr(raw, "label_dict")
  category_levels <- ordered_category_levels(
    dict,
    c(df$label_cat, df$predict_cat)
  )
  if (length(category_levels) == 0L) {
    warning("  [3b] No ordered category levels available; skipping.")
    return(invisible(NULL))
  }

  source_levels <- c("Human", "LLM")
  prompt_levels <- prompt_variant_levels(df$prompt_variant)
  prompt_colour_scale <- function() {
    scale_colour_manual(
      values = prompt_variant_colour_values(prompt_levels),
      limits = prompt_levels,
      drop = FALSE
    )
  }
  category_scale <- scale_fill_manual(
    values = aggregate_category_fill_values(category_levels),
    drop = FALSE
  )

  summarise_distribution <- function(data, groups) {
    group_grid <- data %>%
      distinct(across(all_of(groups)))
    full_grid <- group_grid %>%
      crossing(
        source = factor(source_levels, levels = source_levels),
        category = factor(category_levels, levels = category_levels)
      )
    counts <- bind_rows(
      data %>%
        mutate(source = "Human", category = label_cat) %>%
        count(across(all_of(c(groups, "source", "category"))),
              name = "n_category"),
      data %>%
        mutate(source = "LLM", category = predict_cat) %>%
        count(across(all_of(c(groups, "source", "category"))),
              name = "n_category")
    ) %>%
      mutate(
        source = factor(source, levels = source_levels),
        category = factor(category, levels = category_levels)
      )
    full_grid %>%
      left_join(counts, by = c(groups, "source", "category")) %>%
      mutate(n_category = coalesce(n_category, 0L)) %>%
      group_by(across(all_of(c(groups, "source")))) %>%
      mutate(
        n_total = sum(n_category),
        proportion = if_else(n_total > 0L,
                             n_category / n_total,
                             NA_real_)
      ) %>%
      ungroup()
  }

  summarise_distribution_distance <- function(distribution, groups) {
    distribution %>%
      select(all_of(groups), source, category, n_total, proportion) %>%
      pivot_wider(
        names_from = source,
        values_from = c(n_total, proportion),
        names_sep = "_"
      ) %>%
      mutate(
        n_total_Human = coalesce(n_total_Human, 0L),
        n_total_LLM = coalesce(n_total_LLM, 0L),
        human_proportion = coalesce(proportion_Human, 0),
        llm_proportion = coalesce(proportion_LLM, 0),
        proportion_gap = llm_proportion - human_proportion,
        abs_proportion_gap = abs(proportion_gap)
      ) %>%
      arrange(across(all_of(groups)), category) %>%
      group_by(across(all_of(groups))) %>%
      summarise(
        n_human = max(n_total_Human, na.rm = TRUE),
        n_llm = max(n_total_LLM, na.rm = TRUE),
        l1_distance = sum(abs_proportion_gap, na.rm = TRUE),
        total_variation_distance = 0.5 * l1_distance,
        max_abs_category_gap = max(abs_proportion_gap, na.rm = TRUE),
        largest_gap_category =
          as.character(category[which.max(abs_proportion_gap)][1]),
        largest_gap_signed =
          proportion_gap[which.max(abs_proportion_gap)][1],
        .groups = "drop"
      )
  }

  distribution_by_wave <- summarise_distribution(
    df,
    c("model", "prompt_variant", "wave", "wave_order")
  ) %>%
    arrange(wave_order, wave, model, prompt_variant, source, category)
  distribution_overall <- summarise_distribution(
    df,
    c("model", "prompt_variant")
  ) %>%
    arrange(model, prompt_variant, source, category)

  write_csv(distribution_by_wave,
            file.path(out_dir, "aggregate_distribution_by_wave.csv"))
  write_csv(distribution_overall,
            file.path(out_dir, "aggregate_distribution_overall.csv"))

  category_gaps_by_wave <- distribution_by_wave %>%
    select(model, prompt_variant, wave, wave_order,
           source, category, n_total, proportion) %>%
    pivot_wider(
      names_from = source,
      values_from = c(n_total, proportion),
      names_sep = "_"
    ) %>%
    mutate(
      n_total_Human = coalesce(n_total_Human, 0L),
      n_total_LLM = coalesce(n_total_LLM, 0L),
      human_proportion = coalesce(proportion_Human, 0),
      llm_proportion = coalesce(proportion_LLM, 0),
      proportion_gap = llm_proportion - human_proportion,
      abs_proportion_gap = abs(proportion_gap)
    ) %>%
    arrange(wave_order, wave, model, prompt_variant, category)
  write_csv(category_gaps_by_wave,
            file.path(out_dir,
                      "aggregate_distribution_category_gaps_by_wave.csv"))

  distance_by_wave <- summarise_distribution_distance(
    distribution_by_wave,
    c("model", "prompt_variant", "wave", "wave_order")
  ) %>%
    arrange(wave_order, wave, model, prompt_variant)
  distance_overall <- summarise_distribution_distance(
    distribution_overall,
    c("model", "prompt_variant")
  ) %>%
    arrange(model, prompt_variant)

  write_csv(distance_by_wave,
            file.path(out_dir, "aggregate_distribution_distance_by_wave.csv"))
  write_csv(distance_overall,
            file.path(out_dir, "aggregate_distribution_distance_overall.csv"))

  mean_by_wave <- df %>%
    group_by(model, prompt_variant, wave, wave_order) %>%
    summarise(
      n = n(),
      human_mean = mean(label_num, na.rm = TRUE),
      llm_mean = mean(predict_num, na.rm = TRUE),
      mean_bias = llm_mean - human_mean,
      abs_mean_bias = abs(mean_bias),
      human_sd = sd(label_num, na.rm = TRUE),
      llm_sd = sd(predict_num, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(wave_order, wave, model, prompt_variant)
  mean_overall <- df %>%
    group_by(model, prompt_variant) %>%
    summarise(
      n = n(),
      human_mean = mean(label_num, na.rm = TRUE),
      llm_mean = mean(predict_num, na.rm = TRUE),
      mean_bias = llm_mean - human_mean,
      abs_mean_bias = abs(mean_bias),
      human_sd = sd(label_num, na.rm = TRUE),
      llm_sd = sd(predict_num, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(model, prompt_variant)

  write_csv(mean_by_wave,
            file.path(out_dir, "aggregate_mean_bias_by_wave.csv"))
  write_csv(mean_overall,
            file.path(out_dir, "aggregate_mean_bias_overall.csv"))

  trend_by_wave <- mean_by_wave %>%
    arrange(model, prompt_variant, wave_order, wave) %>%
    group_by(model, prompt_variant) %>%
    mutate(
      prev_wave = lag(wave),
      prev_human_mean = lag(human_mean),
      prev_llm_mean = lag(llm_mean),
      delta_human_mean = human_mean - prev_human_mean,
      delta_llm_mean = llm_mean - prev_llm_mean,
      delta_mean_gap = delta_llm_mean - delta_human_mean,
      abs_delta_mean_gap = abs(delta_mean_gap),
      aggregate_direction_aligned =
        sign(delta_human_mean) == sign(delta_llm_mean)
    ) %>%
    ungroup() %>%
    arrange(wave_order, wave, model, prompt_variant)
  write_csv(trend_by_wave,
            file.path(out_dir, "aggregate_trend_by_wave.csv"))

  direction_transition_plot_df <- trend_by_wave %>%
    filter(!is.na(prev_wave),
           !is.na(delta_human_mean),
           !is.na(delta_llm_mean),
           !is.na(aggregate_direction_aligned)) %>%
    mutate(
      transition = paste(prev_wave, wave, sep = " -> "),
      transition = factor(
        transition,
        levels = unique(transition[order(wave_order)])
      ),
      prompt_variant = factor(prompt_variant, levels = prompt_levels),
      direction_status = if_else(
        aggregate_direction_aligned,
        "Aligned",
        "Not aligned"
      ),
      direction_status = factor(direction_status,
                                levels = c("Aligned", "Not aligned")),
      direction_label = if_else(aggregate_direction_aligned, "Yes", "No")
    )
  if (nrow(direction_transition_plot_df) > 0L) {
    p_direction_transition <- ggplot(
      direction_transition_plot_df,
      aes(x = transition, y = prompt_variant, fill = direction_status)
    ) +
      geom_tile(colour = "white", linewidth = 0.6) +
      geom_text(aes(label = direction_label), size = 3) +
      facet_wrap(~ model, nrow = 1) +
      scale_fill_manual(
        values = c("Aligned" = "#2E7D32", "Not aligned" = "#C75A54"),
        drop = FALSE
      ) +
      labs(
        title = "Transition-Level Aggregate Direction Alignment",
        subtitle = "Each cell shows whether Human and LLM aggregate means move in the same direction between consecutive waves.",
        x = "Wave transition",
        y = "Prompt variant",
        fill = "Direction"
      ) +
      theme_minimal(base_size = 10) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom",
            panel.grid = element_blank())
    ggsave(file.path(out_dir,
                     "aggregate_direction_alignment_by_transition.png"),
           p_direction_transition, width = 14, height = 6.5, dpi = 150)
  }

  trend_summary <- trend_by_wave %>%
    filter(!is.na(delta_human_mean), !is.na(delta_llm_mean)) %>%
    group_by(model, prompt_variant) %>%
    summarise(
      n_transitions = n(),
      mean_abs_delta_error = mean(abs_delta_mean_gap, na.rm = TRUE),
      aggregate_direction_alignment =
        mean(aggregate_direction_aligned, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    arrange(model, prompt_variant)
  write_csv(trend_summary,
            file.path(out_dir, "aggregate_trend_summary.csv"))

  trend_summary_plot_df <- trend_summary %>%
    mutate(prompt_variant = factor(prompt_variant, levels = prompt_levels))

  p_direction_alignment <- trend_summary_plot_df %>%
    filter(!is.na(aggregate_direction_alignment)) %>%
    ggplot(aes(x = prompt_variant, y = aggregate_direction_alignment,
               fill = prompt_variant)) +
    geom_col(width = 0.7) +
    facet_wrap(~ model, nrow = 1) +
    scale_fill_manual(
      values = prompt_variant_colour_values(prompt_levels),
      limits = prompt_levels,
      drop = FALSE
    ) +
    scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
    labs(
      title = "Aggregate Direction Alignment",
      subtitle = "Share of wave-to-wave aggregate changes where LLM and Human means move in the same direction.",
      x = "Prompt variant",
      y = "Direction alignment",
      fill = "Prompt variant"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")
  ggsave(file.path(out_dir, "aggregate_direction_alignment.png"),
         p_direction_alignment, width = 12, height = 6, dpi = 150)

  wave_levels <- mean_by_wave %>%
    distinct(wave, wave_order) %>%
    arrange(wave_order, wave) %>%
    pull(wave)

  p_distance <- distance_by_wave %>%
    mutate(
      wave = factor(wave, levels = wave_levels),
      prompt_variant = factor(prompt_variant, levels = prompt_levels)
    ) %>%
    ggplot(aes(x = wave, y = total_variation_distance,
               colour = prompt_variant, group = prompt_variant)) +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2) +
    facet_wrap(~ model, nrow = 1) +
    prompt_colour_scale() +
    scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
    labs(
      title = "Aggregate Distribution Distance by Wave",
      subtitle = "Total variation distance between Human label and LLM prediction distributions.",
      x = "Wave",
      y = "Total variation distance",
      colour = "Prompt variant"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")
  ggsave(file.path(out_dir, "aggregate_distribution_distance_by_wave.png"),
         p_distance, width = 14, height = 6.5, dpi = 150)

  p_bias <- mean_by_wave %>%
    mutate(
      wave = factor(wave, levels = wave_levels),
      prompt_variant = factor(prompt_variant, levels = prompt_levels)
    ) %>%
    ggplot(aes(x = wave, y = mean_bias,
               colour = prompt_variant, group = prompt_variant)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2) +
    facet_wrap(~ model, nrow = 1) +
    prompt_colour_scale() +
    labs(
      title = "Aggregate Mean Bias by Wave",
      subtitle = "Bias is LLM aggregate mean minus Human aggregate mean.",
      x = "Wave",
      y = "Mean bias",
      colour = "Prompt variant"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")
  ggsave(file.path(out_dir, "aggregate_mean_bias_by_wave.png"),
         p_bias, width = 14, height = 6.5, dpi = 150)

  llm_trend_plot_df <- mean_by_wave %>%
    transmute(
      model,
      prompt_variant = factor(prompt_variant, levels = prompt_levels),
      wave = factor(wave, levels = wave_levels),
      wave_order,
      aggregate_mean = llm_mean
    )

  human_trend_base <- df %>%
    distinct(lfdn, wave, wave_order, label_num) %>%
    group_by(wave, wave_order) %>%
    summarise(aggregate_mean = mean(label_num, na.rm = TRUE),
              .groups = "drop") %>%
    mutate(
      wave = factor(wave, levels = wave_levels)
    )

  human_trend_plot_df <- tidyr::crossing(
    model = sort(unique(mean_by_wave$model)),
    human_trend_base
  ) %>%
    mutate(series = "Human")

  trend_colour_values <- c(
    Human = "#222222",
    prompt_variant_colour_values(prompt_levels)
  )
  trend_colour_breaks <- c("Human", prompt_levels)

  p_trend <- ggplot() +
    geom_line(
      data = human_trend_plot_df,
      aes(x = wave, y = aggregate_mean,
          colour = series, group = model),
      linetype = "dashed", linewidth = 0.85
    ) +
    geom_point(
      data = human_trend_plot_df,
      aes(x = wave, y = aggregate_mean, colour = series),
      size = 1.8
    ) +
    geom_line(
      data = llm_trend_plot_df,
      aes(x = wave, y = aggregate_mean,
          colour = prompt_variant, group = prompt_variant),
      linewidth = 0.7
    ) +
    geom_point(
      data = llm_trend_plot_df,
      aes(x = wave, y = aggregate_mean, colour = prompt_variant),
      size = 1.8
    ) +
    facet_wrap(~ model, nrow = 1) +
    scale_colour_manual(
      values = trend_colour_values,
      breaks = trend_colour_breaks,
      labels = c("Human (shared)", prompt_levels),
      drop = FALSE
    ) +
    guides(
      colour = guide_legend(
        override.aes = list(
          linetype = c("dashed", rep("solid", length(prompt_levels))),
          linewidth = c(0.85, rep(0.7, length(prompt_levels)))
        )
      )
    ) +
    labs(
      title = "Aggregate Mean Trends by Wave",
      subtitle = "Shared Human trajectory shown as a dashed reference line before individual-level dynamic evaluation.",
      x = "Wave",
      y = "Aggregate mean",
      colour = "Series"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          legend.position = "bottom")
  ggsave(file.path(out_dir, "aggregate_mean_trends_by_wave.png"),
         p_trend, width = 14, height = 6.5, dpi = 150)

  human_counts <- df %>%
    mutate(category = factor(label_cat, levels = category_levels)) %>%
    count(prompt_variant, wave, wave_order, category,
          name = "n_category")
  human_grid <- df %>%
    distinct(prompt_variant, wave, wave_order) %>%
    crossing(category = factor(category_levels, levels = category_levels))
  human_distribution_plot_df <- human_grid %>%
    left_join(human_counts,
              by = c("prompt_variant", "wave", "wave_order", "category")) %>%
    mutate(n_category = coalesce(n_category, 0L)) %>%
    group_by(prompt_variant, wave, wave_order) %>%
    mutate(
      n_total = sum(n_category),
      proportion = if_else(n_total > 0L,
                           n_category / n_total,
                           NA_real_),
      row_label = "Human"
    ) %>%
    ungroup()

  llm_distribution_plot_df <- distribution_by_wave %>%
    filter(source == "LLM") %>%
    mutate(row_label = model)

  distribution_plot_df <- bind_rows(
    human_distribution_plot_df %>%
      select(prompt_variant, wave, wave_order, category,
             n_category, n_total, proportion, row_label),
    llm_distribution_plot_df %>%
      select(prompt_variant, wave, wave_order, category,
             n_category, n_total, proportion, row_label)
  ) %>%
    mutate(
      wave = factor(wave, levels = wave_levels),
      prompt_variant = factor(prompt_variant, levels = prompt_levels),
      category = factor(category, levels = category_levels),
      row_label = factor(row_label, levels = c(
        "Human",
        sort(unique(as.character(llm_distribution_plot_df$row_label)))
      ))
    )

  p_distribution <- ggplot(
    distribution_plot_df,
    aes(x = wave, y = proportion, fill = category)
  ) +
    geom_col(width = 0.8) +
    facet_grid(row_label ~ prompt_variant) +
    category_scale +
    scale_y_continuous(labels = percent_format()) +
    labs(
      title = "Aggregate Category Distributions by Wave",
      subtitle = "Human labels and LLM predictions are compared at the population level.",
      x = "Wave",
      y = "Proportion",
      fill = "Category"
    ) +
    theme_minimal(base_size = 9) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          strip.text.y = element_text(size = 7),
          legend.position = "bottom")
  ggsave(file.path(out_dir, "aggregate_distribution_by_wave.png"),
         p_distribution, width = 16, height = 12, dpi = 150,
         limitsize = FALSE)
}

# -----------------------------------------------------------------------------

run_module_confusion_matrix <- function(raw, out_dir, min_n = CONFUSION_MIN_N) {
  message("  [4] category confusion matrix ...")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  df <- raw %>%
    filter(!is.na(label_cat), !is.na(predict_cat)) %>%
    mutate(wave_order = parse_wave_order(wave))
  if (nrow(df) == 0L) {
    warning("  [4] No valid label/predict rows; skipping.")
    return(invisible(NULL))
  }

  by_wave <- df %>%
    count(model, prompt_variant, wave, wave_order,
          label = label_cat, predict = predict_cat,
          name = "n") %>%
    group_by(model, prompt_variant, wave, wave_order, label) %>%
    mutate(label_total = sum(n),
           row_percent = n / label_total) %>%
    ungroup() %>%
    group_by(model, prompt_variant, wave, wave_order) %>%
    mutate(stratum_total = sum(n),
           overall_percent = n / stratum_total) %>%
    ungroup() %>%
    arrange(wave_order, wave, model, prompt_variant, label, predict)
  write_csv(by_wave, file.path(out_dir, "confusion_matrix_by_wave.csv"))

  overall <- df %>%
    count(model, prompt_variant,
          label = label_cat, predict = predict_cat,
          name = "n") %>%
    group_by(model, prompt_variant, label) %>%
    mutate(label_total = sum(n),
           row_percent = n / label_total) %>%
    ungroup() %>%
    group_by(model, prompt_variant) %>%
    mutate(stratum_total = sum(n),
           overall_percent = n / stratum_total) %>%
    ungroup() %>%
    arrange(model, prompt_variant, label, predict)
  write_csv(overall, file.path(out_dir, "confusion_matrix_overall.csv"))

  dict <- attr(raw, "label_dict")
  axis_levels <- ordered_category_levels(
    dict,
    c(by_wave$label, by_wave$predict, overall$label, overall$predict)
  )
  waves <- by_wave %>% distinct(wave, wave_order) %>% arrange(wave_order, wave)
  for (i in seq_len(nrow(waves))) {
    wv <- waves$wave[[i]]
    plot_df <- by_wave %>%
      filter(wave == wv, label_total >= min_n) %>%
      mutate(
        label = factor(label, levels = axis_levels),
        predict = factor(predict, levels = axis_levels),
        tile_label = sprintf("%s\nn=%s",
                             percent(row_percent, accuracy = 1),
                             comma(n))
      )
    if (nrow(plot_df) == 0L) next
    diagonal_df <- plot_df %>%
      distinct(model, prompt_variant) %>%
      crossing(diagonal_category = axis_levels) %>%
      mutate(
        label = factor(diagonal_category, levels = axis_levels),
        predict = factor(diagonal_category, levels = axis_levels)
      )
    p <- ggplot(plot_df, aes(x = predict, y = label, fill = row_percent)) +
      geom_tile(colour = "white") +
      geom_tile(
        data = diagonal_df,
        aes(x = predict, y = label),
        inherit.aes = FALSE,
        fill = NA,
        colour = "#111827",
        linewidth = 0.7
      ) +
      geom_text(aes(label = tile_label), size = 2.4, lineheight = 0.9) +
      facet_grid(model ~ prompt_variant) +
      scale_x_discrete(drop = FALSE) +
      scale_y_discrete(drop = FALSE) +
      scale_fill_gradientn(
        colours = HEATMAP_FILL_COLOURS,
        labels = percent_format(),
        limits = c(0, 1)
      ) +
      labs(
        title = sprintf("Category confusion matrix: Wave=%s", wv),
        subtitle = "Fill and first label line are row percentages within each true label; second line is raw count.",
        x = "Predicted category",
        y = "Human label",
        fill = "Row %"
      ) +
      theme_minimal(base_size = 10) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            strip.text = element_text(size = 8))
    ggsave(file.path(out_dir, sprintf("confusion_matrix_%s.png", slug(wv))),
           p, width = 14, height = 9, dpi = 150)
  }
}

# -----------------------------------------------------------------------------

run_module_trajectory <- function(raw, out_dir,
                                  delta_l_mode = c("self_trajectory",
                                                   "anchored_change")) {
  delta_l_mode <- match.arg(delta_l_mode)
  message("  [6] trajectory correlation (", delta_l_mode, ") ...")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  if (!all(c("vorwelle_label", "vorwelle_predict") %in% names(raw))) {
    warning("  [6] Missing vorwelle_label / vorwelle_predict; skipping.")
    return(invisible(NULL))
  }
  if (delta_l_mode == "self_trajectory") {
    traj <- raw %>%
      filter(!is.na(label_num), !is.na(predict_num),
             !is.na(vorwelle_label_num)) %>%
      filter(!is.na(vorwelle_predict_num)) %>%
      mutate(delta_H = label_num   - vorwelle_label_num,
             delta_L = predict_num - vorwelle_predict_num)
    delta_formula_note <- "Delta H=H(t)-H(t-1); Delta L=L(t)-L(t-1), using the previous LLM prediction."
    delta_title_suffix <- "all prompt variants"
  } else {
    traj_base <- raw %>%
      filter(str_to_lower(prompt_variant) == "trajectory",
             !is.na(label_num), !is.na(predict_num),
             !is.na(vorwelle_label_num))
    traj <- traj_base %>%
      mutate(delta_H = label_num   - vorwelle_label_num,
             delta_L = predict_num - vorwelle_label_num)
    delta_formula_note <- "Trajectory prompt only; Delta H=H(t)-H(t-1); Delta L=L(t)-H(t-1)."
    delta_title_suffix <- "trajectory prompt, anchored change"
  }
  if (nrow(traj) == 0L) {
    warning("  [6] No valid trajectory rows; skipping."); return(invisible(NULL))
  }

  safe_spearman <- function(x, y) {
    if (length(x) < 2L || length(unique(x)) < 2L || length(unique(y)) < 2L) {
      return(NA_real_)
    }
    suppressWarnings(cor(x, y, method = "spearman", use = "complete.obs"))
  }
  corr_overall <- traj %>%
    group_by(model, prompt_variant) %>%
    summarise(n = n(),
              spearman_rho = safe_spearman(delta_H, delta_L),
              .groups = "drop")
  corr_strat <- traj %>%
    mutate(wave_order = parse_wave_order(wave)) %>%
    group_by(wave, wave_order, model, prompt_variant) %>%
    summarise(n = n(),
              spearman_rho = safe_spearman(delta_H, delta_L),
              .groups = "drop") %>%
    arrange(wave_order, wave, model, prompt_variant)
  write_csv(corr_overall,
            file.path(out_dir, "trajectory_delta_correlation.csv"))
  write_csv(corr_strat,
            file.path(out_dir, "trajectory_delta_correlation_by_wave.csv"))

  summarise_change_capture <- function(data, groups) {
    data %>%
      mutate(
        rare_change = delta_H != 0,
        captured_change = delta_L != 0,
        direction_aligned = sign(delta_H) == sign(delta_L)
      ) %>%
      group_by(across(all_of(groups))) %>%
      summarise(
        n_total = n(),
        n_rare = sum(rare_change, na.rm = TRUE),
        n_captured = sum(rare_change & captured_change, na.rm = TRUE),
        n_direction_aligned = sum(rare_change & captured_change &
                                  direction_aligned, na.rm = TRUE),
        ccr = if_else(n_rare > 0L, n_captured / n_rare, NA_real_),
        cda = if_else(
          n_captured > 0L,
          n_direction_aligned / n_captured,
          NA_real_
        ),
        dccr = if_else(
          n_rare > 0L,
          n_direction_aligned / n_rare,
          NA_real_
        ),
        .groups = "drop"
      )
  }
  change_overall <- summarise_change_capture(
    traj,
    c("model", "prompt_variant")
  )
  change_by_wave <- summarise_change_capture(
    traj %>% mutate(wave_order = parse_wave_order(wave)),
    c("wave", "wave_order", "model", "prompt_variant")
  ) %>%
    arrange(wave_order, wave, model, prompt_variant)
  write_csv(change_overall,
            file.path(out_dir, "trajectory_change_capture_metrics.csv"))
  write_csv(change_by_wave,
            file.path(out_dir, "trajectory_change_capture_metrics_by_wave.csv"))

  change_plot_df <- change_by_wave %>%
    filter(n_rare >= CHANGE_CAPTURE_MIN_RARE_N) %>%
    mutate(cda = if_else(n_captured >= CHANGE_CAPTURE_MIN_CAPTURED_N,
                         cda, NA_real_)) %>%
    select(wave, wave_order, model, prompt_variant, ccr, cda, dccr) %>%
    pivot_longer(
      cols = c(ccr, cda, dccr), names_to = "metric", values_to = "value"
    ) %>%
    filter(!is.na(value)) %>%
    mutate(wave = factor(wave, levels = unique(wave[order(wave_order)])),
           metric = recode(metric,
                           ccr = "Change Capture Rate",
                           cda = "Conditional Directional Accuracy",
                           dccr = "Directional Change Capture Rate"))
  if (nrow(change_plot_df) > 0L) {
    p_change <- ggplot(change_plot_df,
                       aes(x = wave, y = value,
                           colour = prompt_variant,
                           group = prompt_variant)) +
      geom_line(linewidth = 0.7) +
      geom_point(size = 2) +
      facet_grid(metric ~ model) +
      scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
      labs(
        title = sprintf("Rare-event change capture metrics by wave (%s)",
                        delta_title_suffix),
        subtitle = sprintf(
          paste0(
            "Rare events are Delta H != 0; groups with n_rare < %s omitted; ",
            "CDA points with n_captured < %s omitted. %s"
          ),
          CHANGE_CAPTURE_MIN_RARE_N, CHANGE_CAPTURE_MIN_CAPTURED_N,
          delta_formula_note
        ),
        x = "Wave",
        y = "Metric value",
        colour = "Prompt variant"
      ) +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")
    ggsave(file.path(out_dir, "trajectory_change_capture_metrics_by_wave.png"),
           p_change, width = 15, height = 8, dpi = 150)
  }

  plot_df <- corr_strat %>%
    filter(n >= 50L, !is.na(spearman_rho)) %>%
    mutate(wave = factor(wave, levels = unique(wave[order(wave_order)])))
  if (nrow(plot_df) == 0L) return(invisible(NULL))
  p <- ggplot(plot_df, aes(x = wave, y = spearman_rho,
                           colour = prompt_variant,
                           group = prompt_variant)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    geom_line(linewidth = 0.7) +
    geom_point(size = 2) +
    facet_wrap(~ model, nrow = 1) +
    labs(
      title = sprintf("Correlation between Delta H and Delta L by wave (%s)",
                      delta_title_suffix),
      subtitle = paste("Metric: Spearman rho; groups with n < 50 omitted.",
                       delta_formula_note),
      x = "Wave",
      y = "Spearman rho (Delta H, Delta L)",
      colour = "Prompt variant"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(size = 16),
      plot.subtitle = element_text(size = 11),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "right"
    )
  ggsave(file.path(out_dir, "trajectory_delta_correlation_by_wave.png"), p,
         width = 14, height = 7, dpi = 150)
  old_scatter <- file.path(out_dir, "trajectory_delta_scatter.png")
  if (file.exists(old_scatter)) unlink(old_scatter)
  return(invisible(NULL))
}

# -----------------------------------------------------------------------------

run_module_prior_state_persistence <- function(raw, out_dir) {
  message("  [6c] prior-state persistence benchmark ...")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  required <- c("label_num", "predict_num", "vorwelle_label_num",
                "model", "prompt_variant", "wave")
  if (!all(required %in% names(raw))) {
    warning("  [6c] Missing required columns for persistence benchmark; skipping.")
    return(invisible(NULL))
  }

  traj <- raw %>%
    filter(str_to_lower(prompt_variant) == "trajectory",
           !is.na(label_num), !is.na(predict_num),
           !is.na(vorwelle_label_num)) %>%
    mutate(
      wave_order = parse_wave_order(wave),
      human_stable = label_num == vorwelle_label_num,
      trajectory_correct = predict_num == label_num,
      previous_agreement = predict_num == vorwelle_label_num
    )
  if (nrow(traj) == 0L) {
    warning("  [6c] No valid trajectory rows for persistence benchmark; skipping.")
    return(invisible(NULL))
  }

  summarise_persistence <- function(data, groups) {
    data %>%
      group_by(across(all_of(groups))) %>%
      summarise(
        n_total = n(),
        n_human_stable = sum(human_stable, na.rm = TRUE),
        n_human_changed = n_total - n_human_stable,
        n_cf_correct = n_human_stable,
        n_trajectory_correct = sum(trajectory_correct, na.rm = TRUE),
        n_previous_agreement = sum(previous_agreement, na.rm = TRUE),
        accuracy_cf = n_cf_correct / n_total,
        accuracy_trajectory = n_trajectory_correct / n_total,
        a_previous = n_previous_agreement / n_total,
        trajectory_minus_cf = accuracy_trajectory - accuracy_cf,
        previous_agreement_minus_cf = a_previous - accuracy_cf,
        .groups = "drop"
      )
  }

  persistence_overall <- summarise_persistence(
    traj,
    c("model", "prompt_variant")
  )
  persistence_by_wave <- summarise_persistence(
    traj,
    c("wave", "wave_order", "model", "prompt_variant")
  ) %>%
    arrange(wave_order, wave, model, prompt_variant)

  write_csv(persistence_overall,
            file.path(out_dir, "prior_state_persistence_overall.csv"))
  write_csv(persistence_by_wave,
            file.path(out_dir, "prior_state_persistence_by_wave.csv"))

  plot_df <- persistence_by_wave %>%
    select(wave, wave_order, model,
           carry_forward_accuracy = accuracy_cf,
           trajectory_accuracy = accuracy_trajectory,
           previous_state_agreement = a_previous) %>%
    pivot_longer(cols = c(carry_forward_accuracy,
                          trajectory_accuracy,
                          previous_state_agreement),
                 names_to = "metric", values_to = "value") %>%
    mutate(
      wave = factor(wave, levels = unique(wave[order(wave_order)])),
      metric = recode(
        metric,
        carry_forward_accuracy = "Carry-forward accuracy",
        trajectory_accuracy = "Trajectory accuracy",
        previous_state_agreement = "Previous-state agreement"
      )
    )
  if (nrow(plot_df) > 0L) {
    p <- ggplot(plot_df,
                aes(x = wave, y = value, colour = metric, group = metric)) +
      geom_line(linewidth = 0.7) +
      geom_point(size = 2) +
      facet_wrap(~ model, nrow = 1) +
      scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
      labs(
        title = "Trajectory accuracy and prior-state persistence by wave",
        subtitle = "Carry-forward uses the previous observed response as the current prediction.",
        x = "Wave",
        y = "Rate",
        colour = "Metric"
      ) +
      theme_minimal(base_size = 12) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")
    ggsave(file.path(out_dir, "prior_state_persistence_by_wave.png"), p,
           width = 14, height = 7, dpi = 150)
  }

  return(invisible(NULL))
}

# -----------------------------------------------------------------------------

run_module_statistical_baselines <- function(
    raw,
    outcome_variable,
    out_dir,
    min_n = STAT_BASELINE_MIN_N,
    maxit = STAT_BASELINE_MAXIT) {
  message("  [6d] majority and lag-covariate statistical baselines ...")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  required <- c("lfdn", "wave", "label_cat", "predict_cat",
                "vorwelle_label_cat", "model", "prompt_variant")
  if (!all(required %in% names(raw))) {
    warning("  [6d] Missing required columns for statistical baselines; skipping.")
    return(invisible(NULL))
  }

  dict <- attr(raw, "label_dict")
  category_levels <- ordered_category_levels(
    dict,
    c(raw$label_cat, raw$predict_cat, raw$vorwelle_label_cat)
  )
  if (length(category_levels) < 2L) {
    warning("  [6d] Fewer than two response categories; skipping.")
    return(invisible(NULL))
  }

  base_df <- raw %>%
    mutate(wave_order = parse_wave_order(wave))
  previous_wave_modal_lookup <- build_previous_wave_modal_lookup(base_df)
  cov <- infer_covariate_columns(base_df, outcome_variable)
  cov <- cov[vapply(cov, function(col) {
    length(unique(na.omit(base_df[[col]]))) >= 2L
  }, logical(1))]

  transition_df <- base_df %>%
    select(lfdn, wave, wave_order, label_cat, vorwelle_label_cat,
           all_of(cov)) %>%
    group_by(lfdn, wave, wave_order) %>%
    summarise(
      label_cat = first_non_missing(label_cat),
      vorwelle_label_cat = first_non_missing(vorwelle_label_cat),
      across(all_of(cov), first_non_missing),
      .groups = "drop"
    ) %>%
    filter(!is.na(lfdn), !is.na(wave_order),
           !is.na(label_cat), !is.na(vorwelle_label_cat))

  if (nrow(transition_df) == 0L) {
    warning("  [6d] No valid lag-available human transition rows; skipping.")
    return(invisible(NULL))
  }

  predictor_cols <- c("vorwelle_label_cat", cov)
  predictor_levels <- lapply(predictor_cols, function(col) {
    values <- as.character(transition_df[[col]])
    values[is.na(values) | !nzchar(values)] <- STAT_BASELINE_MISSING_LEVEL
    sort(unique(c(values, STAT_BASELINE_MISSING_LEVEL,
                  STAT_BASELINE_OTHER_LEVEL)))
  })
  names(predictor_levels) <- predictor_cols

  prepare_predictor_frame <- function(data, keep_outcome = TRUE) {
    out <- data
    for (col in predictor_cols) {
      values <- as.character(out[[col]])
      values[is.na(values) | !nzchar(values)] <- STAT_BASELINE_MISSING_LEVEL
      allowed <- predictor_levels[[col]]
      values[!(values %in% allowed)] <- STAT_BASELINE_OTHER_LEVEL
      out[[col]] <- factor(values, levels = allowed)
    }
    if (keep_outcome) {
      out$label_factor <- factor(out$label_cat, levels = category_levels)
    }
    out
  }

  fit_predict_wave <- function(wave_value) {
    target_wave_order <- transition_df %>%
      filter(wave == wave_value) %>%
      summarise(wave_order = first(wave_order)) %>%
      pull(wave_order)
    train_raw <- transition_df %>% filter(wave_order < target_wave_order)
    test_raw  <- transition_df %>% filter(wave == wave_value)
    if (nrow(train_raw) < min_n || nrow(test_raw) == 0L) {
      return(test_raw %>%
               transmute(lfdn, wave, wave_order, label_cat,
                         statistical_pred_cat = NA_character_,
                         statistical_model = "not_estimated",
                         n_train = nrow(train_raw),
                         n_test = nrow(test_raw),
                         predictor_count = 0L,
                         covariates_used = NA_character_,
                         n_classes = NA_integer_,
                         fit_convergence = NA_integer_,
                         fit_objective = NA_real_,
                         fit_deviance = NA_real_))
    }

    train <- prepare_predictor_frame(train_raw, keep_outcome = TRUE) %>%
      filter(!is.na(label_factor))
    test <- prepare_predictor_frame(test_raw, keep_outcome = FALSE)
    model_predictors <- predictor_cols[vapply(predictor_cols, function(col) {
      length(unique(train[[col]])) >= 2L
    }, logical(1))]
    if (nrow(train) < min_n ||
        length(unique(train$label_factor)) < 2L ||
        length(model_predictors) == 0L) {
      return(test_raw %>%
               transmute(lfdn, wave, wave_order, label_cat,
                         statistical_pred_cat = NA_character_,
                         statistical_model = "not_estimated",
                         n_train = nrow(train),
                         n_test = nrow(test_raw),
                         predictor_count = 0L,
                         covariates_used = NA_character_,
                         n_classes = NA_integer_,
                         fit_convergence = NA_integer_,
                         fit_objective = NA_real_,
                         fit_deviance = NA_real_))
    }

    fit_multinom <- function(cols) {
      form <- as.formula(
        paste("label_factor ~",
              paste(sprintf("`%s`", cols), collapse = " + "))
      )
      fit <- tryCatch(
        suppressWarnings(nnet::multinom(
          form,
          data = train,
          trace = FALSE,
          MaxNWts = 100000,
          maxit = maxit,
          summ = 2
        )),
        error = function(e) NULL
      )
      if (!is.null(fit) && is.null(fit$xlevels)) {
        fit$xlevels <- lapply(cols, function(col) {
          levels(droplevels(train[[col]]))
        })
        names(fit$xlevels) <- cols
      }
      fit
    }

    message("    [6d] target wave ", wave_value,
            ": n_train=", nrow(train),
            " n_test=", nrow(test_raw),
            " predictors=", length(model_predictors),
            " maxit=", maxit)

    fit <- fit_multinom(model_predictors)
    model_name <- "expanding_window_multinomial_logit_lag_covariates"
    if (is.null(fit) && "vorwelle_label_cat" %in% model_predictors) {
      model_predictors <- "vorwelle_label_cat"
      fit <- fit_multinom(model_predictors)
      model_name <- "expanding_window_multinomial_logit_lag_only_fallback"
    }
    if (is.null(fit)) {
      return(test_raw %>%
               transmute(lfdn, wave, wave_order, label_cat,
                         statistical_pred_cat = NA_character_,
                         statistical_model = "not_estimated",
                         n_train = nrow(train),
                         n_test = nrow(test_raw),
                         predictor_count = 0L,
                         covariates_used = NA_character_,
                         n_classes = NA_integer_,
                         fit_convergence = NA_integer_,
                         fit_objective = NA_real_,
                         fit_deviance = NA_real_))
    }

    fit_convergence <- if (!is.null(fit$convergence)) {
      as.integer(fit$convergence)
    } else {
      NA_integer_
    }
    fit_objective <- if (!is.null(fit$value)) fit$value else NA_real_
    fit_deviance <- if (!is.null(fit$deviance)) fit$deviance else NA_real_
    n_classes <- nlevels(droplevels(train$label_factor))

    test_for_prediction <- align_newdata_levels(test, fit, train)
    pred <- tryCatch(
      as.character(predict(fit, newdata = test_for_prediction,
                           type = "class")),
      error = function(e) rep(NA_character_, nrow(test))
    )
    test_raw %>%
      transmute(
        lfdn, wave, wave_order, label_cat,
        statistical_pred_cat = pred,
        statistical_model = model_name,
        n_train = nrow(train),
        n_test = nrow(test_raw),
        predictor_count = length(model_predictors),
        covariates_used = paste(setdiff(model_predictors,
                                        "vorwelle_label_cat"),
                                collapse = ";"),
        n_classes = n_classes,
        fit_convergence = fit_convergence,
        fit_objective = fit_objective,
        fit_deviance = fit_deviance
      )
  }

  stat_predictions <- transition_df %>%
    distinct(wave, wave_order) %>%
    arrange(wave_order, wave) %>%
    pull(wave) %>%
    lapply(fit_predict_wave) %>%
    bind_rows() %>%
    arrange(wave_order, wave, lfdn)

  write_csv(stat_predictions,
            file.path(out_dir, "lag_covariate_multinomial_logit_predictions.csv"))
  write_csv(
    stat_predictions %>%
      count(wave, wave_order, statistical_model, n_train, n_test,
            predictor_count, covariates_used, n_classes,
            fit_convergence, fit_objective, fit_deviance,
            name = "n_predictions") %>%
      mutate(iteration_limit = as.integer(maxit),
             .before = fit_convergence) %>%
      arrange(wave_order, wave, statistical_model),
    file.path(out_dir, "lag_covariate_multinomial_logit_diagnostics.csv")
  )

  traj <- base_df %>%
    filter(str_to_lower(prompt_variant) == "trajectory",
           !is.na(label_cat),
           !is.na(vorwelle_label_cat)) %>%
    select(lfdn, wave, wave_order, model, prompt_variant,
           label_cat, predict_cat, vorwelle_label_cat) %>%
    left_join(
      stat_predictions %>%
        select(lfdn, wave, wave_order, statistical_pred_cat,
               statistical_model),
      by = c("lfdn", "wave", "wave_order")
    ) %>%
    left_join(
      previous_wave_modal_lookup,
      by = c("wave", "wave_order")
    ) %>%
    mutate(
      trajectory_correct = predict_cat == label_cat,
      carry_forward_correct = vorwelle_label_cat == label_cat,
      previous_wave_modal_correct =
        previous_wave_modal_category == label_cat,
      statistical_correct = statistical_pred_cat == label_cat
    )

  if (nrow(traj) == 0L) {
    warning("  [6d] No valid trajectory rows for baseline comparison; skipping.")
    return(invisible(NULL))
  }

  write_csv(traj,
            file.path(out_dir, "trajectory_baseline_row_comparison.csv"))

  summarise_baselines <- function(data, groups) {
    data %>%
      group_by(across(all_of(groups))) %>%
      group_modify(~ {
        n_total <- nrow(.x)
        modal_categories <- unique(na.omit(.x$previous_wave_modal_category))
        modal_cat <- if (length(modal_categories) == 1L) {
          modal_categories[[1]]
        } else {
          "Varies by previous wave"
        }
        n_majority_correct <- sum(.x$previous_wave_modal_correct, na.rm = TRUE)
        n_cf_correct <- sum(.x$carry_forward_correct, na.rm = TRUE)
        n_trajectory_correct <- sum(.x$trajectory_correct, na.rm = TRUE)
        n_stat <- sum(!is.na(.x$statistical_pred_cat))
        n_stat_correct <- sum(.x$statistical_correct, na.rm = TRUE)
        accuracy_stat_available <- if (n_stat > 0L) {
          n_stat_correct / n_stat
        } else {
          NA_real_
        }
        tibble(
          n_total = n_total,
          modal_category = modal_cat,
          modal_source = "previous_wave",
          modal_share = mean(.x$previous_wave_modal_correct, na.rm = TRUE),
          n_majority_correct = n_majority_correct,
          n_cf_correct = n_cf_correct,
          n_trajectory_correct = n_trajectory_correct,
          n_statistical_pred_available = n_stat,
          n_statistical_correct = n_stat_correct,
          accuracy_majority = n_majority_correct / n_total,
          accuracy_cf = n_cf_correct / n_total,
          accuracy_trajectory = n_trajectory_correct / n_total,
          accuracy_statistical = n_stat_correct / n_total,
          accuracy_statistical_available = accuracy_stat_available,
          trajectory_minus_majority =
            accuracy_trajectory - accuracy_majority,
          trajectory_minus_cf = accuracy_trajectory - accuracy_cf,
          trajectory_minus_statistical =
            accuracy_trajectory - accuracy_statistical,
          statistical_minus_cf = accuracy_statistical - accuracy_cf
        )
      }) %>%
      ungroup()
  }

  comparison_overall <- summarise_baselines(
    traj,
    c("model", "prompt_variant")
  ) %>%
    arrange(model, prompt_variant)
  comparison_by_wave <- summarise_baselines(
    traj,
    c("wave", "wave_order", "model", "prompt_variant")
  ) %>%
    arrange(wave_order, wave, model, prompt_variant)

  write_csv(comparison_overall,
            file.path(out_dir, "statistical_baseline_comparison_overall.csv"))
  write_csv(comparison_by_wave,
            file.path(out_dir, "statistical_baseline_comparison_by_wave.csv"))

  metric_labels <- c(
    accuracy_trajectory = "Trajectory accuracy",
    accuracy_cf = "Carry-forward accuracy",
    accuracy_majority = "Previous-wave modal accuracy",
    accuracy_statistical = "Lag + covariates multinomial logit"
  )
  plot_by_wave <- comparison_by_wave %>%
    select(wave, wave_order, model, all_of(names(metric_labels))) %>%
    pivot_longer(cols = all_of(names(metric_labels)),
                 names_to = "metric", values_to = "value") %>%
    mutate(
      wave = factor(wave, levels = unique(wave[order(wave_order)])),
      metric = factor(metric, levels = names(metric_labels),
                      labels = unname(metric_labels))
    )
  if (nrow(plot_by_wave) > 0L) {
    p_wave <- ggplot(plot_by_wave,
                     aes(x = wave, y = value,
                         colour = metric, group = metric)) +
      geom_line(linewidth = 0.7) +
      geom_point(size = 2) +
      facet_wrap(~ model, nrow = 1) +
      scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
      labs(
        title = "Trajectory prompt versus non-LLM baselines by wave",
        subtitle = "Expanding-window multinomial logit uses only earlier waves, with previous response and eligible covariates.",
        x = "Wave",
        y = "Accuracy",
        colour = "Metric"
      ) +
      theme_minimal(base_size = 12) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")
    ggsave(file.path(out_dir, "statistical_baseline_comparison_by_wave.png"),
           p_wave, width = 14, height = 7, dpi = 150, bg = "white")
  }

  plot_overall <- comparison_overall %>%
    select(model, all_of(names(metric_labels))) %>%
    pivot_longer(cols = all_of(names(metric_labels)),
                 names_to = "metric", values_to = "value") %>%
    mutate(metric = factor(metric, levels = names(metric_labels),
                           labels = unname(metric_labels)))
  if (nrow(plot_overall) > 0L) {
    p_overall <- ggplot(plot_overall,
                        aes(x = model, y = value, fill = metric)) +
      geom_col(position = position_dodge(width = 0.75), width = 0.68) +
      coord_flip() +
      scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
      labs(
        title = "Trajectory prompt versus non-LLM baselines",
        subtitle = "Comparison uses the same lag-available trajectory rows for each model.",
        x = "Model",
        y = "Accuracy",
        fill = "Metric"
      ) +
      theme_minimal(base_size = 12) +
      theme(legend.position = "bottom")
    ggsave(file.path(out_dir, "statistical_baseline_comparison_overall.png"),
           p_overall, width = 12, height = 6.5, dpi = 150, bg = "white")
  }

  return(invisible(NULL))
}

# -----------------------------------------------------------------------------

run_module_covariates_only_statistical_baseline <- function(
    raw,
    outcome_variable,
    out_dir,
    min_n = STAT_BASELINE_MIN_N,
    prompt_variants = c("baseline", "baseline_notime", "tanchored"),
    maxit = STAT_BASELINE_MAXIT,
    stability_limits = integer()) {
  message("  [6e] covariates-only statistical baseline ...")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  required <- c("lfdn", "wave", "label_cat", "predict_cat",
                "model", "prompt_variant")
  if (!all(required %in% names(raw))) {
    warning("  [6e] Missing required columns for covariates-only baseline; skipping.")
    return(invisible(NULL))
  }

  dict <- attr(raw, "label_dict")
  category_levels <- ordered_category_levels(
    dict,
    c(raw$label_cat, raw$predict_cat)
  )
  if (length(category_levels) < 2L) {
    warning("  [6e] Fewer than two response categories; skipping.")
    return(invisible(NULL))
  }

  base_df <- raw %>%
    mutate(
      wave_order = parse_wave_order(wave),
      prompt_variant = str_to_lower(prompt_variant)
    )
  previous_wave_modal_lookup <- build_previous_wave_modal_lookup(base_df)
  cov <- infer_covariate_columns(base_df, outcome_variable)
  cov <- cov[vapply(cov, function(col) {
    length(unique(na.omit(base_df[[col]]))) >= 2L
  }, logical(1))]
  if (length(cov) == 0L) {
    warning("  [6e] No eligible covariates; skipping.")
    return(invisible(NULL))
  }

  current_df <- base_df %>%
    select(lfdn, wave, wave_order, label_cat, all_of(cov)) %>%
    group_by(lfdn, wave, wave_order) %>%
    summarise(
      label_cat = first_non_missing(label_cat),
      across(all_of(cov), first_non_missing),
      .groups = "drop"
    ) %>%
    filter(!is.na(lfdn), !is.na(wave_order), !is.na(label_cat))

  if (nrow(current_df) == 0L) {
    warning("  [6e] No valid human outcome rows; skipping.")
    return(invisible(NULL))
  }

  class_level_diagnostics <- current_df %>%
    distinct(wave, wave_order) %>%
    arrange(wave_order, wave) %>%
    split(.$wave) %>%
    lapply(function(wave_row) {
      wave_value <- wave_row$wave[[1]]
      wave_order_value <- wave_row$wave_order[[1]]
          train_labels <- current_df %>%
            filter(wave_order < wave_order_value) %>%
        count(label_cat, name = "n_train")
      test_labels <- current_df %>%
        filter(wave == wave_value) %>%
        count(label_cat, name = "n_test")
      tibble(
        wave = wave_value,
        wave_order = wave_order_value,
        label_cat = category_levels
      ) %>%
        left_join(train_labels, by = "label_cat") %>%
        left_join(test_labels, by = "label_cat") %>%
        mutate(
          n_train = replace_na(n_train, 0L),
          n_test = replace_na(n_test, 0L),
          absent_in_train = n_train == 0L,
          absent_in_test = n_test == 0L
        )
    }) %>%
    bind_rows() %>%
    arrange(wave_order, wave, label_cat)
  write_csv(
    class_level_diagnostics,
    file.path(out_dir, "covariates_only_class_level_diagnostics.csv")
  )

  predictor_cols <- cov
  predictor_levels <- lapply(predictor_cols, function(col) {
    values <- as.character(current_df[[col]])
    values[is.na(values) | !nzchar(values)] <- STAT_BASELINE_MISSING_LEVEL
    sort(unique(c(values, STAT_BASELINE_MISSING_LEVEL,
                  STAT_BASELINE_OTHER_LEVEL)))
  })
  names(predictor_levels) <- predictor_cols
  write_csv(
    tibble(
      model = "expanding_window_multinomial_logit_covariates_only",
      outcome_variable = outcome_variable,
      outcome_levels = paste(category_levels, collapse = ";"),
      covariate = predictor_cols,
      covariate_coding = "factor",
      missing_handling = paste0("missing values encoded as ",
                                STAT_BASELINE_MISSING_LEVEL),
      unseen_level_handling = paste0("unseen values encoded as ",
                                     STAT_BASELINE_OTHER_LEVEL)
    ),
    file.path(out_dir, "covariates_only_model_spec.csv")
  )

  prepare_predictor_frame <- function(data, keep_outcome = TRUE) {
    out <- data
    for (col in predictor_cols) {
      values <- as.character(out[[col]])
      values[is.na(values) | !nzchar(values)] <- STAT_BASELINE_MISSING_LEVEL
      allowed <- predictor_levels[[col]]
      values[!(values %in% allowed)] <- STAT_BASELINE_OTHER_LEVEL
      out[[col]] <- factor(values, levels = allowed)
    }
    if (keep_outcome) {
      out$label_factor <- factor(out$label_cat, levels = category_levels)
    }
    out
  }

  stability_limits <- sort(unique(as.integer(stability_limits)))
  stability_limits <- stability_limits[
    !is.na(stability_limits) & stability_limits > 0L
  ]
  stability_rows <- list()

  fit_predict_wave <- function(wave_value) {
    target_wave_order <- current_df %>%
      filter(wave == wave_value) %>%
      summarise(wave_order = first(wave_order)) %>%
      pull(wave_order)
    train_raw <- current_df %>% filter(wave_order < target_wave_order)
    test_raw  <- current_df %>% filter(wave == wave_value)
    if (nrow(train_raw) < min_n || nrow(test_raw) == 0L) {
      return(test_raw %>%
               transmute(lfdn, wave, wave_order, label_cat,
                         statistical_pred_cat = NA_character_,
                         statistical_model = "not_estimated",
                         n_train = nrow(train_raw),
                         n_test = nrow(test_raw),
                         predictor_count = 0L,
                         covariates_used = NA_character_,
                         n_classes = NA_integer_,
                         fit_convergence = NA_integer_,
                         fit_objective = NA_real_,
                         fit_deviance = NA_real_))
    }

    train <- prepare_predictor_frame(train_raw, keep_outcome = TRUE) %>%
      filter(!is.na(label_factor))
    test <- prepare_predictor_frame(test_raw, keep_outcome = FALSE)
    model_predictors <- predictor_cols[vapply(predictor_cols, function(col) {
      length(unique(train[[col]])) >= 2L
    }, logical(1))]
    if (nrow(train) < min_n ||
        length(unique(train$label_factor)) < 2L ||
        length(model_predictors) == 0L) {
      return(test_raw %>%
               transmute(lfdn, wave, wave_order, label_cat,
                         statistical_pred_cat = NA_character_,
                         statistical_model = "not_estimated",
                         n_train = nrow(train),
                         n_test = nrow(test_raw),
                         predictor_count = 0L,
                         covariates_used = NA_character_,
                         n_classes = NA_integer_,
                         fit_convergence = NA_integer_,
                         fit_objective = NA_real_,
                         fit_deviance = NA_real_))
    }

    fit_multinom <- function(cols, iteration_limit) {
      form <- as.formula(
        paste("label_factor ~",
              paste(sprintf("`%s`", cols), collapse = " + "))
      )
      fit <- tryCatch(
        suppressWarnings(nnet::multinom(
          form,
          data = train,
          trace = FALSE,
          MaxNWts = 100000,
          maxit = iteration_limit,
          summ = 2
        )),
        error = function(e) NULL
      )
      if (!is.null(fit) && is.null(fit$xlevels)) {
        fit$xlevels <- lapply(cols, function(col) {
          levels(droplevels(train[[col]]))
        })
        names(fit$xlevels) <- cols
      }
      fit
    }

    message("    [6e] target wave ", wave_value,
            ": n_train=", nrow(train),
            " n_test=", nrow(test_raw),
            " predictors=", length(model_predictors))
    fit_limits <- if (length(stability_limits) > 0L) {
      sort(unique(c(stability_limits, as.integer(maxit))))
    } else {
      as.integer(maxit)
    }
    fits <- setNames(
      lapply(fit_limits, function(iteration_limit) {
        fit_multinom(model_predictors, iteration_limit)
      }),
      as.character(fit_limits)
    )
    fit <- fits[[as.character(as.integer(maxit))]]
    model_name <- "expanding_window_multinomial_logit_covariates_only"
    if (is.null(fit)) {
      return(test_raw %>%
               transmute(lfdn, wave, wave_order, label_cat,
                         statistical_pred_cat = NA_character_,
                         statistical_model = "not_estimated",
                         n_train = nrow(train),
                         n_test = nrow(test_raw),
                         predictor_count = 0L,
                         covariates_used = NA_character_,
                         n_classes = NA_integer_,
                         fit_convergence = NA_integer_,
                         fit_objective = NA_real_,
                         fit_deviance = NA_real_))
    }
    fit_convergence <- if (!is.null(fit$convergence)) {
      as.integer(fit$convergence)
    } else {
      NA_integer_
    }
    fit_objective <- if (!is.null(fit$value)) fit$value else NA_real_
    fit_deviance <- if (!is.null(fit$deviance)) fit$deviance else NA_real_
    n_classes <- nlevels(droplevels(train$label_factor))

    predict_with_fit <- function(fit_object) {
      if (is.null(fit_object)) {
        return(rep(NA_character_, nrow(test)))
      }
      test_for_prediction <- align_newdata_levels(test, fit_object, train)
      tryCatch(
        as.character(predict(fit_object, newdata = test_for_prediction,
                             type = "class")),
        error = function(e) rep(NA_character_, nrow(test))
      )
    }

    predictions_by_limit <- lapply(fits, predict_with_fit)
    pred <- predictions_by_limit[[as.character(as.integer(maxit))]]

    if (length(stability_limits) > 0L) {
      n_compared <- vapply(predictions_by_limit, function(candidate) {
        sum(!is.na(candidate) & !is.na(pred))
      }, integer(1))
      agreement <- vapply(predictions_by_limit, function(candidate) {
        keep <- !is.na(candidate) & !is.na(pred)
        if (!any(keep)) return(NA_real_)
        mean(candidate[keep] == pred[keep])
      }, numeric(1))
      accuracy <- vapply(predictions_by_limit, function(candidate) {
        if (all(is.na(candidate))) return(NA_real_)
        mean(!is.na(candidate) & candidate == test_raw$label_cat)
      }, numeric(1))
      stability_rows[[length(stability_rows) + 1L]] <<- tibble(
        wave = wave_value,
        wave_order = target_wave_order,
        iteration_limit = fit_limits,
        convergence = vapply(fits, function(candidate) {
          if (is.null(candidate) || is.null(candidate$convergence)) {
            return(NA_integer_)
          }
          as.integer(candidate$convergence)
        }, integer(1)),
        objective = vapply(fits, function(candidate) {
          if (is.null(candidate) || is.null(candidate$value)) return(NA_real_)
          as.numeric(candidate$value)
        }, numeric(1)),
        deviance = vapply(fits, function(candidate) {
          if (is.null(candidate) || is.null(candidate$deviance)) {
            return(NA_real_)
          }
          as.numeric(candidate$deviance)
        }, numeric(1)),
        n_train = nrow(train),
        n_test = nrow(test_raw),
        n_classes = n_classes,
        predictor_count = length(model_predictors),
        accuracy = accuracy,
        n_predictions_compared_with_final = n_compared,
        prediction_agreement_with_final = agreement,
        final_iteration_limit = as.integer(maxit)
      )
    }

    test_raw %>%
      transmute(
        lfdn, wave, wave_order, label_cat,
        statistical_pred_cat = pred,
        statistical_model = model_name,
        n_train = nrow(train),
        n_test = nrow(test_raw),
        predictor_count = length(model_predictors),
        covariates_used = paste(model_predictors, collapse = ";"),
        n_classes = n_classes,
        fit_convergence = fit_convergence,
        fit_objective = fit_objective,
        fit_deviance = fit_deviance
      )
  }

  stat_predictions <- current_df %>%
    distinct(wave, wave_order) %>%
    arrange(wave_order, wave) %>%
    pull(wave) %>%
    lapply(fit_predict_wave) %>%
    bind_rows() %>%
    arrange(wave_order, wave, lfdn)

  write_csv(
    stat_predictions,
    file.path(out_dir, "covariates_only_multinomial_logit_predictions.csv")
  )
  write_csv(
    stat_predictions %>%
      count(wave, wave_order, statistical_model, n_train, n_test,
            predictor_count, covariates_used, n_classes,
            fit_convergence, fit_objective, fit_deviance,
            name = "n_predictions") %>%
      mutate(iteration_limit = as.integer(maxit),
             .before = fit_convergence) %>%
      arrange(wave_order, wave, statistical_model),
    file.path(out_dir, "covariates_only_multinomial_logit_diagnostics.csv")
  )
  if (length(stability_rows) > 0L) {
    write_csv(
      bind_rows(stability_rows) %>%
        arrange(wave_order, wave, iteration_limit),
      file.path(out_dir, "covariates_only_iteration_stability.csv")
    )
  }

  prompt_labels <- c(
    baseline = "Date baseline",
    baseline_notime = "No-time baseline",
    tanchored = "Context-anchored prompt"
  )
  prompt_levels <- intersect(prompt_variants, names(prompt_labels))
  nontraj <- base_df %>%
    filter(prompt_variant %in% prompt_levels,
           !is.na(label_cat)) %>%
    select(lfdn, wave, wave_order, model, prompt_variant,
           label_cat, predict_cat) %>%
    left_join(
      stat_predictions %>%
        select(lfdn, wave, wave_order, statistical_pred_cat,
               statistical_model),
      by = c("lfdn", "wave", "wave_order")
    ) %>%
    left_join(
      previous_wave_modal_lookup,
      by = c("wave", "wave_order")
    ) %>%
    mutate(
      prompt_label = recode(prompt_variant, !!!as.list(prompt_labels)),
      prompt_correct = predict_cat == label_cat,
      previous_wave_modal_correct =
        previous_wave_modal_category == label_cat,
      statistical_correct = statistical_pred_cat == label_cat
    ) %>%
    filter(!is.na(previous_wave_modal_category))

  if (nrow(nontraj) == 0L) {
    warning("  [6e] No valid non-trajectory rows for baseline comparison; skipping.")
    return(invisible(NULL))
  }

  write_csv(
    nontraj,
    file.path(out_dir, "covariates_only_nontrajectory_row_comparison.csv")
  )
  denominator_sanity_by_wave <- nontraj %>%
    group_by(model, prompt_variant, prompt_label, wave, wave_order) %>%
    summarise(
      n_llm_rows = n(),
      n_stat_pred = sum(!is.na(statistical_pred_cat)),
      n_stat_missing = sum(is.na(statistical_pred_cat)),
      share_stat_missing = mean(is.na(statistical_pred_cat)),
      same_denominator = n_stat_missing == 0L,
      .groups = "drop"
    ) %>%
    arrange(wave_order, wave, prompt_variant, model)
  denominator_sanity_overall <- nontraj %>%
    group_by(model, prompt_variant, prompt_label) %>%
    summarise(
      n_llm_rows = n(),
      n_stat_pred = sum(!is.na(statistical_pred_cat)),
      n_stat_missing = sum(is.na(statistical_pred_cat)),
      share_stat_missing = mean(is.na(statistical_pred_cat)),
      same_denominator = n_stat_missing == 0L,
      .groups = "drop"
    ) %>%
    arrange(prompt_variant, model)
  write_csv(
    denominator_sanity_by_wave,
    file.path(out_dir,
              "covariates_only_denominator_sanity_by_wave.csv")
  )
  write_csv(
    denominator_sanity_overall,
    file.path(out_dir,
              "covariates_only_denominator_sanity_overall.csv")
  )

  summarise_covariates_only <- function(data, groups) {
    data %>%
      group_by(across(all_of(groups))) %>%
      group_modify(~ {
        n_total <- nrow(.x)
        modal_categories <- unique(na.omit(.x$previous_wave_modal_category))
        modal_cat <- if (length(modal_categories) == 1L) {
          modal_categories[[1]]
        } else {
          "Varies by previous wave"
        }
        n_majority_correct <- sum(.x$previous_wave_modal_correct, na.rm = TRUE)
        n_prompt_correct <- sum(.x$prompt_correct, na.rm = TRUE)
        n_stat <- sum(!is.na(.x$statistical_pred_cat))
        n_stat_correct <- sum(.x$statistical_correct, na.rm = TRUE)
        accuracy_stat_available <- if (n_stat > 0L) {
          n_stat_correct / n_stat
        } else {
          NA_real_
        }
        tibble(
          n_total = n_total,
          modal_category = modal_cat,
          modal_source = "previous_wave",
          modal_share = mean(.x$previous_wave_modal_correct, na.rm = TRUE),
          n_majority_correct = n_majority_correct,
          n_prompt_correct = n_prompt_correct,
          n_statistical_pred_available = n_stat,
          n_statistical_correct = n_stat_correct,
          accuracy_majority = n_majority_correct / n_total,
          accuracy_prompt = n_prompt_correct / n_total,
          accuracy_statistical = n_stat_correct / n_total,
          accuracy_statistical_available = accuracy_stat_available,
          prompt_minus_majority = accuracy_prompt - accuracy_majority,
          prompt_minus_statistical = accuracy_prompt - accuracy_statistical,
          statistical_minus_majority = accuracy_statistical - accuracy_majority
        )
      }) %>%
      ungroup()
  }

  comparison_overall <- summarise_covariates_only(
    nontraj,
    c("model", "prompt_variant", "prompt_label")
  ) %>%
    arrange(prompt_variant, model)
  comparison_by_wave <- summarise_covariates_only(
    nontraj,
    c("wave", "wave_order", "model", "prompt_variant", "prompt_label")
  ) %>%
    arrange(wave_order, wave, prompt_variant, model)

  write_csv(
    comparison_overall,
    file.path(out_dir, "covariates_only_nontrajectory_comparison_overall.csv")
  )
  write_csv(
    comparison_by_wave,
    file.path(out_dir, "covariates_only_nontrajectory_comparison_by_wave.csv")
  )

  metric_labels <- c(
    accuracy_majority = "Previous-wave modal accuracy",
    accuracy_statistical = "Covariates-only multinomial logit",
    accuracy_prompt = "Non-trajectory prompt accuracy"
  )
  prompt_metric_label <- metric_labels[["accuracy_prompt"]]
  plot_by_wave <- comparison_by_wave %>%
    select(wave, wave_order, model, prompt_label, all_of(names(metric_labels))) %>%
    pivot_longer(cols = all_of(names(metric_labels)),
                 names_to = "metric", values_to = "value") %>%
    mutate(
      wave = factor(wave, levels = unique(wave[order(wave_order)])),
      prompt_label = factor(prompt_label,
                            levels = unname(prompt_labels[prompt_levels])),
      metric = factor(metric, levels = names(metric_labels),
                      labels = unname(metric_labels))
    )
  if (nrow(plot_by_wave) > 0L) {
    plot_by_wave_base <- plot_by_wave %>%
      filter(metric != prompt_metric_label)
    plot_by_wave_prompt <- plot_by_wave %>%
      filter(metric == prompt_metric_label)
    p_wave <- ggplot(plot_by_wave,
                     aes(x = wave, y = value,
                         colour = metric, group = metric)) +
      geom_line(data = plot_by_wave_base, linewidth = 0.65,
                alpha = 0.75) +
      geom_point(data = plot_by_wave_base, size = 1.6,
                 alpha = 0.75) +
      geom_line(data = plot_by_wave_prompt, linewidth = 1.05) +
      geom_point(data = plot_by_wave_prompt, size = 2.3) +
      facet_grid(prompt_label ~ model) +
      scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
      labs(
        title = "Non-trajectory prompts versus covariates-only statistical baseline by wave",
        subtitle = "Expanding-window multinomial logit uses only earlier waves and current-wave covariates.",
        x = "Wave",
        y = "Accuracy",
        colour = "Metric"
      ) +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")
    ggsave(
      file.path(out_dir, "covariates_only_nontrajectory_comparison_by_wave.png"),
      p_wave, width = 15, height = 9, dpi = 150, bg = "white"
    )
  }

  plot_overall <- comparison_overall %>%
    select(model, prompt_label, all_of(names(metric_labels))) %>%
    pivot_longer(cols = all_of(names(metric_labels)),
                 names_to = "metric", values_to = "value") %>%
    mutate(
      prompt_label = factor(prompt_label,
                            levels = unname(prompt_labels[prompt_levels])),
      metric = factor(metric, levels = names(metric_labels),
                      labels = unname(metric_labels))
    )
  if (nrow(plot_overall) > 0L) {
    p_overall <- ggplot(plot_overall,
                        aes(x = model, y = value, fill = metric)) +
      geom_col(position = position_dodge(width = 0.75), width = 0.68) +
      coord_flip() +
      facet_wrap(~ prompt_label) +
      scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
      labs(
        title = "Non-trajectory prompts versus covariates-only statistical baseline",
        subtitle = "Comparison uses the available rows for each non-trajectory prompt.",
        x = "Model",
        y = "Accuracy",
        fill = "Metric"
      ) +
      theme_minimal(base_size = 11) +
      theme(legend.position = "bottom")
    ggsave(
      file.path(out_dir, "covariates_only_nontrajectory_comparison_overall.png"),
      p_overall, width = 13, height = 7, dpi = 150, bg = "white"
    )
  }

  trajectory_by_wave_path <- file.path(
    out_dir,
    "statistical_baseline_comparison_by_wave.csv"
  )
  trajectory_overall_path <- file.path(
    out_dir,
    "statistical_baseline_comparison_overall.csv"
  )
  metric_labels_with_trajectory <- c(
    accuracy_majority = "Previous-wave modal accuracy",
    accuracy_statistical = "Covariates-only multinomial logit",
    accuracy_trajectory = "Trajectory prompt accuracy",
    accuracy_prompt = "Non-trajectory prompt accuracy"
  )
  trajectory_metric_label <-
    metric_labels_with_trajectory[["accuracy_trajectory"]]
  prompt_metric_label_with_trajectory <-
    metric_labels_with_trajectory[["accuracy_prompt"]]
  metric_colours_with_trajectory <- c(
    "Previous-wave modal accuracy" = "#F8766D",
    "Covariates-only multinomial logit" = "#00BA38",
    "Trajectory prompt accuracy" = "#A15CC6",
    "Non-trajectory prompt accuracy" = "#619CFF"
  )
  prompt_level_labels <- unname(prompt_labels[prompt_levels])

  if (file.exists(trajectory_by_wave_path) && nrow(plot_by_wave) > 0L) {
    trajectory_by_wave <- read_csv(trajectory_by_wave_path,
                                   show_col_types = FALSE) %>%
      select(wave, wave_order, model, accuracy_trajectory) %>%
      distinct()
    trajectory_plot_by_wave <- tidyr::expand_grid(
      trajectory_by_wave,
      prompt_label = prompt_level_labels
    ) %>%
      transmute(
        wave = as.character(wave),
        wave_order,
        model,
        prompt_label,
        metric = trajectory_metric_label,
        value = accuracy_trajectory
      )
    plot_by_wave_with_trajectory <- bind_rows(
      plot_by_wave %>%
        mutate(
          wave = as.character(wave),
          prompt_label = as.character(prompt_label),
          metric = as.character(metric)
        ),
      trajectory_plot_by_wave
    ) %>%
      mutate(
        wave = factor(wave, levels = unique(wave[order(wave_order)])),
        prompt_label = factor(prompt_label, levels = prompt_level_labels),
        metric = factor(metric,
                        levels = unname(metric_labels_with_trajectory))
      )
    plot_by_wave_base <- plot_by_wave_with_trajectory %>%
      filter(!metric %in% c(trajectory_metric_label,
                            prompt_metric_label_with_trajectory))
    plot_by_wave_trajectory <- plot_by_wave_with_trajectory %>%
      filter(metric == trajectory_metric_label)
    plot_by_wave_prompt <- plot_by_wave_with_trajectory %>%
      filter(metric == prompt_metric_label_with_trajectory)
    p_wave_with_trajectory <- ggplot(
      plot_by_wave_with_trajectory,
      aes(x = wave, y = value, colour = metric, group = metric)
    ) +
      geom_line(data = plot_by_wave_base, linewidth = 0.65,
                alpha = 0.75) +
      geom_point(data = plot_by_wave_base, size = 1.6,
                 alpha = 0.75) +
      geom_line(data = plot_by_wave_trajectory, linewidth = 0.95,
                linetype = "longdash") +
      geom_point(data = plot_by_wave_trajectory, size = 2.1,
                 shape = 17) +
      geom_line(data = plot_by_wave_prompt, linewidth = 1.05) +
      geom_point(data = plot_by_wave_prompt, size = 2.3) +
      facet_grid(prompt_label ~ model) +
      scale_colour_manual(values = metric_colours_with_trajectory) +
      scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
      labs(
        title = "Non-trajectory prompts, trajectory prompt, and covariates-only baseline by wave",
        subtitle = "Trajectory accuracy is from lag-available trajectory rows; covariates-only baseline uses current-wave covariates only.",
        x = "Wave",
        y = "Accuracy",
        colour = "Metric"
      ) +
      theme_minimal(base_size = 11) +
      theme(axis.text.x = element_text(angle = 45, hjust = 1),
            legend.position = "bottom")
    ggsave(
      file.path(
        out_dir,
        "covariates_only_nontrajectory_with_trajectory_comparison_by_wave.png"
      ),
      p_wave_with_trajectory, width = 15, height = 9, dpi = 150,
      bg = "white"
    )
  }

  if (file.exists(trajectory_overall_path) && nrow(plot_overall) > 0L) {
    trajectory_overall <- read_csv(trajectory_overall_path,
                                   show_col_types = FALSE) %>%
      select(model, accuracy_trajectory) %>%
      distinct()
    trajectory_plot_overall <- tidyr::expand_grid(
      trajectory_overall,
      prompt_label = prompt_level_labels
    ) %>%
      transmute(
        model,
        prompt_label,
        metric = trajectory_metric_label,
        value = accuracy_trajectory
      )
    plot_overall_with_trajectory <- bind_rows(
      plot_overall %>%
        mutate(
          prompt_label = as.character(prompt_label),
          metric = as.character(metric)
        ),
      trajectory_plot_overall
    ) %>%
      mutate(
        prompt_label = factor(prompt_label, levels = prompt_level_labels),
        metric = factor(metric,
                        levels = unname(metric_labels_with_trajectory))
      )
    p_overall_with_trajectory <- ggplot(
      plot_overall_with_trajectory,
      aes(x = model, y = value, fill = metric)
    ) +
      geom_col(position = position_dodge(width = 0.75), width = 0.68) +
      coord_flip() +
      facet_wrap(~ prompt_label) +
      scale_fill_manual(values = metric_colours_with_trajectory) +
      scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
      labs(
        title = "Non-trajectory prompts, trajectory prompt, and covariates-only baseline",
        subtitle = "Trajectory accuracy is from lag-available trajectory rows; non-trajectory comparisons use their available rows.",
        x = "Model",
        y = "Accuracy",
        fill = "Metric"
      ) +
      theme_minimal(base_size = 11) +
      theme(legend.position = "bottom")
    ggsave(
      file.path(
        out_dir,
        "covariates_only_nontrajectory_with_trajectory_comparison_overall.png"
      ),
      p_overall_with_trajectory, width = 13, height = 7, dpi = 150,
      bg = "white"
    )
  }

  return(invisible(NULL))
}

# -----------------------------------------------------------------------------
# Section
run_module_heatmap <- function(raw, out_dir,
                               delta_l_mode = c("self_trajectory",
                                                "anchored_change")) {
  delta_l_mode <- match.arg(delta_l_mode)
  message("  [7] trajectory heatmap (", delta_l_mode, ") ...")
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
  if (!all(c("vorwelle_label", "vorwelle_predict") %in% names(raw))) {
    warning("  [7] Missing vorwelle_label / vorwelle_predict; skipping.")
    return(invisible(NULL))
  }
  heat_base <- raw %>%
    filter(str_to_lower(prompt_variant) == "trajectory",
           !is.na(label_num), !is.na(predict_num),
           !is.na(vorwelle_label_num))
  if (delta_l_mode == "self_trajectory") {
    heat <- heat_base %>%
      filter(!is.na(vorwelle_predict_num)) %>%
      mutate(delta_H = label_num   - vorwelle_label_num,
             delta_L = predict_num - vorwelle_predict_num)
    delta_formula_note <- "Trajectory prompt only; Delta H=H(t)-H(t-1); Delta L=L(t)-L(t-1), using the previous LLM prediction."
    delta_title_suffix <- "trajectory prompt, previous-prediction change"
    heatmap_mode_label <- "previous-prediction change"
  } else {
    heat <- heat_base %>%
      mutate(delta_H = label_num   - vorwelle_label_num,
             delta_L = predict_num - vorwelle_label_num)
    delta_formula_note <- "Trajectory prompt only; Delta H=H(t)-H(t-1); Delta L=L(t)-H(t-1)."
    delta_title_suffix <- "trajectory prompt, anchored change"
    heatmap_mode_label <- "anchored change"
  }
  if (nrow(heat) == 0L) {
    warning("  [7] No valid trajectory rows; skipping."); return(invisible(NULL))
  }
  grid_all <- heat %>%
    count(delta_H, delta_L, name = "count") %>%
    mutate(delta_H = factor(delta_H, levels = sort(unique(delta_H))),
           delta_L = factor(delta_L, levels = sort(unique(delta_L))))
  write_csv(grid_all,
            file.path(out_dir, "trajectory_delta_grid_counts_overall.csv"))

  delta_H_levels <- sort(unique(heat$delta_H))
  delta_L_levels <- sort(unique(heat$delta_L))
  strata <- heat %>%
    mutate(wave_order = parse_wave_order(wave)) %>%
    distinct(wave, wave_order, model) %>%
    arrange(wave_order, wave, model)
  plot_records <- list()
  for (i in seq_len(nrow(strata))) {
    s <- strata[i, ]
    df_s <- heat %>% filter(wave == s$wave, model == s$model)
    if (nrow(df_s) < 10L) next
    grid_s <- df_s %>%
      count(delta_H, delta_L, name = "count") %>%
      group_by(delta_H) %>%
      mutate(row_percent = count / sum(count)) %>%
      ungroup() %>%
      complete(delta_H = delta_H_levels,
               delta_L = delta_L_levels,
               fill = list(count = 0L, row_percent = 0)) %>%
      mutate(delta_H = factor(delta_H, levels = delta_H_levels),
             delta_L = factor(delta_L, levels = delta_L_levels))
    fname_csv <- sprintf("trajectory_delta_grid_w%s_%s.csv",
                         s$wave, slug(s$model))
    write_csv(grid_s, file.path(out_dir, fname_csv))
    p <- ggplot(grid_s, aes(x = delta_L, y = delta_H, fill = row_percent)) +
      geom_tile(colour = "white") +
      scale_fill_gradientn(colours = HEATMAP_FILL_COLOURS,
                           values = seq(0, 1, length.out = length(HEATMAP_FILL_COLOURS)),
                           limits = c(0, 1),
                           labels = percent_format(accuracy = 1),
                           na.value = "#F7FCF5",
                           guide = guide_colourbar(nbin = 256,
                                                   raster = TRUE,
                                                   frame.colour = "grey60",
                                                   ticks.colour = "grey30")) +
      labs(title = sprintf("Trajectory Delta H by Delta L Heatmap (%s): Wave=%s | Model=%s",
                           delta_title_suffix, s$wave, s$model),
           subtitle = delta_formula_note,
           x = "Delta L (LLM change)", y = "Delta H (Human change)", fill = "Row %") +
      theme_minimal() +
      theme(plot.title = element_text(size = 11, face = "bold"),
            plot.subtitle = element_text(size = 8))
    fname_png <- sprintf("trajectory_delta_heatmap_w%s_%s.png",
                         s$wave, slug(s$model))
    ggsave(file.path(out_dir, fname_png), p,
           width = 8, height = 6, dpi = 100)
    plot_records[[length(plot_records) + 1L]] <- list(
      wave = s$wave,
      wave_order = s$wave_order,
      model = s$model,
      plot = p
    )
  }
  combine_heatmap_plots_by_wave(
    plot_records, out_dir, "trajectory_delta_heatmap",
    heatmap_mode_label
  )
  combine_heatmap_plots_all(
    plot_records, out_dir, "trajectory_delta_heatmap",
    heatmap_mode_label
  )
}

# -----------------------------------------------------------------------------

run_module_subgroup_correctness <- function(raw, out_dir,
                                            subgroup_vars = SUBGROUP_INDEPENDENT_VARS,
                                            source_vars = SUBGROUP_SOURCE_VARS,
                                            subgroup_fn = make_subgroup_variables,
                                            outcome_fn = make_subgroup_outcome,
                                            outcome_name = SUBGROUP_OUTCOME_NAME,
                                            min_n = SUBGROUP_MIN_N) {
  message("  [8] subgroup correctness analysis ...")
  missing_vars <- setdiff(source_vars, names(raw))
  if (length(missing_vars) > 0L) {
    warning("  [8] Missing subgroup source variables: ",
            paste(missing_vars, collapse = ", "),
            "; skipping.")
    return(invisible(NULL))
  }
  dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

  df <- subgroup_fn(raw)
  missing_subgroups <- setdiff(subgroup_vars, names(df))
  if (length(missing_subgroups) > 0L) {
    warning("  [8] Subgroup function did not create: ",
            paste(missing_subgroups, collapse = ", "),
            "; skipping.")
    return(invisible(NULL))
  }

  df <- df %>%
    mutate(wave_order = parse_wave_order(wave))
  df$subgroup_outcome <- as.logical(outcome_fn(df))
  df <- df %>%
    filter(!is.na(subgroup_outcome)) %>%
    filter(if_all(all_of(subgroup_vars), ~ !is.na(.x)))
  if (nrow(df) == 0L) {
    warning("  [8] No valid subgroup rows; skipping.")
    return(invisible(NULL))
  }

  summarise_correctness <- function(data, groups) {
    data %>%
      group_by(across(all_of(groups))) %>%
      summarise(
        outcome = outcome_name,
        n = n(),
        n_correct = sum(subgroup_outcome),
        accuracy = n_correct / n,
        se = sqrt(accuracy * (1 - accuracy) / n),
        ci_low = pmax(0, accuracy - 1.96 * se),
        ci_high = pmin(1, accuracy + 1.96 * se),
        .groups = "drop"
      )
  }

  by_wave <- summarise_correctness(
    df,
    c("model", "prompt_variant", "wave", "wave_order", subgroup_vars)
  ) %>%
    arrange(wave_order, wave, model, prompt_variant, across(all_of(subgroup_vars)))
  write_csv(by_wave, file.path(out_dir, "subgroup_correctness_by_wave.csv"))
  write_csv(by_wave %>% filter(n >= min_n),
            file.path(out_dir, "subgroup_correctness_by_wave_min_n.csv"))

  overall <- summarise_correctness(
    df,
    c("model", "prompt_variant", subgroup_vars)
  ) %>%
    arrange(model, prompt_variant, across(all_of(subgroup_vars)))
  write_csv(overall, file.path(out_dir, "subgroup_correctness_overall.csv"))
  plot_df <- overall %>%
    filter(n >= min_n) %>%
    unite("subgroup", all_of(subgroup_vars), sep = " | ", remove = FALSE) %>%
    mutate(subgroup = reorder(subgroup, accuracy))
  if (nrow(plot_df) == 0L) return(invisible(NULL))

  p <- ggplot(plot_df, aes(x = subgroup, y = accuracy, colour = model)) +
    geom_pointrange(aes(ymin = ci_low, ymax = ci_high),
                    position = position_dodge(width = 0.6),
                    linewidth = 0.4) +
    coord_flip() +
    facet_wrap(~ prompt_variant) +
    scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
    labs(
      title = "Prediction correctness by subgroup",
      subtitle = sprintf("Outcome: %s; subgroups: %s; groups with n < %s omitted.",
                         outcome_name, paste(subgroup_vars, collapse = " x "), min_n),
      x = "Subgroup",
      y = "Accuracy",
      colour = "Model"
    ) +
    theme_minimal(base_size = 11) +
    theme(axis.text.y = element_text(size = 7),
          legend.position = "bottom")
  ggsave(file.path(out_dir, "subgroup_correctness_overall.png"), p,
         width = 14, height = max(7, 0.22 * length(unique(plot_df$subgroup))),
         dpi = 150, limitsize = FALSE)

  make_gap_table <- function(data, groups) {
    data %>%
      filter(n >= min_n) %>%
      unite("subgroup", all_of(subgroup_vars), sep = " | ", remove = FALSE) %>%
      group_by(across(all_of(groups))) %>%
      summarise(
        n_groups = n(),
        min_accuracy = min(accuracy, na.rm = TRUE),
        max_accuracy = max(accuracy, na.rm = TRUE),
        accuracy_gap = max_accuracy - min_accuracy,
        worst_subgroup = subgroup[which.min(accuracy)][1],
        best_subgroup = subgroup[which.max(accuracy)][1],
        .groups = "drop"
      ) %>%
      filter(n_groups >= 2L)
  }
  fairness_gap_by_wave <- make_gap_table(
    by_wave,
    c("model", "prompt_variant", "wave", "wave_order")
  ) %>%
    arrange(wave_order, wave, model, prompt_variant)
  fairness_gap_overall <- make_gap_table(
    overall,
    c("model", "prompt_variant")
  ) %>%
    arrange(model, prompt_variant)
  write_csv(fairness_gap_by_wave,
            file.path(out_dir, "subgroup_fairness_accuracy_gaps_by_wave.csv"))
  write_csv(fairness_gap_overall,
            file.path(out_dir, "subgroup_fairness_accuracy_gaps_overall.csv"))

  bias_tests_by_wave <- by_wave %>%
    filter(n >= min_n) %>%
    unite("subgroup", all_of(subgroup_vars), sep = " | ", remove = FALSE) %>%
    group_by(model, prompt_variant, wave, wave_order) %>%
    summarise(
      n_groups = n(),
      total_n = sum(n),
      p_value = if (n_groups >= 2L) {
        tryCatch(prop.test(n_correct, n)$p.value, error = function(e) NA_real_)
      } else NA_real_,
      .groups = "drop"
    ) %>%
    mutate(p_adjust_bh = p.adjust(p_value, method = "BH")) %>%
    arrange(wave_order, wave, model, prompt_variant)
  bias_tests_overall <- overall %>%
    filter(n >= min_n) %>%
    unite("subgroup", all_of(subgroup_vars), sep = " | ", remove = FALSE) %>%
    group_by(model, prompt_variant) %>%
    summarise(
      n_groups = n(),
      total_n = sum(n),
      p_value = if (n_groups >= 2L) {
        tryCatch(prop.test(n_correct, n)$p.value, error = function(e) NA_real_)
      } else NA_real_,
      .groups = "drop"
    ) %>%
    mutate(p_adjust_bh = p.adjust(p_value, method = "BH")) %>%
    arrange(model, prompt_variant)
  write_csv(bias_tests_by_wave,
            file.path(out_dir, "subgroup_bias_prop_tests_by_wave.csv"))
  write_csv(bias_tests_overall,
            file.path(out_dir, "subgroup_bias_prop_tests_overall.csv"))

  glm_data <- by_wave %>%
    filter(n >= min_n) %>%
    mutate(n_incorrect = n - n_correct) %>%
    filter(n_correct >= 0L, n_incorrect >= 0L)
  if (nrow(glm_data) > 0L &&
      all(c("model", "prompt_variant", "wave", subgroup_vars) %in% names(glm_data))) {
    form <- as.formula(
      paste("cbind(n_correct, n_incorrect) ~ model + prompt_variant + wave +",
            paste(sprintf("factor(`%s`)", subgroup_vars), collapse = " + "))
    )
    fit <- tryCatch(glm(form, family = binomial(), data = glm_data),
                    error = function(e) NULL)
    if (!is.null(fit)) {
      bias_glm <- broom::tidy(fit) %>%
        mutate(
          odds_ratio = exp(estimate),
          conf.low.or = exp(estimate - 1.96 * std.error),
          conf.high.or = exp(estimate + 1.96 * std.error),
          p_adjust_bh = p.adjust(p.value, method = "BH")
        )
      write_csv(bias_glm,
                file.path(out_dir, "subgroup_bias_logistic_regression.csv"))
    }
  }
}

# -----------------------------------------------------------------------------

process_csv <- function(csv_path) {
  variant <- sub("^analyse_(.+)\\.csv$", "\\1", basename(csv_path))
  outcome_variable <- sub("_original_scale$", "", variant)

  message("==== variant: ", variant,
          "  (outcome=", outcome_variable, ") ====")

  base <- file.path(EVALUATION_OUTPUT_ROOT, paste0("analysis_", variant))
  dirs <- list(
    accuracy   = file.path(base, "accuracy_summary"),
    aggregate  = file.path(base, "aggregate_prediction"),
    confusion  = file.path(base, "confusion_matrix"),
    trajectory = file.path(base, "trajectory_analysis"),
    statistical = file.path(base, "statistical_baselines"),
    heatmap    = file.path(base, "trajectory_heatmap"),
    subgroup   = file.path(base, "subgroup_analysis")
  )
  for (d in dirs) dir.create(d, showWarnings = FALSE, recursive = TRUE)

  raw  <- prepare_raw(csv_path)
  dict <- attr(raw, "label_dict")


  if (length(dict$cats) > 0L) {
    dict_df <- tibble(
      code        = encode_num(dict$ordered, dict),
      category    = dict$ordered,
      tokens_used = if (dict$is_numeric) dict$ordered
                    else vapply(dict$ordered,
                                function(c) paste(dict$tokens[[c]],
                                                  collapse = "; "),
                                character(1))
    )
    write_csv(dict_df, file.path(base, "label_dictionary.csv"))
  }
  message("  rows=", nrow(raw),
          "  cats=", length(dict$cats),
          " (", if (dict$is_numeric) "numeric Likert" else "text", ")",
          "  models=", length(unique(na.omit(raw$model))),
          "  prompts=", length(unique(na.omit(raw$prompt_variant))),
          "  waves=", length(unique(na.omit(raw$wave))))
  message("  parsed: label=", sum(!is.na(raw$label_cat)),
          "/", nrow(raw),
          "  predict=", sum(!is.na(raw$predict_cat)),
          "/", nrow(raw))

  run_module_safe("[3] accuracy summary",
                  run_module_accuracy(raw, dirs$accuracy))
  run_module_safe("[3b] aggregate prediction",
                  run_module_aggregate_prediction(raw, dirs$aggregate))
  run_module_safe("[4] category confusion matrix",
                  run_module_confusion_matrix(raw, dirs$confusion))
  run_module_safe("[6a] trajectory correlation: self trajectory",
                  run_module_trajectory(
                    raw, file.path(dirs$trajectory, "self_trajectory"),
                    "self_trajectory"
                  ))
  run_module_safe("[6b] trajectory correlation: anchored change",
                  run_module_trajectory(
                    raw, file.path(dirs$trajectory, "anchored_change"),
                    "anchored_change"
                  ))
  run_module_safe("[6c] prior-state persistence benchmark",
                  run_module_prior_state_persistence(
                    raw, file.path(dirs$trajectory, "prior_state_persistence")
                  ))
  run_module_safe("[6d] majority and lag-covariate statistical baselines",
                  run_module_statistical_baselines(
                    raw, outcome_variable, dirs$statistical
                  ))
  run_module_safe("[6e] covariates-only statistical baseline",
                  run_module_covariates_only_statistical_baseline(
                    raw, outcome_variable, dirs$statistical,
                    stability_limits = if (grepl("_original_scale$", variant)) {
                      STAT_BASELINE_STABILITY_LIMITS
                    } else integer()
                  ))
  run_module_safe("[7a] trajectory heatmap: self trajectory",
                  run_module_heatmap(
                    raw, file.path(dirs$heatmap, "self_trajectory"),
                    "self_trajectory"
                  ))
  run_module_safe("[7b] trajectory heatmap: anchored change",
                  run_module_heatmap(
                    raw, file.path(dirs$heatmap, "anchored_change"),
                    "anchored_change"
                  ))
  run_module_safe("[8] subgroup correctness analysis",
                  run_module_subgroup_correctness(raw, dirs$subgroup))
  message("  -> done: ", base)
}

csv_files <- list.files(
  ANALYSIS_INPUT_DIR,
  pattern = "^analyse_.+\\.csv$",
  full.names = TRUE
)
if (length(csv_files) == 0L) {
  stop("No analyse_*.csv files found in ", ANALYSIS_INPUT_DIR,
       ". Run 02_build_analysis_inputs/scripts/build_analysis_inputs_from_jsonl.R first.")
}
variant_filter <- commandArgs(trailingOnly = TRUE)
variant_filter <- variant_filter[!startsWith(variant_filter, "--")]
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
  if (length(csv_files) == 0L) {
    stop("No analyse_*.csv files matched requested variants: ",
         paste(variant_filter, collapse = ", "))
  }
}
message("Found CSVs: ",
        paste(basename(csv_files), collapse = ", "))

for (f in csv_files) {
  process_csv(f)
}
write_statistical_baseline_display_table(EVALUATION_OUTPUT_ROOT)
organize_analysis_pngs(EVALUATION_OUTPUT_ROOT)
message("analyse_all_variants.R complete.")
