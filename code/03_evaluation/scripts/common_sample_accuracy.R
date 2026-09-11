#!/usr/bin/env Rscript
# Common-sample accuracy robustness check.
#
# This script creates a separate evaluation run that restricts all prompt
# variants to the same respondent-wave records within each
# outcome/representation x model x wave stratum. It never writes into the
# existing analysis_<variant>/ output folders.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(ggplot2)
  library(scales)
})

REQUIRED_PROMPTS <- c("baseline", "baseline_notime", "tanchored", "trajectory")
DEFAULT_VARIANTS <- c("1290", "1290_original_scale", "1500", "1500_original_scale")

clean_text <- function(x) {
  x <- as.character(x)
  x <- str_squish(x)
  x[!is.na(x) & x == ""] <- NA_character_
  x
}

parse_wave_order <- function(wave) {
  as.integer(str_extract(wave, "[0-9]+"))
}

normalize_str <- function(s) {
  s <- tolower(enc2utf8(as.character(s)))
  s <- gsub("\u00e3\u00bc", "ue", s, fixed = TRUE)
  s <- gsub("\u00e3\u00a4", "ae", s, fixed = TRUE)
  s <- gsub("\u00e3\u00b6", "oe", s, fixed = TRUE)
  s <- gsub("\u00e3\u0178", "ss", s, fixed = TRUE)
  s <- gsub("\u00e4", "ae", s, fixed = TRUE)
  s <- gsub("\u00f6", "oe", s, fixed = TRUE)
  s <- gsub("\u00fc", "ue", s, fixed = TRUE)
  s <- gsub("\u00df", "ss", s, fixed = TRUE)
  sub("^\\s*[0-9]+\\s*[\\.\\):]\\s*", "", s, perl = TRUE)
}

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
                ordered = character(0), is_numeric = FALSE,
                scores = NULL))
  }

  is_num <- all(grepl("^-?\\d+(\\.\\d+)?$", cats))
  if (is_num) {
    ordered <- cats[order(as.numeric(cats))]
    tokens <- setNames(as.list(ordered), ordered)
    return(list(cats = ordered, tokens = tokens,
                ordered = ordered, is_numeric = TRUE,
                scores = NULL))
  }

  norm_cats <- normalize_str(cats)
  is_1290_grouped <- all(c(
    any(str_detect(norm_cats, "bekaempfung.*klimawandels")),
    any(str_detect(norm_cats, "mittelposition")),
    any(str_detect(norm_cats, "wirtschaftswachstum"))
  ))
  if (is_1290_grouped && length(cats) == 3L) {
    scores <- case_when(
      str_detect(norm_cats, "bekaempfung.*klimawandels") ~ -1,
      str_detect(norm_cats, "mittelposition") ~ 0,
      str_detect(norm_cats, "wirtschaftswachstum") ~ 1,
      TRUE ~ NA_real_
    )
    if (all(!is.na(scores))) {
      tokens_per <- lapply(cats, content_tokens)
      names(tokens_per) <- cats
      freq <- table(unlist(tokens_per))
      distinguishing <- lapply(tokens_per, function(toks) {
        if (length(toks) == 0L) return(character(0))
        uniq <- toks[as.integer(freq[toks]) == 1L]
        if (length(uniq) == 0L) toks else uniq
      })
      return(list(cats = cats, tokens = distinguishing,
                  ordered = cats[order(scores)], is_numeric = FALSE,
                  scores = setNames(scores, cats)))
    }
  }

  is_1500_grouped <- all(c(
    any(norm_cats == "links"),
    any(norm_cats == "neutral"),
    any(norm_cats == "rechts")
  ))
  if (is_1500_grouped && length(cats) == 3L) {
    scores <- case_when(
      norm_cats == "links" ~ -1,
      norm_cats == "neutral" ~ 0,
      norm_cats == "rechts" ~ 1,
      TRUE ~ NA_real_
    )
    if (all(!is.na(scores))) {
      tokens_per <- lapply(cats, content_tokens)
      names(tokens_per) <- cats
      freq <- table(unlist(tokens_per))
      distinguishing <- lapply(tokens_per, function(toks) {
        if (length(toks) == 0L) return(character(0))
        uniq <- toks[as.integer(freq[toks]) == 1L]
        if (length(uniq) == 0L) toks else uniq
      })
      return(list(cats = cats, tokens = distinguishing,
                  ordered = cats[order(scores)], is_numeric = FALSE,
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

  k <- length(dict$cats)
  positions <- matrix(.Machine$integer.max, nrow = n, ncol = k,
                      dimnames = list(NULL, dict$cats))
  text_safe <- text_c
  text_safe[is.na(text_safe)] <- ""
  if (dict$is_numeric) {
    for (j in seq_len(k)) {
      pat <- sprintf("(?<![0-9])%s(?![0-9])",
                     gsub(".", "\\.", dict$cats[j], fixed = TRUE))
      pos <- as.integer(regexpr(pat, text_safe, perl = TRUE))
      pos[is.na(pos) | pos < 0L] <- .Machine$integer.max
      positions[, j] <- pos
    }
  } else {
    text_n <- normalize_str(text_safe)
    text_n <- gsub("[^a-z0-9]+", " ", text_n, perl = TRUE)
    text_n[is.na(text_n)] <- ""
    for (j in seq_len(k)) {
      toks <- dict$tokens[[dict$cats[j]]]
      if (length(toks) == 0L) next
      pat <- sprintf("\\b(?:%s)\\b", paste(toks, collapse = "|"))
      pos <- as.integer(regexpr(pat, text_n, perl = TRUE))
      pos[is.na(pos) | pos < 0L] <- .Machine$integer.max
      positions[, j] <- pos
    }
  }
  best <- max.col(-positions, ties.method = "first")
  has_hit <- positions[cbind(seq_len(n), best)] < .Machine$integer.max
  out[has_hit] <- dict$cats[best[has_hit]]
  out
}

arg_value <- function(args, name, default = NULL) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) > 0L) return(sub(prefix, "", hit[1], fixed = TRUE))
  flag_idx <- match(paste0("--", name), args)
  if (!is.na(flag_idx) && flag_idx < length(args)) return(args[flag_idx + 1L])
  default
}

