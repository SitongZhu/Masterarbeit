#!/usr/bin/env Rscript
# analyse_1500_dynamic_chains.R
# Diagnostic analysis for clustered left-right trajectories.
# It checks whether negative dynamic correlations may arise because LLM
# predictions lag, copy previous-wave states, or reverse observed changes.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(readr)
  library(stringr)
  library(tidyr)
  library(scales)
})

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
CSV_FILE <- file.path(ANALYSIS_INPUT_DIR, "analyse_1500.csv")
OUT_DIR <- file.path(EVALUATION_OUTPUT_ROOT, "analysis_1500",
                     "dynamic_chain_diagnostics")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

if (!file.exists(CSV_FILE)) {
  stop("Cannot find ", CSV_FILE)
}

clean_text <- function(x) {
  x <- as.character(x)
  x <- str_squish(x)
  x[x == ""] <- NA_character_
  x
}

parse_wave_order <- function(wave) {
  suppressWarnings(as.integer(str_extract(wave, "[0-9]+")))
}

norm_cat <- function(x) {
  x <- str_to_lower(clean_text(x))
  case_when(
    str_detect(x, "\\blinks\\b") ~ "L",
    str_detect(x, "\\bneutral\\b") ~ "N",
    str_detect(x, "\\brechts\\b") ~ "R",
    TRUE ~ NA_character_
  )
}

cat_to_num <- function(x) {
  case_when(
    x == "L" ~ -1,
    x == "N" ~ 0,
    x == "R" ~ 1,
    TRUE ~ NA_real_
  )
}

message("Loading ", CSV_FILE, " ...")
raw <- read_csv(CSV_FILE, show_col_types = FALSE)

df <- raw %>%
  mutate(
    wave = clean_text(if ("wave_id_from_list" %in% names(.)) wave_id_from_list else wave),
    wave_order = parse_wave_order(wave),
    model = clean_text(
      if ("llm_model" %in% names(.)) {
        coalesce(llm_model, if ("model" %in% names(.)) model else NA_character_)
      } else if ("model" %in% names(.)) {
        model
      } else {
        NA_character_
      }
    ),
    prompt_variant = clean_text(prompt_variant),
    lfdn = clean_text(lfdn),
    human_cat = norm_cat(label),
    llm_cat = norm_cat(predict),
    human_num = cat_to_num(human_cat),
    llm_num = cat_to_num(llm_cat)
  ) %>%
  filter(!is.na(lfdn), !is.na(model), !is.na(prompt_variant),
         !is.na(wave_order), !is.na(human_cat), !is.na(llm_cat))

message("Rows after parsing: ", nrow(df))

# ---------------------------------------------------------------------------
# 1. Full respondent-level chains
# ---------------------------------------------------------------------------

chain_df <- df %>%
  arrange(lfdn, model, prompt_variant, wave_order) %>%
  group_by(lfdn, model, prompt_variant) %>%
  summarise(
    n_waves = n_distinct(wave),
    wave_chain = paste(wave[order(wave_order)], collapse = "-"),
    human_chain = paste(human_cat[order(wave_order)], collapse = ""),
    llm_chain = paste(llm_cat[order(wave_order)], collapse = ""),
    human_num_chain = paste(human_num[order(wave_order)], collapse = ","),
    llm_num_chain = paste(llm_num[order(wave_order)], collapse = ","),
    exact_chain_match = human_chain == llm_chain,
    .groups = "drop"
  )

write_csv(chain_df, file.path(OUT_DIR, "respondent_level_chains.csv"))

chain_summary <- chain_df %>%
  group_by(model, prompt_variant, n_waves, human_chain, llm_chain) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(model, prompt_variant, n_waves, human_chain) %>%
  mutate(
    human_chain_total = sum(n),
    predicted_share_given_human_chain = n / human_chain_total,
    human_chain_rank = dense_rank(desc(human_chain_total))
  ) %>%
  ungroup() %>%
  arrange(model, prompt_variant, n_waves, human_chain_rank,
          desc(predicted_share_given_human_chain), llm_chain)

write_csv(chain_summary, file.path(OUT_DIR, "human_chain_to_llm_chain_distribution.csv"))

