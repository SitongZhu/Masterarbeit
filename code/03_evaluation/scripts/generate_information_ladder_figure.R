#!/usr/bin/env Rscript
# Generate the information ladder accuracy figure by task.
# This script uses existing summary CSVs and does not rerun any model fitting.

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(ggplot2)
  library(scales)
})

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "data"))) {
  stop("Run this script from the code project root.")
}

EVALUATION_OUTPUT_ROOT <- Sys.getenv(
  "EVALUATION_OUTPUT_ROOT",
  unset = file.path(PROJECT_ROOT, "outputs", "evaluation")
)
EVALUATION_OUTPUT_ROOT <- normalizePath(
  EVALUATION_OUTPUT_ROOT,
  winslash = "/",
  mustWork = TRUE
)

TABLE_DIR <- file.path(EVALUATION_OUTPUT_ROOT, "tables")
PUBLICATION_TABLE_DIR <- file.path(
  EVALUATION_OUTPUT_ROOT, "manuscript", "tables"
)
FIGURE_DIR <- file.path(EVALUATION_OUTPUT_ROOT, "figures")
ORGANIZED_PNG_DIR <- file.path(
  EVALUATION_OUTPUT_ROOT,
  "organized_analysis_pngs",
  "statistical_baselines"
)
ORGANIZED_MAIN_DIR <- file.path(
  EVALUATION_OUTPUT_ROOT,
  "organized_analysis_pngs",
  "main_text_figures"
)
dir.create(FIGURE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(ORGANIZED_PNG_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(ORGANIZED_MAIN_DIR, recursive = TRUE, showWarnings = FALSE)

covariates_path <- file.path(
  PUBLICATION_TABLE_DIR,
  "rq1_ordinal_covariates_only_comparison.csv"
)
prior_state_path <- file.path(
  PUBLICATION_TABLE_DIR,
  "rq2_ordinal_prior_state_comparison.csv"
)

if (!file.exists(covariates_path)) {
  stop("Missing covariates-only comparison table: ", covariates_path)
}
if (!file.exists(prior_state_path)) {
  stop("Missing prior-state baseline comparison table: ", prior_state_path)
}

task_levels <- c(
  "Climate-growth grouped",
  "Climate-growth original scale",
  "Left-right grouped",
  "Left-right original scale"
)

standardise_task <- function(x) {
  recode(
    x,
    "Climate-growth original" = "Climate-growth original scale",
    "Left-right original" = "Left-right original scale",
    .default = x
  )
}

condition_levels <- c(
  "Baseline:\nCovariates only",
  "LLM:\nBest no-time",
  "Baseline:\nPrior-wave modal",
  "Baseline:\nCarry-forward",
  "Baseline:\nLag + covariates",
  "LLM:\nBest trajectory"
)

condition_colours <- c(
  "Baseline:\nCovariates only" = "#59A14F",
  "LLM:\nBest no-time" = "#4E79A7",
  "Baseline:\nPrior-wave modal" = "#7F7F7F",
  "Baseline:\nCarry-forward" = "#F28E2B",
  "Baseline:\nLag + covariates" = "#B07AA1",
  "LLM:\nBest trajectory" = "#76B7B2"
)

condition_shapes <- c(
  "Baseline:\nCovariates only" = 22,
  "LLM:\nBest no-time" = 24,
  "Baseline:\nPrior-wave modal" = 22,
  "Baseline:\nCarry-forward" = 22,
  "Baseline:\nLag + covariates" = 22,
  "LLM:\nBest trajectory" = 24
)

covariates <- read_csv(covariates_path, show_col_types = FALSE) %>%
  mutate(Task = standardise_task(Task))

prior_state <- read_csv(prior_state_path, show_col_types = FALSE) %>%
  mutate(Task = standardise_task(Task))

model_tiebreaker <- c(
  "Mistral-7B", "Qwen2.5-7B", "Qwen2.5-32B",
  "Llama-3.3-70B", "Qwen2.5-72B"
)

# Select the displayed LLM first, then take every benchmark from that exact
# model-specific comparison row.  This keeps each block on identical retained
# respondent-wave records and avoids independently maximizing baseline values.
static_selection <- covariates %>%
  filter(prompt_variant == "baseline_notime") %>%
  mutate(model_tiebreak = match(Model, model_tiebreaker)) %>%
  arrange(Task, desc(accuracy_prompt), desc(n_total), model_tiebreak) %>%
  group_by(Task) %>%
  slice_head(n = 1L) %>%
  ungroup() %>%
  transmute(
    Task,
    covariates_only = accuracy_ordinal,
    best_nontrajectory = accuracy_prompt,
    best_nontrajectory_model = Model,
    best_nontrajectory_prompt = prompt_label,
    no_prior_state_n = n_total
  )

prior_state_selection <- prior_state %>%
  mutate(model_tiebreak = match(Model, model_tiebreaker)) %>%
  arrange(Task, desc(accuracy_trajectory), desc(n_total), model_tiebreak) %>%
  group_by(Task) %>%
  slice_head(n = 1L) %>%
  ungroup() %>%
  transmute(
    Task,
    modal = accuracy_majority,
    carry_forward = accuracy_cf,
    lag_covariates = accuracy_ordinal,
    best_trajectory = accuracy_trajectory,
    best_trajectory_model = Model,
    prior_state_n = n_total
  )

selection_details <- static_selection %>%
  left_join(prior_state_selection, by = "Task") %>%
  mutate(Task = factor(Task, levels = task_levels)) %>%
  arrange(Task)
if (nrow(selection_details) != length(task_levels) ||
    any(!complete.cases(selection_details))) {
  stop("Information-ladder selection must contain one complete row per task.")
}

ladder_data <- selection_details %>%
  select(Task, modal, covariates_only, best_nontrajectory,
         carry_forward, lag_covariates, best_trajectory) %>%
  pivot_longer(
    cols = -Task,
    names_to = "condition_key",
    values_to = "accuracy"
  ) %>%
  mutate(
    condition = recode(
      condition_key,
      modal = "Baseline:\nPrior-wave modal",
      covariates_only = "Baseline:\nCovariates only",
      best_nontrajectory = "LLM:\nBest no-time",
      carry_forward = "Baseline:\nCarry-forward",
      lag_covariates = "Baseline:\nLag + covariates",
      best_trajectory = "LLM:\nBest trajectory"
    ),
    condition = factor(condition, levels = condition_levels),
    condition_order = as.integer(condition),
    information_block = if_else(
      condition_order <= 2L,
      "No prior-state information",
      "Prior-state information"
    )
  ) %>%
  arrange(Task, condition_order)

write_csv(
  ladder_data,
  file.path(FIGURE_DIR, "information_ladder_data.csv")
)
write_csv(
  selection_details,
  file.path(FIGURE_DIR, "information_ladder_selection_details.csv")
)

information_ladder <- ggplot(
  ladder_data,
  aes(x = condition, y = accuracy)
) +
  geom_vline(xintercept = 2.5, linetype = "dashed",
             linewidth = 0.3, colour = "grey70") +
  geom_text(
    data = tibble(
      condition = factor(c("Baseline:\nCovariates only",
                           "Baseline:\nCarry-forward"),
                         levels = condition_levels),
      accuracy = c(0.96, 0.96),
      label = c("No prior-state\ninformation",
                "Prior-state\ninformation available")
    ),
    aes(x = condition, y = accuracy, label = label),
    inherit.aes = FALSE,
    size = 2.8,
    colour = "grey35",
    fontface = "bold",
    lineheight = 0.9
  ) +
  geom_line(aes(group = interaction(Task, information_block)),
            colour = "grey45", linewidth = 0.55) +
  geom_point(aes(fill = condition, shape = condition),
             size = 3.2, stroke = 0.55, colour = "grey20") +
  facet_wrap(~ Task, nrow = 2) +
  scale_x_discrete(limits = condition_levels, drop = FALSE) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    breaks = seq(0, 1, by = 0.25),
    limits = c(0, 1),
    expand = expansion(mult = c(0.02, 0.04))
  ) +
  scale_fill_manual(values = condition_colours, drop = FALSE) +
  scale_shape_manual(values = condition_shapes, drop = FALSE) +
  labs(
    title = "Accuracy along the information ladder",
    subtitle = "Row-matched statistical and persistence baselines absorb the apparent LLM trajectory advantage.",
    x = NULL,
    y = NULL
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(size = 15),
    plot.subtitle = element_text(size = 10.5, colour = "black"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(size = 10.5),
    axis.text.x = element_text(
      colour = "grey30", size = 9.2, lineheight = 0.9,
      margin = margin(t = 5)
    ),
    axis.text.y = element_text(colour = "grey30"),
    legend.position = "none",
    plot.margin = margin(10, 14, 10, 10)
  )

png_path <- file.path(FIGURE_DIR, "information_ladder.png")
pdf_path <- file.path(FIGURE_DIR, "information_ladder.pdf")
svg_path <- file.path(FIGURE_DIR, "information_ladder.svg")
organized_png_path <- file.path(ORGANIZED_PNG_DIR, "information_ladder.png")

ggsave(png_path, information_ladder, width = 12.5, height = 6.9, dpi = 300,
       bg = "white")
ggsave(pdf_path, information_ladder, width = 12.5, height = 6.9,
       device = cairo_pdf, bg = "white")
ggsave(svg_path, information_ladder, width = 12.5, height = 6.9,
       device = "svg", bg = "white")
file.copy(png_path, organized_png_path, overwrite = TRUE)
file.copy(
  png_path,
  file.path(ORGANIZED_MAIN_DIR, "information_ladder.png"),
  overwrite = TRUE
)

message("Wrote: ", png_path)
message("Wrote: ", organized_png_path)
message("Wrote: ", pdf_path)
message("Wrote: ", svg_path)
message("Wrote: ", file.path(FIGURE_DIR, "information_ladder_data.csv"))
message("Wrote: ",
        file.path(FIGURE_DIR, "information_ladder_selection_details.csv"))