detect_input_dir <- function(cwd) {
  candidates <- c(
    file.path(cwd, "data", "analysis_inputs"),
    cwd,
    file.path(cwd, "code", "data", "analysis_inputs")
  )
  for (candidate in candidates) {
    if (dir.exists(candidate) &&
        any(file.exists(file.path(candidate, paste0("analyse_", DEFAULT_VARIANTS, ".csv"))))) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }
  stop("Could not find analyse_<variant>.csv files. Pass --input-dir explicitly.")
}

detect_output_root <- function(cwd) {
  if (dir.exists(file.path(cwd, "data", "analysis_inputs"))) {
    return(file.path(cwd, "outputs", "evaluation", "common_sample_accuracy"))
  }
  file.path(cwd, "common_sample_accuracy_evaluation")
}

make_run_dir <- function(output_root, run_id = "") {
  dir.create(file.path(output_root, "runs"), showWarnings = FALSE, recursive = TRUE)
  if (nzchar(run_id)) {
    if (!grepl("^[A-Za-z0-9_.-]+$", run_id)) {
      stop("--run-id may contain only letters, numbers, dot, underscore, or hyphen.")
    }
    run_dir <- file.path(output_root, "runs", paste0("run_", run_id))
    dir.create(run_dir, showWarnings = FALSE, recursive = TRUE)
    return(run_dir)
  }
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  run_dir <- file.path(output_root, "runs", paste0("run_", stamp))
  suffix <- 1L
  while (dir.exists(run_dir)) {
    suffix <- suffix + 1L
    run_dir <- file.path(output_root, "runs", paste0("run_", stamp, "_", suffix))
  }
  dir.create(run_dir, showWarnings = FALSE, recursive = TRUE)
  run_dir
}