top_human_chains <- chain_summary %>%
  filter(human_chain_rank <= 25) %>%
  group_by(model, prompt_variant, n_waves, human_chain) %>%
  slice_max(predicted_share_given_human_chain, n = 5, with_ties = FALSE) %>%
  ungroup()

write_csv(top_human_chains,
          file.path(OUT_DIR, "top_human_chains_with_common_llm_chains.csv"))

chain_accuracy <- chain_df %>%
  group_by(model, prompt_variant, n_waves) %>%
  summarise(
    n_chains = n(),
    exact_chain_match_rate = mean(exact_chain_match),
    .groups = "drop"
  ) %>%
  arrange(prompt_variant, model, n_waves)

write_csv(chain_accuracy, file.path(OUT_DIR, "chain_match_summary.csv"))

# ---------------------------------------------------------------------------
# 2. Transition-level diagnostics
# ---------------------------------------------------------------------------

transitions <- df %>%
  arrange(lfdn, model, prompt_variant, wave_order) %>%
  group_by(lfdn, model, prompt_variant) %>%
  mutate(
    prev_wave = lag(wave),
    prev_wave_order = lag(wave_order),
    human_prev = lag(human_cat),
    human_curr = human_cat,
    llm_prev = lag(llm_cat),
    llm_curr = llm_cat,
    human_prev_num = lag(human_num),
    human_curr_num = human_num,
    llm_prev_num = lag(llm_num),
    llm_curr_num = llm_num
  ) %>%
  ungroup() %>%
  filter(!is.na(prev_wave_order)) %>%
  mutate(
    transition = paste0(prev_wave, "_to_", wave),
    human_transition = paste0(human_prev, "->", human_curr),
    llm_transition = paste0(llm_prev, "->", llm_curr),
    delta_H = human_curr_num - human_prev_num,
    delta_L = llm_curr_num - llm_prev_num,
    human_changed = delta_H != 0,
    llm_changed = delta_L != 0,
    same_direction = human_changed & llm_changed & sign(delta_H) == sign(delta_L),
    opposite_direction = human_changed & llm_changed & sign(delta_H) == -sign(delta_L),
    llm_no_change = delta_L == 0,
    llm_copies_previous_human = llm_curr == human_prev,
    llm_copies_current_human = llm_curr == human_curr,
    llm_copies_previous_llm = llm_curr == llm_prev,
    reversed_pair = llm_prev == human_curr & llm_curr == human_prev
  )

write_csv(transitions, file.path(OUT_DIR, "transition_level_diagnostics.csv"))

transition_summary <- transitions %>%
  group_by(model, prompt_variant, transition) %>%
  summarise(
    n = n(),
    n_human_changed = sum(human_changed, na.rm = TRUE),
    n_llm_changed_when_human_changed =
      sum(human_changed & llm_changed, na.rm = TRUE),
    n_same_direction = sum(same_direction, na.rm = TRUE),
    n_opposite_direction = sum(opposite_direction, na.rm = TRUE),
    n_llm_no_change_when_human_changed =
      sum(human_changed & llm_no_change, na.rm = TRUE),
    ccr = n_llm_changed_when_human_changed / pmax(n_human_changed, 1),
    conditional_directional_accuracy =
      n_same_direction / pmax(n_llm_changed_when_human_changed, 1),
    directional_change_capture_rate =
      n_same_direction / pmax(n_human_changed, 1),
    opposite_direction_rate =
      n_opposite_direction / pmax(n_llm_changed_when_human_changed, 1),
    llm_no_change_rate_when_human_changed =
      n_llm_no_change_when_human_changed / pmax(n_human_changed, 1),
    llm_copy_previous_human_rate =
      mean(llm_copies_previous_human, na.rm = TRUE),
    llm_copy_current_human_rate =
      mean(llm_copies_current_human, na.rm = TRUE),
    llm_copy_previous_llm_rate =
      mean(llm_copies_previous_llm, na.rm = TRUE),
    reversed_pair_rate_when_human_changed =
      sum(human_changed & reversed_pair, na.rm = TRUE) /
      pmax(n_human_changed, 1),
    .groups = "drop"
  ) %>%
  arrange(model, prompt_variant, transition)

