#!/usr/bin/env Rscript

# Descriptive model-scale robustness summary.
# Run from the code project root:
# Rscript 03_evaluation/scripts/generate_model_scale_robustness_figure.R

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(scales)
})

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "outputs", "evaluation"))) {
  stop("Run this script from the code project root.")
}

table_dir <- file.path(PROJECT_ROOT, "outputs", "evaluation", "tables")
publication_table_dir <- file.path(
  PROJECT_ROOT, "outputs", "evaluation", "manuscript", "tables"
)
figure_dir <- file.path(PROJECT_ROOT, "outputs", "evaluation", "figures")
dir.create(figure_dir, recursive = TRUE, showWarnings = FALSE)

model_meta <- tibble::tribble(
  ~Model, ~family, ~size_b, ~model_order, ~model_label,
  "Mistral-7B", "Mistral", 7, 1, "Mistral\n7B",
  "Qwen2.5-7B", "Qwen", 7, 2, "Qwen\n7B",
  "Qwen2.5-32B", "Qwen", 32, 3, "Qwen\n32B",
  "Llama-3.3-70B", "Llama", 70, 4, "Llama\n70B",
  "Qwen2.5-72B", "Qwen", 72, 5, "Qwen\n72B"
)

clean_task <- function(x) {
  dplyr::recode(
    x,
    "Climate-growth original" = "Climate-growth original scale",
    "Left-right original" = "Left-right original scale",
    .default = x
  )
}

static <- read_csv(
  file.path(
    publication_table_dir, "rq1_ordinal_covariates_only_comparison.csv"
  ),
  show_col_types = FALSE
) %>%
  transmute(
    task = clean_task(.data[["Task"]]),
    Model = .data[["Model"]],
    prompt = .data[["prompt_variant"]],
    nontrajectory_accuracy = .data[["accuracy_prompt"]],
    covariates_only_accuracy = .data[["accuracy_ordinal"]]
  ) %>%
  filter(prompt == "baseline_notime")

trajectory <- read_csv(
  file.path(
    publication_table_dir, "rq2_ordinal_prior_state_comparison.csv"
  ),
  show_col_types = FALSE
) %>%
  transmute(
    task = clean_task(.data[["Task"]]),
    Model = .data[["Model"]],
    trajectory_accuracy = .data[["accuracy_trajectory"]],
    carry_forward_accuracy = .data[["accuracy_cf"]],
    trajectory_minus_carry_forward = .data[["trajectory_minus_cf"]]
  )

dynamic <- read_csv(
  file.path(table_dir, "stable_changing_split_table.csv"),
  show_col_types = FALSE
) %>%
  transmute(
    task = .data[["Task"]],
    Model = .data[["Model"]],
    stable_share = as.numeric(.data[["Stable share"]]),
    stable_accuracy = as.numeric(.data[["Acc. stable"]]),
    changed_accuracy = as.numeric(.data[["Acc. changed"]]),
    false_persistence = as.numeric(.data[["False persistence among changers"]])
  )

model_task <- static %>%
  inner_join(trajectory, by = c("task", "Model")) %>%
  inner_join(dynamic, by = c("task", "Model")) %>%
  inner_join(model_meta, by = "Model") %>%
  arrange(model_order, task)

if (nrow(model_task) != 20L) {
  stop("Expected 20 model-task rows; found ", nrow(model_task), ".")
}

summary_table <- model_task %>%
  group_by(Model, family, size_b, model_order) %>%
  summarise(
    tasks = n(),
    mean_no_time_accuracy = mean(nontrajectory_accuracy),
    mean_covariates_only_accuracy = mean(covariates_only_accuracy),
    mean_no_time_minus_covariates =
      mean(nontrajectory_accuracy - covariates_only_accuracy),
    mean_trajectory_accuracy = mean(trajectory_accuracy),
    mean_trajectory_gain_over_no_time =
      mean(trajectory_accuracy - nontrajectory_accuracy),
    mean_trajectory_minus_carry_forward =
      mean(trajectory_minus_carry_forward),
    mean_changed_accuracy = mean(changed_accuracy),
    mean_false_persistence = mean(false_persistence),
    .groups = "drop"
  ) %>%
  arrange(model_order)

write_csv(
  model_task,
  file.path(figure_dir, "model_scale_robustness_by_task.csv")
)
write_csv(
  summary_table,
  file.path(figure_dir, "model_scale_robustness_summary.csv")
)

write_appendix_robustness_table <- function(data, path) {
  task_levels <- c(
    "Climate-growth grouped",
    "Climate-growth original scale",
    "Left-right grouped",
    "Left-right original scale"
  )

  display <- data %>%
    mutate(task = factor(task, levels = task_levels)) %>%
    arrange(task, model_order) %>%
    transmute(
      Task = as.character(task),
      Model,
      No_time = sprintf("%.3f", nontrajectory_accuracy),
      Cov_only = sprintf("%.3f", covariates_only_accuracy),
      Trajectory = sprintf("%.3f", trajectory_accuracy),
      Traj_CF = sprintf("%+.3f", trajectory_minus_carry_forward),
      Changed = sprintf("%.3f", changed_accuracy),
      False_persistence = sprintf("%.3f", false_persistence)
    )

  rows <- apply(
    display,
    1,
    function(row) paste0(paste(row, collapse = " & "), " \\\\")
  )

  lines <- c(
    "\\begin{table}[!htbp]",
    "\\centering",
    "\\caption{Model-specific robustness details.  Values are reported for each",
    "model-task combination.  Higher values are better except for false persistence.",
    "The trajectory-minus-carry-forward comparison uses lag-available records.}",
    "\\label{tab:model-robustness-details}",
    "\\scriptsize",
    "\\resizebox{\\textwidth}{!}{%",
    "\\begin{tabular}{llrrrrrr}",
    "\\hline",
    "Task & Model & No-time & Cov.-only & Trajectory & Traj.--CF & Changed & False persistence \\\\",
    "\\hline",
    rows,
    "\\hline",
    "\\end{tabular}}",
    "\\normalsize",
    "\\end{table}"
  )

  writeLines(lines, path, useBytes = TRUE)
}

