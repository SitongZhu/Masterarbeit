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

prepare_raw_statistical_light <- function(csv_path) {
  raw <- readr::read_csv(
    csv_path,
    col_select = c(
      tidyselect::any_of(c(
        "wave_id_from_list", "wave", "lfdn", "id", "label", "predict",
        "llm_model", "model", "prompt_variant"
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
    } else NA_character_
  )
  raw$lfdn <- clean_text(
    if ("lfdn" %in% names(raw)) raw$lfdn
    else if ("id" %in% names(raw)) raw$id
    else NA_character_
  )

  dict <- build_label_dict(raw$label)
  raw$label_cat <- match_to_category(raw$label, dict)
  raw$predict_cat <- match_to_category(raw$predict, dict)
  attr(raw, "label_dict") <- dict
  raw
}

write_covariates_only_display_table <- function(evaluation_root) {
  variants <- tibble::tribble(
    ~variant, ~task,
    "1290", "Climate-growth grouped",
    "1290_original_scale", "Climate-growth original",
    "1500", "Left-right grouped",
    "1500_original_scale", "Left-right original"
  )

  read_covariates_only <- function(variant) {
    path <- file.path(
      evaluation_root,
      paste0("analysis_", variant),
      "statistical_baselines",
      "covariates_only_nontrajectory_comparison_overall.csv"
    )
    if (!file.exists(path)) {
      return(tibble())
    }
    read_csv(path, show_col_types = FALSE) %>%
      mutate(modal_category = as.character(modal_category))
  }

  compact <- variants %>%
    mutate(data = purrr::map(variant, read_covariates_only)) %>%
    select(variant, task, data) %>%
    tidyr::unnest(data)
  if (nrow(compact) == 0L) {
    warning("No covariates-only comparison files found for display table.")
    return(invisible(NULL))
  }

  format3 <- function(x) {
    ifelse(is.na(x), NA_character_, sprintf("%.3f", x))
  }

  compact <- compact %>%
    mutate(
      model_short = case_when(
        str_detect(model, "Mistral") ~ "Mistral-7B",
        str_detect(model, "Llama-3_3-70B") ~ "Llama-3.3-70B",
        str_detect(model, "72B") ~ "Qwen2.5-72B",
        str_detect(model, "32B") ~ "Qwen2.5-32B",
        str_detect(model, "7B") ~ "Qwen2.5-7B",
        TRUE ~ model
      ),
      prompt_label = factor(
        prompt_label,
        levels = c("No-time baseline", "Date baseline",
                   "Context-anchored prompt")
      ),
      task = factor(task, levels = variants$task)
    ) %>%
    arrange(task, prompt_label, model_short)

  tables_dir <- file.path(evaluation_root, "tables")
  dir.create(tables_dir, showWarnings = FALSE, recursive = TRUE)

  write_csv(
    compact,
    file.path(tables_dir,
              "covariates_only_statistical_baseline_comparison.csv")
  )

  display <- compact %>%
    transmute(
      Task = as.character(task),
      Prompt = as.character(prompt_label),
      Model = model_short,
      N = n_total,
      Modal = modal_category,
      PreviousWaveModal = format3(accuracy_majority),
      CovariatesOnly = format3(accuracy_statistical),
      LLMPrompt = format3(accuracy_prompt),
      `Prompt-PreviousWaveModal` = format3(prompt_minus_majority),
      `Prompt-Stat` = format3(prompt_minus_statistical),
      NStat = n_statistical_pred_available
    )

  out <- file.path(
    tables_dir,
    "covariates_only_statistical_baseline_comparison_display.csv"
  )
  write_csv(display, out)
  message("wrote ", out)
  invisible(display)
}

write_covariates_only_audit_files <- function(evaluation_root) {
  variants <- c("1290", "1290_original_scale", "1500", "1500_original_scale")
  for (variant in variants) {
    out_dir <- file.path(evaluation_root, paste0("analysis_", variant),
                         "statistical_baselines")
    row_path <- file.path(
      out_dir,
      "covariates_only_nontrajectory_row_comparison.csv"
    )
    pred_path <- file.path(
      out_dir,
      "covariates_only_multinomial_logit_predictions.csv"
    )
    diag_path <- file.path(
      out_dir,
      "covariates_only_multinomial_logit_diagnostics.csv"
    )

    if (file.exists(row_path)) {
      row_df <- read_csv(row_path, show_col_types = FALSE)
      denominator_sanity_by_wave <- row_df %>%
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
      denominator_sanity_overall <- row_df %>%
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
    }

    if (file.exists(pred_path)) {
      pred_df <- read_csv(pred_path, show_col_types = FALSE)
      category_levels <- ordered_category_levels(NULL, pred_df$label_cat)
      class_level_diagnostics <- pred_df %>%
        distinct(wave, wave_order) %>%
        arrange(wave_order, wave) %>%
        split(.$wave) %>%
        lapply(function(wave_row) {
          wave_value <- wave_row$wave[[1]]
          wave_order_value <- wave_row$wave_order[[1]]
          train_labels <- pred_df %>%
            filter(wave_order < wave_order_value) %>%
            count(label_cat, name = "n_train")
          test_labels <- pred_df %>%
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
    }

    if (file.exists(diag_path)) {
      diag_df <- read_csv(diag_path, show_col_types = FALSE)
      covariates_used <- diag_df$covariates_used[
        !is.na(diag_df$covariates_used) & nzchar(diag_df$covariates_used)
      ][1]
      if (!is.na(covariates_used)) {
        covariates <- unlist(strsplit(covariates_used, ";", fixed = TRUE))
        write_csv(
          tibble(
            model = "expanding_window_multinomial_logit_covariates_only",
            variant = variant,
            covariate = covariates,
            covariate_coding = "factor",
            missing_handling = paste0("missing values encoded as ",
                                      STAT_BASELINE_MISSING_LEVEL),
            unseen_level_handling = paste0("unseen values encoded as ",
                                           STAT_BASELINE_OTHER_LEVEL)
          ),
          file.path(out_dir, "covariates_only_model_spec.csv")
        )
      }
    }
  }
}

write_trajectory_statistical_baseline_plots_from_existing <- function(
    evaluation_root) {
  variants <- c("1290", "1290_original_scale", "1500", "1500_original_scale")
  metric_labels <- c(
    accuracy_trajectory = "Trajectory accuracy",
    accuracy_cf = "Carry-forward accuracy",
    accuracy_majority = "Previous-wave modal accuracy",
    accuracy_statistical = "Lag + covariates multinomial logit"
  )

  for (variant in variants) {
    out_dir <- file.path(evaluation_root, paste0("analysis_", variant),
                         "statistical_baselines")
    by_wave_path <- file.path(
      out_dir, "statistical_baseline_comparison_by_wave.csv"
    )
    overall_path <- file.path(
      out_dir, "statistical_baseline_comparison_overall.csv"
    )
    if (!file.exists(by_wave_path) || !file.exists(overall_path)) next

    comparison_by_wave <- read_csv(by_wave_path, show_col_types = FALSE)
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
      p_wave <- ggplot(
        plot_by_wave,
        aes(x = wave, y = value, colour = metric, group = metric)
      ) +
        geom_line(linewidth = 0.7) +
        geom_point(size = 2) +
        facet_wrap(~ model, nrow = 1) +
        scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
        labs(
          title = "Trajectory prompt versus non-LLM baselines by wave",
          subtitle = paste(
            "Expanding-window multinomial logit uses only earlier waves,",
            "with previous response and eligible covariates."
          ),
          x = "Wave",
          y = "Accuracy",
          colour = "Metric"
        ) +
        theme_minimal(base_size = 12) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1),
              legend.position = "bottom")
      ggsave(
        file.path(out_dir, "statistical_baseline_comparison_by_wave.png"),
        p_wave, width = 14, height = 7, dpi = 150, bg = "white"
      )
    }

    comparison_overall <- read_csv(overall_path, show_col_types = FALSE)
    plot_overall <- comparison_overall %>%
      select(model, all_of(names(metric_labels))) %>%
      pivot_longer(cols = all_of(names(metric_labels)),
                   names_to = "metric", values_to = "value") %>%
      mutate(metric = factor(metric, levels = names(metric_labels),
                             labels = unname(metric_labels)))
    if (nrow(plot_overall) > 0L) {
      p_overall <- ggplot(
        plot_overall,
        aes(x = model, y = value, fill = metric)
      ) +
        geom_col(position = position_dodge(width = 0.75), width = 0.68) +
        coord_flip() +
        scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
        labs(
          title = "Trajectory prompt versus non-LLM baselines",
          subtitle = paste(
            "Comparison uses the same lag-available trajectory rows;",
            "statistical models are trained on earlier waves only."
          ),
          x = "Model",
          y = "Accuracy",
          fill = "Metric"
        ) +
        theme_minimal(base_size = 12) +
        theme(legend.position = "bottom")
      ggsave(
        file.path(out_dir, "statistical_baseline_comparison_overall.png"),
        p_overall, width = 12, height = 6.5, dpi = 150, bg = "white"
      )
    }
  }
  invisible(NULL)
}

write_covariates_only_plots_from_existing <- function(evaluation_root) {
  variants <- c("1290", "1290_original_scale", "1500", "1500_original_scale")
  prompt_levels <- c(
    "No-time baseline",
    "Date baseline",
    "Context-anchored prompt"
  )
  metric_labels <- c(
    accuracy_majority = "Previous-wave modal accuracy",
    accuracy_statistical = "Covariates-only multinomial logit",
    accuracy_prompt = "Non-trajectory prompt accuracy"
  )
  prompt_metric_label <- metric_labels[["accuracy_prompt"]]
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

  add_prompt_label <- function(df) {
    if ("prompt_label" %in% names(df)) {
      return(df)
    }
    if (!"prompt_variant" %in% names(df)) {
      df$prompt_label <- "Non-trajectory prompt"
      return(df)
    }
    df %>%
      mutate(
        prompt_label = case_when(
          prompt_variant == "baseline_notime" ~ "No-time baseline",
          prompt_variant == "baseline" ~ "Date baseline",
          prompt_variant == "tanchored" ~ "Context-anchored prompt",
          TRUE ~ as.character(prompt_variant)
        )
      )
  }

  message("Refreshing covariates-only comparison PNGs from existing CSVs.")
  for (variant in variants) {
    out_dir <- file.path(evaluation_root, paste0("analysis_", variant),
                         "statistical_baselines")
    by_wave_path <- file.path(
      out_dir,
      "covariates_only_nontrajectory_comparison_by_wave.csv"
    )
    overall_path <- file.path(
      out_dir,
      "covariates_only_nontrajectory_comparison_overall.csv"
    )
    trajectory_by_wave_path <- file.path(
      out_dir,
      "statistical_baseline_comparison_by_wave.csv"
    )
    trajectory_overall_path <- file.path(
      out_dir,
      "statistical_baseline_comparison_overall.csv"
    )
    plot_by_wave <- tibble()
    plot_overall <- tibble()

    if (file.exists(by_wave_path)) {
      comparison_by_wave <- read_csv(by_wave_path, show_col_types = FALSE) %>%
        add_prompt_label()
      plot_by_wave <- comparison_by_wave %>%
        select(wave, wave_order, model, prompt_label,
               all_of(names(metric_labels))) %>%
        pivot_longer(cols = all_of(names(metric_labels)),
                     names_to = "metric", values_to = "value") %>%
        mutate(
          wave = factor(wave, levels = unique(wave[order(wave_order)])),
          prompt_label = factor(prompt_label, levels = prompt_levels),
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
          file.path(out_dir,
                    "covariates_only_nontrajectory_comparison_by_wave.png"),
          p_wave, width = 15, height = 9, dpi = 150, bg = "white"
        )
      }
    }

    if (file.exists(overall_path)) {
      comparison_overall <- read_csv(overall_path, show_col_types = FALSE) %>%
        add_prompt_label()
      plot_overall <- comparison_overall %>%
        select(model, prompt_label, all_of(names(metric_labels))) %>%
        pivot_longer(cols = all_of(names(metric_labels)),
                     names_to = "metric", values_to = "value") %>%
        mutate(
          prompt_label = factor(prompt_label, levels = prompt_levels),
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
          file.path(out_dir,
                    "covariates_only_nontrajectory_comparison_overall.png"),
          p_overall, width = 13, height = 7, dpi = 150, bg = "white"
        )
      }
    }

    if (file.exists(trajectory_by_wave_path) && nrow(plot_by_wave) > 0L) {
      trajectory_by_wave <- read_csv(trajectory_by_wave_path,
                                     show_col_types = FALSE) %>%
        select(wave, wave_order, model, accuracy_trajectory) %>%
        distinct()
      trajectory_plot_by_wave <- tidyr::expand_grid(
        trajectory_by_wave,
        prompt_label = prompt_levels
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
          prompt_label = factor(prompt_label, levels = prompt_levels),
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
        prompt_label = prompt_levels
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
          prompt_label = factor(prompt_label, levels = prompt_levels),
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
  }
  invisible(NULL)
}

skip_model_run <- Sys.getenv(
  "SKIP_COVARIATES_ONLY_MODEL_RUN",
  unset = ""
) %in% c("1", "true", "TRUE", "yes", "YES")

if (!skip_model_run) {
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
    outcome_variable <- sub("_original_scale$", "", variant)
    message("covariates-only statistical baseline: ", variant)
    raw <- prepare_raw_statistical_light(csv_path)
    out_dir <- file.path(EVALUATION_OUTPUT_ROOT, paste0("analysis_", variant),
                         "statistical_baselines")
    run_module_covariates_only_statistical_baseline(
      raw,
      outcome_variable,
      out_dir,
      maxit = STAT_BASELINE_MAXIT,
      stability_limits = if (grepl("_original_scale$", variant)) {
        STAT_BASELINE_STABILITY_LIMITS
      } else {
        integer()
      }
    )
    rm(raw)
    invisible(gc())
  }
} else {
  message("Skipping model run; rebuilding covariates-only display table.")
}

write_covariates_only_audit_files(EVALUATION_OUTPUT_ROOT)
write_covariates_only_display_table(EVALUATION_OUTPUT_ROOT)
write_statistical_baseline_display_table(EVALUATION_OUTPUT_ROOT)
write_trajectory_statistical_baseline_plots_from_existing(
  EVALUATION_OUTPUT_ROOT
)
write_covariates_only_plots_from_existing(EVALUATION_OUTPUT_ROOT)
organize_analysis_pngs(EVALUATION_OUTPUT_ROOT)
message("covariates-only statistical baseline generation complete.")