write_csv(transition_summary, file.path(OUT_DIR, "transition_summary_by_wave.csv"))

transition_overall <- transitions %>%
  group_by(model, prompt_variant) %>%
  summarise(
    n = n(),
    n_human_changed = sum(human_changed, na.rm = TRUE),
    n_llm_changed_when_human_changed =
      sum(human_changed & llm_changed, na.rm = TRUE),
    n_same_direction = sum(same_direction, na.rm = TRUE),
    n_opposite_direction = sum(opposite_direction, na.rm = TRUE),
    n_llm_no_change_when_human_changed =
      sum(human_changed & llm_no_change, na.rm = TRUE),
    ccr = n_llm_changed_when_human_changed / pmax(n_human_changed, 1),
    conditional_directional_accuracy =
      n_same_direction / pmax(n_llm_changed_when_human_changed, 1),
    directional_change_capture_rate =
      n_same_direction / pmax(n_human_changed, 1),
    opposite_direction_rate =
      n_opposite_direction / pmax(n_llm_changed_when_human_changed, 1),
    llm_no_change_rate_when_human_changed =
      n_llm_no_change_when_human_changed / pmax(n_human_changed, 1),
    llm_copy_previous_human_rate =
      mean(llm_copies_previous_human, na.rm = TRUE),
    llm_copy_current_human_rate =
      mean(llm_copies_current_human, na.rm = TRUE),
    llm_copy_previous_llm_rate =
      mean(llm_copies_previous_llm, na.rm = TRUE),
    reversed_pair_rate_when_human_changed =
      sum(human_changed & reversed_pair, na.rm = TRUE) /
      pmax(n_human_changed, 1),
    .groups = "drop"
  ) %>%
  arrange(prompt_variant, model)

write_csv(transition_overall, file.path(OUT_DIR, "transition_summary_overall.csv"))

transition_pattern_counts <- transitions %>%
  group_by(model, prompt_variant, transition,
           human_transition, llm_transition) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(model, prompt_variant, transition, human_transition) %>%
  mutate(
    human_transition_total = sum(n),
    llm_share_given_human_transition = n / human_transition_total
  ) %>%
  ungroup() %>%
  arrange(model, prompt_variant, transition, human_transition,
          desc(llm_share_given_human_transition))

write_csv(transition_pattern_counts,
          file.path(OUT_DIR, "human_transition_to_llm_transition_distribution.csv"))

top_transition_patterns <- transition_pattern_counts %>%
  group_by(model, prompt_variant, transition, human_transition) %>%
  slice_max(llm_share_given_human_transition, n = 5, with_ties = FALSE) %>%
  ungroup() %>%
  arrange(model, prompt_variant, transition, human_transition,
          desc(llm_share_given_human_transition))

write_csv(top_transition_patterns,
          file.path(OUT_DIR, "top_human_transition_to_llm_transition_patterns.csv"))

# ---------------------------------------------------------------------------
# 3. Compact tables for trajectory prompt, because dynamic evaluation mainly
#    concerns the trajectory condition.
# ---------------------------------------------------------------------------

trajectory_transition_summary <- transition_overall %>%
  filter(prompt_variant == "trajectory")
write_csv(trajectory_transition_summary,
          file.path(OUT_DIR, "trajectory_transition_summary_overall.csv"))

trajectory_by_wave <- transition_summary %>%
  filter(prompt_variant == "trajectory")
write_csv(trajectory_by_wave,
          file.path(OUT_DIR, "trajectory_transition_summary_by_wave.csv"))

trajectory_top_patterns <- top_transition_patterns %>%
  filter(prompt_variant == "trajectory")
write_csv(trajectory_top_patterns,
          file.path(OUT_DIR, "trajectory_top_transition_patterns.csv"))

message("Wrote diagnostics to: ", OUT_DIR)
message("Key files:")
message("  - trajectory_transition_summary_overall.csv")
message("  - trajectory_transition_summary_by_wave.csv")
message("  - trajectory_top_transition_patterns.csv")
message("  - top_human_chains_with_common_llm_chains.csv")

# ---------------------------------------------------------------------------
# 4. Visualizations
# ---------------------------------------------------------------------------

plot_dir <- file.path(OUT_DIR, "plots")
dir.create(plot_dir, showWarnings = FALSE, recursive = TRUE)