summarise_accuracy <- function(df, groups) {
  df %>%
    group_by(across(all_of(groups))) %>%
    summarise(
      n_total = n(),
      n_parsed_label = sum(parsed_label),
      n_parsed_predict = sum(parsed_predict),
      n_correct = sum(correct),
      accuracy = n_correct / n_total,
      accuracy_parsed = n_correct / pmax(sum(parsed_label & parsed_predict), 1L),
      .groups = "drop"
    )
}

read_analysis_input <- function(csv_path, variant) {
  message("Reading ", basename(csv_path))
  needed <- c("wave_id_from_list", "wave", "lfdn", "id", "label", "predict",
              "llm_model", "model", "prompt_variant")
  raw <- read_csv(csv_path, col_select = any_of(needed),
                  show_col_types = FALSE, progress = FALSE)

  raw <- raw %>%
    mutate(
      label = clean_text(label),
      predict = clean_text(predict),
      prompt_variant = clean_text(prompt_variant),
      wave = clean_text(if ("wave_id_from_list" %in% names(.)) {
        wave_id_from_list
      } else {
        wave
      }),
      model = clean_text(if ("llm_model" %in% names(.)) {
        coalesce(llm_model, if ("model" %in% names(.)) model else NA_character_)
      } else if ("model" %in% names(.)) {
        model
      } else {
        NA_character_
      }),
      respondent_id = clean_text(if ("lfdn" %in% names(.)) {
        lfdn
      } else if ("id" %in% names(.)) {
        id
      } else {
        NA_character_
      }),
      variant = variant,
      outcome_variable = sub("_original_scale$", "", variant),
      representation = if_else(str_detect(variant, "_original_scale$"),
                               "original_scale", "grouped"),
      wave_order = parse_wave_order(wave)
    ) %>%
    filter(!is.na(model), !is.na(prompt_variant), !is.na(wave),
           !is.na(respondent_id), prompt_variant %in% REQUIRED_PROMPTS)

  duplicate_summary <- raw %>%
    count(variant, outcome_variable, representation, model, wave, wave_order,
          respondent_id, prompt_variant, name = "n_rows") %>%
    filter(n_rows > 1L)

  if (nrow(duplicate_summary) > 0L) {
    warning(basename(csv_path), " contains duplicate respondent/model/wave/prompt rows; ",
            "keeping the first row for common-sample accounting.")
    raw <- raw %>%
      group_by(variant, outcome_variable, representation, model, wave, wave_order,
               respondent_id, prompt_variant) %>%
      slice(1L) %>%
      ungroup()
  }

  dict <- build_label_dict(raw$label)
  raw <- raw %>%
    mutate(
      label_cat = match_to_category(label, dict),
      predict_cat = match_to_category(predict, dict),
      parsed_label = !is.na(label_cat),
      parsed_predict = !is.na(predict_cat),
      correct = parsed_label & parsed_predict & label_cat == predict_cat
    )

  list(raw = raw, duplicates = duplicate_summary)
}

format_num <- function(x, digits = 3L) {
  ifelse(is.na(x), "", formatC(x, format = "f", digits = digits))
}

markdown_table <- function(df, digits = 3L) {
  if (nrow(df) == 0L) return("(no rows)")
  df_print <- df
  for (nm in names(df_print)) {
    if (is.numeric(df_print[[nm]]) && !grepl("^n_|_n$|count", nm)) {
      df_print[[nm]] <- format_num(df_print[[nm]], digits)
    }
  }
  header <- paste0("| ", paste(names(df_print), collapse = " | "), " |")
  sep <- paste0("| ", paste(rep("---", ncol(df_print)), collapse = " | "), " |")
  rows <- apply(df_print, 1L, function(x) {
    paste0("| ", paste(x, collapse = " | "), " |")
  })
  paste(c(header, sep, rows), collapse = "\n")
}