appendix_table_path <- file.path(
  figure_dir,
  "latex_appendix_model_robustness_table.tex"
)
write_appendix_robustness_table(model_task, appendix_table_path)

plot_data <- model_task %>%
  select(task, Model, family, size_b, model_order, model_label,
         nontrajectory_accuracy, trajectory_minus_carry_forward,
         changed_accuracy, false_persistence) %>%
  pivot_longer(
    cols = c(
      nontrajectory_accuracy,
      trajectory_minus_carry_forward,
      changed_accuracy,
      false_persistence
    ),
    names_to = "metric",
    values_to = "value"
  ) %>%
  mutate(
    task = factor(
      task,
      levels = c(
        "Climate-growth grouped",
        "Climate-growth original scale",
        "Left-right grouped",
        "Left-right original scale"
      )
    ),
    metric = factor(
      metric,
      levels = c(
        "nontrajectory_accuracy",
        "trajectory_minus_carry_forward",
        "changed_accuracy",
        "false_persistence"
      ),
      labels = c(
        "A. No-time accuracy",
        "B. Trajectory minus carry-forward accuracy",
        "C. Trajectory accuracy among changers",
        "D. False persistence among changers\n(higher = worse)"
      )
    )
  )

baseline_lines <- model_task %>%
  distinct(task, covariates_only_accuracy) %>%
  mutate(
    task = factor(
      task,
      levels = c(
        "Climate-growth grouped",
        "Climate-growth original scale",
        "Left-right grouped",
        "Left-right original scale"
      )
    ),
    metric = factor(
      "A. No-time accuracy",
      levels = levels(plot_data$metric)
    )
  )

zero_lines <- tibble::tibble(
  metric = factor(
    "B. Trajectory minus carry-forward accuracy",
    levels = levels(plot_data$metric)
  ),
  yintercept = 0
)

family_colours <- c(Mistral = "#4E79A7", Qwen = "#59A14F", Llama = "#E15759")

p <- ggplot(
  plot_data,
  aes(x = model_order, y = value, colour = family, shape = family)
) +
  geom_hline(yintercept = 0, colour = "grey90", linewidth = 0.3) +
  geom_hline(
    data = baseline_lines,
    aes(yintercept = covariates_only_accuracy),
    inherit.aes = FALSE,
    colour = "black",
    linetype = "dashed",
    linewidth = 0.45
  ) +
  geom_hline(
    data = zero_lines,
    aes(yintercept = yintercept),
    inherit.aes = FALSE,
    colour = "black",
    linetype = "dashed",
    linewidth = 0.45
  ) +
  geom_point(size = 3.1, stroke = 0.8) +
  facet_grid(metric ~ task, scales = "free_y") +
  scale_colour_manual(values = family_colours) +
  scale_shape_manual(values = c(Mistral = 16, Qwen = 17, Llama = 15)) +
  scale_x_continuous(
    breaks = 1:5,
    labels = c("Mistral\n7B", "Qwen\n7B", "Qwen\n32B", "Llama\n70B", "Qwen\n72B"),
    limits = c(0.6, 5.4)
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    expand = expansion(mult = c(0.08, 0.12))
  ) +
  labs(
    title = "Static--dynamic patterns across model scales",
    subtitle = "Descriptive robustness check across five model configurations and four task representations",
    x = "Model configuration (ordered by nominal parameter count)",
    y = NULL,
    colour = "Model family",
    shape = "Model family",
    caption = paste(
      "Panel A: dashed lines mark the matched covariates-only baseline.  ",
      "Panel B: the dashed line marks zero.  ",
      "Model-family, quantization, and instruction-tuning differences make this a descriptive robustness check."
    )
  ) +
  theme_minimal(base_size = 10.5) +
  theme(
    legend.position = "bottom",
    panel.grid.major.x = element_blank(),
    panel.spacing = grid::unit(0.75, "lines"),
    strip.text.x = element_text(face = "bold", size = 9),
    strip.text.y = element_text(face = "bold", size = 9),
    plot.title = element_text(face = "bold"),
    plot.caption = element_text(hjust = 0, size = 8, margin = margin(t = 7))
  )

png_path <- file.path(figure_dir, "model_scale_robustness.png")
pdf_path <- file.path(figure_dir, "model_scale_robustness.pdf")
ggsave(png_path, p, width = 16, height = 12.2, dpi = 200, bg = "white")
ggsave(pdf_path, p, width = 16, height = 12.2, bg = "white")

paper_path <- file.path(
  PROJECT_ROOT, "outputs", "evaluation", "figures",
  "Figure_5_model_scale_robustness.png"
)
if (dir.exists(dirname(paper_path))) {
  file.copy(png_path, paper_path, overwrite = TRUE)
}

message("Wrote: ", png_path)
message("Wrote: ", pdf_path)
if (file.exists(paper_path)) message("Wrote: ", paper_path)
message("Wrote: ", file.path(figure_dir, "model_scale_robustness_by_task.csv"))
message("Wrote: ", file.path(figure_dir, "model_scale_robustness_summary.csv"))