model_labels <- c(
  "Mistral-7B-Instruct-v0_3" = "Mistral-7B",
  "Qwen2_5-32B-Instruct" = "Qwen2.5-32B",
  "Qwen2_5-7B-Instruct-GPTQ-Int4" = "Qwen2.5-7B",
  "Qwen2_5-72B-Instruct" = "Qwen2.5-72B",
  "Llama-3_3-70B-Instruct" = "Llama-3.3-70B"
)

model_cols <- c(
  "Mistral-7B-Instruct-v0_3" = "#4C78A8",
  "Qwen2_5-32B-Instruct" = "#F58518",
  "Qwen2_5-7B-Instruct-GPTQ-Int4" = "#54A24B",
  "Qwen2_5-72B-Instruct" = "#B279A2",
  "Llama-3_3-70B-Instruct" = "#E45756"
)

heatmap_fill_colours <- c("#F7FCF5", "#D9F0D3", "#A1D99B",
                          "#41AB5D", "#238B45")

theme_chain <- function(base_size = 11) {
  theme_minimal(base_size = base_size) +
    theme(
      panel.grid.minor = element_blank(),
      plot.title = element_text(face = "bold"),
      plot.subtitle = element_text(colour = "grey35"),
      legend.position = "bottom"
    )
}

# 4.1 Overall dynamic mechanism bars.
overall_plot_df <- trajectory_transition_summary %>%
  select(model, ccr, conditional_directional_accuracy,
         directional_change_capture_rate, opposite_direction_rate,
         llm_no_change_rate_when_human_changed,
         llm_copy_previous_human_rate,
         reversed_pair_rate_when_human_changed) %>%
  pivot_longer(
    cols = -model,
    names_to = "metric",
    values_to = "value"
  ) %>%
  mutate(
    metric = recode(
      metric,
      ccr = "Change capture",
      conditional_directional_accuracy =
        "Correct direction\namong captured changes",
      directional_change_capture_rate =
        "Correct direction\namong all human changes",
      opposite_direction_rate = "Opposite direction\namong captured changes",
      llm_no_change_rate_when_human_changed =
        "LLM no-change\nwhen human changes",
      llm_copy_previous_human_rate = "Copies previous\nhuman state",
      reversed_pair_rate_when_human_changed =
        "Reversed pair\nwhen human changes"
    ),
    metric = factor(metric, levels = c(
      "Change capture",
      "Correct direction\namong captured changes",
      "Correct direction\namong all human changes",
      "Opposite direction\namong captured changes",
      "LLM no-change\nwhen human changes",
      "Copies previous\nhuman state",
      "Reversed pair\nwhen human changes"
    )),
    model_short = recode(model, !!!model_labels)
  )

p_overall <- ggplot(overall_plot_df,
                    aes(x = metric, y = value, fill = model)) +
  geom_col(position = position_dodge(width = 0.76), width = 0.68) +
  geom_text(
    aes(label = percent(value, accuracy = 1)),
    position = position_dodge(width = 0.76),
    vjust = -0.25,
    size = 3
  ) +
  scale_fill_manual(values = model_cols, labels = model_labels) +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1.08)) +
  labs(
    title = "Dynamic Diagnostics for Clustered Left-Right Trajectories",
    subtitle = "Trajectory prompt; metrics computed on respondent-wave transitions",
    x = NULL,
    y = "Rate",
    fill = "Model"
  ) +
  theme_chain() +
  theme(axis.text.x = element_text(size = 9))

ggsave(file.path(plot_dir, "trajectory_dynamic_mechanism_bars.png"),
       p_overall, width = 13.5, height = 7.2, dpi = 180)