write_report <- function(run_dir, input_dir, variants, full_overall, common_overall,
                         pooled_common, best_non_comparison, retention_by_wave) {
  n_combo <- nrow(best_non_comparison)
  n_traj_wins <- sum(best_non_comparison$trajectory_minus_best_non > 0, na.rm = TRUE)
  n_traj_ties <- sum(best_non_comparison$trajectory_minus_best_non == 0, na.rm = TRUE)
  n_traj_losses <- sum(best_non_comparison$trajectory_minus_best_non < 0, na.rm = TRUE)

  advantage_range <- range(best_non_comparison$trajectory_minus_best_non,
                           na.rm = TRUE)
  if (!all(is.finite(advantage_range))) advantage_range <- c(NA_real_, NA_real_)

  pooled_table <- pooled_common %>%
    select(variant, representation, prompt_variant, n_total, accuracy) %>%
    arrange(variant, prompt_variant)

  best_non_table <- best_non_comparison %>%
    select(variant, representation, model, n_common = trajectory_n_total,
           trajectory_accuracy, best_nontrajectory_prompt,
           best_nontrajectory_accuracy, trajectory_minus_best_non) %>%
    arrange(variant, model)

  retention_table <- retention_by_wave %>%
    group_by(variant, representation, prompt_variant) %>%
    summarise(
      n_full = sum(n_full),
      n_common = sum(n_common),
      common_share = n_common / pmax(n_full, 1L),
      .groups = "drop"
    ) %>%
    arrange(variant, prompt_variant)

  report <- c(
    "# Common-Sample Accuracy Evaluation",
    "",
    paste0("Execution timestamp: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    "",
    paste0("Input directory: `", normalizePath(input_dir, winslash = "/", mustWork = TRUE), "`"),
    paste0("Variants: `", paste(variants, collapse = "`, `"), "`"),
    "",
    "## Definition",
    "",
    paste(
      "For each outcome representation, model, and wave, the common sample is",
      "the set of respondent IDs present under all four prompt variants:",
      "`baseline`, `baseline_notime`, `tanchored`, and `trajectory`.",
      "Accuracy is then recomputed separately for each prompt on this identical",
      "respondent-wave set."
    ),
    "",
    paste(
      "The analysis uses the retained evaluation rows in the existing",
      "`analyse_<variant>.csv` files. If unresolved grouped predictions were",
      "already removed before those files were written, they cannot be restored",
      "by this robustness check."
    ),
    "",
    "## Main Check",
    "",
    paste0(
      "Across ", n_combo, " outcome-representation/model combinations, the",
      " trajectory prompt is higher than the best non-trajectory prompt in ",
      n_traj_wins, " combinations, tied in ", n_traj_ties,
      ", and lower in ", n_traj_losses, "."
    ),
    paste0(
      "The common-sample trajectory advantage over the best non-trajectory",
      " prompt ranges from ", format_num(advantage_range[1]), " to ",
      format_num(advantage_range[2]), " accuracy points."
    ),
    "",
    "## Pooled Common-Sample Accuracy",
    "",
    markdown_table(pooled_table),
    "",
    "## Trajectory Compared With Best Non-Trajectory Prompt",
    "",
    markdown_table(best_non_table),
    "",
    "## Common-Sample Retention",
    "",
    markdown_table(retention_table),
    "",
    "## Output Files",
    "",
    "- `full_sample_accuracy_by_wave.csv`",
    "- `full_sample_accuracy_overall.csv`",
    "- `common_sample_set_sizes_by_wave.csv`",
    "- `common_sample_retention_by_wave.csv`",
    "- `common_sample_accuracy_by_wave.csv`",
    "- `common_sample_accuracy_overall.csv`",
    "- `common_sample_accuracy_pooled.csv`",
    "- `common_vs_full_accuracy_overall.csv`",
    "- `trajectory_vs_nontrajectory_common_sample.csv`",
    "- `trajectory_vs_best_nontrajectory_common_sample.csv`",
    "- `common_sample_accuracy_by_wave.png`",
    "- `common_sample_accuracy_overall.png`",
    "- `trajectory_advantage_vs_best_nontrajectory.png`"
  )

  writeLines(report, file.path(run_dir, "common_sample_accuracy_report.md"),
             useBytes = TRUE)
}

main <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  cwd <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  input_dir <- arg_value(args, "input-dir", detect_input_dir(cwd))
  output_root <- arg_value(args, "output-root", detect_output_root(cwd))
  run_id <- arg_value(
    args, "run-id", Sys.getenv("COMMON_SAMPLE_RUN_ID", unset = "")
  )
  variants_arg <- arg_value(args, "variants", paste(DEFAULT_VARIANTS, collapse = ","))
  variants <- trimws(unlist(strsplit(variants_arg, ",", fixed = TRUE)))
  variants <- variants[nzchar(variants)]

  input_dir <- normalizePath(input_dir, winslash = "/", mustWork = TRUE)
  output_root <- normalizePath(output_root, winslash = "/", mustWork = FALSE)
  run_dir <- make_run_dir(output_root, run_id)
  message("Writing common-sample evaluation to: ", run_dir)

  csv_paths <- file.path(input_dir, paste0("analyse_", variants, ".csv"))
  missing <- csv_paths[!file.exists(csv_paths)]
  if (length(missing) > 0L) {
    stop("Missing input CSV files: ", paste(missing, collapse = ", "))
  }

  loaded <- Map(read_analysis_input, csv_paths, variants)
  raw <- bind_rows(lapply(loaded, `[[`, "raw"))
  duplicates <- bind_rows(lapply(loaded, `[[`, "duplicates"))

  if (nrow(duplicates) > 0L) {
    write_csv(duplicates, file.path(run_dir, "duplicate_prompt_rows.csv"))
  }

  id_groups <- c("variant", "outcome_variable", "representation",
                 "model", "wave", "wave_order")
  prompt_groups <- c(id_groups, "prompt_variant")

  full_by_wave <- summarise_accuracy(raw, prompt_groups) %>%
    arrange(variant, model, wave_order, prompt_variant)
  full_overall <- summarise_accuracy(
    raw,
    c("variant", "outcome_variable", "representation", "model", "prompt_variant")
  ) %>%
    arrange(variant, model, prompt_variant)

  presence <- raw %>%
    distinct(across(all_of(c(id_groups, "respondent_id", "prompt_variant"))))

  common_keys <- presence %>%
    group_by(across(all_of(c(id_groups, "respondent_id")))) %>%
    summarise(
      n_required_prompts_present = sum(REQUIRED_PROMPTS %in% prompt_variant),
      prompts_present = paste(sort(unique(prompt_variant)), collapse = ";"),
      .groups = "drop"
    ) %>%
    filter(n_required_prompts_present == length(REQUIRED_PROMPTS))

  common_set_sizes <- common_keys %>%
    count(across(all_of(id_groups)), name = "n_common_respondent_wave") %>%
    arrange(variant, model, wave_order)

  common_raw <- raw %>%
    semi_join(common_keys, by = c(id_groups, "respondent_id"))

  common_by_wave <- summarise_accuracy(common_raw, prompt_groups) %>%
    arrange(variant, model, wave_order, prompt_variant)
  common_overall <- summarise_accuracy(
    common_raw,
    c("variant", "outcome_variable", "representation", "model", "prompt_variant")
  ) %>%
    arrange(variant, model, prompt_variant)
  pooled_common <- summarise_accuracy(
    common_raw,
    c("variant", "outcome_variable", "representation", "prompt_variant")
  ) %>%
    arrange(variant, prompt_variant)

  retention_by_wave <- full_by_wave %>%
    select(all_of(prompt_groups), n_full = n_total) %>%
    left_join(
      common_by_wave %>% select(all_of(prompt_groups), n_common = n_total),
      by = prompt_groups
    ) %>%
    mutate(
      n_common = coalesce(n_common, 0L),
      n_dropped = n_full - n_common,
      common_share = n_common / pmax(n_full, 1L)
    ) %>%
    arrange(variant, model, wave_order, prompt_variant)

  common_vs_full <- full_overall %>%
    select(variant, outcome_variable, representation, model, prompt_variant,
           n_full = n_total, accuracy_full = accuracy,
           accuracy_parsed_full = accuracy_parsed) %>%
    left_join(
      common_overall %>%
        select(variant, outcome_variable, representation, model, prompt_variant,
               n_common = n_total, accuracy_common = accuracy,
               accuracy_parsed_common = accuracy_parsed),
      by = c("variant", "outcome_variable", "representation",
             "model", "prompt_variant")
    ) %>%
    mutate(
      n_common = coalesce(n_common, 0L),
      accuracy_common_minus_full = accuracy_common - accuracy_full,
      parsed_accuracy_common_minus_full =
        accuracy_parsed_common - accuracy_parsed_full
    ) %>%
    arrange(variant, model, prompt_variant)

  traj_common <- common_overall %>%
    filter(prompt_variant == "trajectory") %>%
    select(variant, outcome_variable, representation, model,
           trajectory_n_total = n_total,
           trajectory_accuracy = accuracy,
           trajectory_accuracy_parsed = accuracy_parsed)

  nontraj_common <- common_overall %>%
    filter(prompt_variant != "trajectory") %>%
    select(variant, outcome_variable, representation, model,
           nontrajectory_prompt = prompt_variant,
           nontrajectory_n_total = n_total,
           nontrajectory_accuracy = accuracy,
           nontrajectory_accuracy_parsed = accuracy_parsed)

  trajectory_vs_non <- nontraj_common %>%
    left_join(traj_common,
              by = c("variant", "outcome_variable", "representation", "model")) %>%
    mutate(
      trajectory_minus_nontrajectory =
        trajectory_accuracy - nontrajectory_accuracy,
      trajectory_minus_nontrajectory_parsed =
        trajectory_accuracy_parsed - nontrajectory_accuracy_parsed
    ) %>%
    arrange(variant, model, nontrajectory_prompt)

  best_non <- nontraj_common %>%
    group_by(variant, outcome_variable, representation, model) %>%
    slice_max(order_by = nontrajectory_accuracy, n = 1L,
              with_ties = FALSE) %>%
    ungroup() %>%
    rename(
      best_nontrajectory_prompt = nontrajectory_prompt,
      best_nontrajectory_n_total = nontrajectory_n_total,
      best_nontrajectory_accuracy = nontrajectory_accuracy,
      best_nontrajectory_accuracy_parsed = nontrajectory_accuracy_parsed
    )

  best_non_comparison <- traj_common %>%
    left_join(best_non,
              by = c("variant", "outcome_variable", "representation", "model")) %>%
    mutate(
      trajectory_minus_best_non =
        trajectory_accuracy - best_nontrajectory_accuracy,
      trajectory_minus_best_non_parsed =
        trajectory_accuracy_parsed - best_nontrajectory_accuracy_parsed
    ) %>%
    arrange(variant, model)

  write_csv(full_by_wave, file.path(run_dir, "full_sample_accuracy_by_wave.csv"))
  write_csv(full_overall, file.path(run_dir, "full_sample_accuracy_overall.csv"))
  write_csv(common_set_sizes, file.path(run_dir, "common_sample_set_sizes_by_wave.csv"))
  write_csv(retention_by_wave, file.path(run_dir, "common_sample_retention_by_wave.csv"))
  write_csv(common_by_wave, file.path(run_dir, "common_sample_accuracy_by_wave.csv"))
  write_csv(common_overall, file.path(run_dir, "common_sample_accuracy_overall.csv"))
  write_csv(pooled_common, file.path(run_dir, "common_sample_accuracy_pooled.csv"))
  write_csv(common_vs_full, file.path(run_dir, "common_vs_full_accuracy_overall.csv"))
  write_csv(trajectory_vs_non,
            file.path(run_dir, "trajectory_vs_nontrajectory_common_sample.csv"))
  write_csv(best_non_comparison,
            file.path(run_dir, "trajectory_vs_best_nontrajectory_common_sample.csv"))

  prompt_levels <- REQUIRED_PROMPTS
  plot_common <- common_by_wave %>%
    mutate(
      prompt_variant = factor(prompt_variant, levels = prompt_levels),
      wave = factor(wave, levels = unique(wave[order(wave_order)]))
    )

  p_wave <- ggplot(plot_common,
                   aes(x = prompt_variant, y = accuracy, fill = prompt_variant)) +
    geom_col(width = 0.72) +
    facet_grid(variant + model ~ wave) +
    scale_y_continuous(labels = percent_format(accuracy = 1),
                       limits = c(0, 1)) +
    scale_fill_manual(values = c(
      baseline = "#F8766D",
      baseline_notime = "#7CAE00",
      tanchored = "#00BFC4",
      trajectory = "#C77CFF"
    )) +
    labs(
      title = "Common-Sample Accuracy by Wave",
      subtitle = "Within each outcome/representation x model x wave, all prompt variants use the same respondent IDs.",
      x = "Prompt variant",
      y = "Accuracy",
      fill = "Prompt variant"
    ) +
    theme_minimal(base_size = 9) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1),
          strip.text.y = element_text(size = 7))
  ggsave(file.path(run_dir, "common_sample_accuracy_by_wave.png"),
         p_wave, width = 18, height = 16, dpi = 150, limitsize = FALSE)

  plot_overall <- common_overall %>%
    mutate(prompt_variant = factor(prompt_variant, levels = prompt_levels))
  p_overall <- ggplot(plot_overall,
                      aes(x = prompt_variant, y = accuracy,
                          fill = prompt_variant)) +
    geom_col(width = 0.72) +
    facet_grid(variant ~ model) +
    scale_y_continuous(labels = percent_format(accuracy = 1),
                       limits = c(0, 1)) +
    scale_fill_manual(values = c(
      baseline = "#F8766D",
      baseline_notime = "#7CAE00",
      tanchored = "#00BFC4",
      trajectory = "#C77CFF"
    )) +
    labs(
      title = "Common-Sample Accuracy, Pooled Across Waves",
      x = "Prompt variant",
      y = "Accuracy",
      fill = "Prompt variant"
    ) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 45, hjust = 1))
  ggsave(file.path(run_dir, "common_sample_accuracy_overall.png"),
         p_overall, width = 14, height = 9, dpi = 150, limitsize = FALSE)

  advantage_plot_data <- best_non_comparison %>%
    mutate(
      task = recode(
        variant,
        "1290" = "Climate-growth\ngrouped",
        "1290_original_scale" = "Climate-growth\noriginal scale",
        "1500" = "Left-right\ngrouped",
        "1500_original_scale" = "Left-right\noriginal scale"
      ),
      task = factor(
        task,
        levels = c(
          "Climate-growth\ngrouped",
          "Climate-growth\noriginal scale",
          "Left-right\ngrouped",
          "Left-right\noriginal scale"
        )
      ),
      model_label = recode(
        model,
        "Llama-3_3-70B-Instruct" = "Llama-3.3-70B",
        "Mistral-7B-Instruct-v0_3" = "Mistral-7B",
        "Qwen2_5-7B-Instruct-GPTQ-Int4" = "Qwen2.5-7B",
        "Qwen2_5-32B-Instruct" = "Qwen2.5-32B",
        "Qwen2_5-72B-Instruct" = "Qwen2.5-72B",
        .default = model
      )
    )

  p_adv <- ggplot(advantage_plot_data,
                  aes(x = task, y = trajectory_minus_best_non,
                      fill = model_label)) +
    geom_hline(yintercept = 0, linetype = "dashed", colour = "grey45") +
    geom_col(position = position_dodge(width = 0.8), width = 0.72) +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    labs(
      title = "Trajectory Advantage on the Common Sample",
      subtitle = "Difference between trajectory accuracy and the best non-trajectory prompt in the same model/outcome.",
      x = "Task representation",
      y = "Trajectory minus best non-trajectory accuracy",
      fill = "Model"
    ) +
    theme_minimal(base_size = 10) +
    theme(axis.text.x = element_text(angle = 25, hjust = 1))
  ggsave(file.path(run_dir, "trajectory_advantage_vs_best_nontrajectory.png"),
         p_adv, width = 12, height = 7, dpi = 150, limitsize = FALSE)

  write_report(run_dir, input_dir, variants, full_overall, common_overall,
               pooled_common, best_non_comparison, retention_by_wave)

  message("Common-sample evaluation complete: ", run_dir)
}

main()