# 4.2 Conditional and unconditional direction metrics by transition.
wave_plot_df <- trajectory_by_wave %>%
  mutate(
    transition = factor(transition, levels = unique(transition)),
    model_short = recode(model, !!!model_labels)
  ) %>%
  select(model, transition, conditional_directional_accuracy,
         directional_change_capture_rate, opposite_direction_rate,
         llm_no_change_rate_when_human_changed) %>%
  pivot_longer(
    cols = c(conditional_directional_accuracy,
             directional_change_capture_rate, opposite_direction_rate,
             llm_no_change_rate_when_human_changed),
    names_to = "metric",
    values_to = "value"
  ) %>%
  mutate(
    metric = recode(
      metric,
      conditional_directional_accuracy =
        "Correct direction among captured changes",
      directional_change_capture_rate =
        "Correct direction among all human changes",
      opposite_direction_rate = "Opposite direction",
      llm_no_change_rate_when_human_changed = "No LLM change"
    ),
    metric = factor(metric, levels = c(
      "Correct direction among captured changes",
      "Correct direction among all human changes",
      "Opposite direction",
      "No LLM change"
    ))
  )

p_wave <- ggplot(wave_plot_df,
                 aes(x = transition, y = value, colour = model,
                     group = model)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2) +
  facet_wrap(~ metric, ncol = 1) +
  scale_colour_manual(values = model_cols, labels = model_labels) +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
  labs(
    title = "Transition-Level Direction Diagnostics",
    subtitle = "When human responses change, LLMs often predict no change or the opposite direction",
    x = "Wave transition",
    y = "Rate",
    colour = "Model"
  ) +
  theme_chain() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1))

ggsave(file.path(plot_dir, "trajectory_direction_by_wave.png"),
       p_wave, width = 12.5, height = 9.5, dpi = 180)

# 4.3 Heatmap: human transitions to LLM transitions.
heatmap_df <- transitions %>%
  filter(prompt_variant == "trajectory",
         human_changed,
         human_transition %in% c("L->N", "N->L", "N->R", "R->N")) %>%
  count(model, human_transition, llm_transition, name = "n") %>%
  group_by(model, human_transition) %>%
  mutate(share = n / sum(n)) %>%
  ungroup() %>%
  mutate(
    human_transition = factor(human_transition,
                              levels = c("L->N", "N->L", "N->R", "R->N")),
    llm_transition = factor(llm_transition,
                            levels = c("L->L", "L->N", "L->R",
                                       "N->L", "N->N", "N->R",
                                       "R->L", "R->N", "R->R")),
    model_short = recode(model, !!!model_labels)
  )

p_heat <- ggplot(heatmap_df,
                 aes(x = llm_transition, y = human_transition, fill = share)) +
  geom_tile(colour = "white", linewidth = 0.4) +
  geom_text(aes(label = percent(share, accuracy = 1)),
            size = 3, colour = "#111827") +
  facet_wrap(~ model_short, nrow = 1) +
  scale_fill_gradientn(
    colours = heatmap_fill_colours,
    labels = percent_format(),
    limits = c(0, max(heatmap_df$share, na.rm = TRUE))
  ) +
  labs(
    title = "How Human Changes Are Translated Into LLM Transitions",
    subtitle = "Rows condition on common human changes; cells show LLM transition shares",
    x = "LLM-predicted transition",
    y = "Observed human transition",
    fill = "Share"
  ) +
  theme_chain() +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        panel.grid = element_blank())

ggsave(file.path(plot_dir, "trajectory_transition_heatmap.png"),
       p_heat, width = 14, height = 5.8, dpi = 180)

# 4.4 Chain match deteriorates as the observed sequence gets longer.
chain_plot_df <- chain_accuracy %>%
  filter(prompt_variant == "trajectory") %>%
  mutate(model_short = recode(model, !!!model_labels))

p_chain <- ggplot(chain_plot_df,
                  aes(x = n_waves, y = exact_chain_match_rate,
                      colour = model, group = model)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.3) +
  scale_colour_manual(values = model_cols, labels = model_labels) +
  scale_x_continuous(breaks = sort(unique(chain_plot_df$n_waves))) +
  scale_y_continuous(labels = percent_format(), limits = c(0, 1)) +
  labs(
    title = "Exact Chain Match Declines With Sequence Length",
    subtitle = "Clustered left-right task under trajectory prompting",
    x = "Number of observed waves in respondent chain",
    y = "Exact chain match rate",
    colour = "Model"
  ) +
  theme_chain()

ggsave(file.path(plot_dir, "trajectory_chain_match_by_length.png"),
       p_chain, width = 9.5, height = 6, dpi = 180)

message("Plots written to: ", plot_dir)
