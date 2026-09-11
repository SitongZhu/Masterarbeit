#!/usr/bin/env Rscript
# Generate compact main-text figures for the Results chapter.
#
# Outputs:
# - outputs/evaluation/figures/stable_changing_split.png
# - outputs/evaluation/figures/anchored_change_heatmap_left_right_grouped.png
#
# The script uses existing evaluation tables and analysis inputs. It does not
# rerun model fitting.

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

ANALYSIS_INPUT_DIR <- Sys.getenv(
  "ANALYSIS_INPUT_DIR",
  unset = file.path(PROJECT_ROOT, "data", "analysis_inputs")
)
ANALYSIS_INPUT_DIR <- normalizePath(
  ANALYSIS_INPUT_DIR,
  winslash = "/",
  mustWork = TRUE
)

TABLE_DIR <- file.path(EVALUATION_OUTPUT_ROOT, "tables")
FIGURE_DIR <- file.path(EVALUATION_OUTPUT_ROOT, "figures")
ORGANIZED_MAIN_DIR <- file.path(
  EVALUATION_OUTPUT_ROOT,
  "organized_analysis_pngs",
  "main_text_figures"
)
dir.create(FIGURE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(ORGANIZED_MAIN_DIR, recursive = TRUE, showWarnings = FALSE)

task_levels <- c(
  "Climate-growth grouped",
  "Climate-growth original scale",
  "Left-right grouped",
  "Left-right original scale"
)

task_labels <- c(
  "Climate-growth\ngrouped",
  "Climate-growth\noriginal scale",
  "Left-right\ngrouped",
  "Left-right\noriginal scale"
)
names(task_labels) <- task_levels

model_levels <- c(
  "Mistral-7B", "Qwen2.5-32B", "Qwen2.5-7B", "Qwen2.5-72B",
  "Llama-3.3-70B"
)
model_colours <- c(
  "Mistral-7B" = "#4C78A8",
  "Qwen2.5-32B" = "#59A14F",
  "Qwen2.5-7B" = "#F28E2B",
  "Qwen2.5-72B" = "#B279A2",
  "Llama-3.3-70B" = "#E45756"
)

heatmap_fill_colours <- c("#F7FCF5", "#D9F0D3", "#A1D99B",
                          "#41AB5D", "#238B45")

prompt_levels <- c("baseline_notime", "baseline", "tanchored", "trajectory")
prompt_labels <- c(
  baseline_notime = "No-time",
  baseline = "Date",
  tanchored = "Context-anchored",
  trajectory = "Trajectory"
)

# Aggregate validity for the main-text progression.
variant_tasks <- tibble::tribble(
  ~variant, ~Task,
  "1290", "Climate-growth grouped",
  "1290_original_scale", "Climate-growth original scale",
  "1500", "Left-right grouped",
  "1500_original_scale", "Left-right original scale"
)

aggregate_distance <- bind_rows(lapply(seq_len(nrow(variant_tasks)), function(i) {
  path <- file.path(
    EVALUATION_OUTPUT_ROOT,
    paste0("analysis_", variant_tasks$variant[[i]]),
    "aggregate_prediction",
    "aggregate_distribution_distance_overall.csv"
  )
  if (!file.exists(path)) return(tibble())
  read_csv(path, show_col_types = FALSE) %>%
    select(model, prompt_variant, total_variation_distance) %>%
    mutate(Task = variant_tasks$Task[[i]], .before = 1)
}))

if (nrow(aggregate_distance) > 0L) {
  aggregate_distance_plot_df <- aggregate_distance %>%
    mutate(
      Task = factor(Task, levels = task_levels),
      Model = case_when(
        str_detect(model, "Mistral") ~ "Mistral-7B",
        str_detect(model, "Llama-3_3-70B") ~ "Llama-3.3-70B",
        str_detect(model, "72B") ~ "Qwen2.5-72B",
        str_detect(model, "32B") ~ "Qwen2.5-32B",
        str_detect(model, "7B") ~ "Qwen2.5-7B",
        TRUE ~ model
      ),
      Model = factor(Model, levels = model_levels),
      Prompt = factor(prompt_variant, levels = prompt_levels,
                      labels = unname(prompt_labels[prompt_levels]))
    )

  aggregate_distance_plot <- ggplot(
    aggregate_distance_plot_df,
    aes(x = Prompt, y = total_variation_distance,
        colour = Model, group = Model)
  ) +
    geom_line(linewidth = 0.55, colour = "grey70") +
    geom_point(size = 2.7) +
    facet_wrap(~ Task, nrow = 2, labeller = as_labeller(task_labels)) +
    scale_colour_manual(values = model_colours, drop = FALSE) +
    scale_y_continuous(labels = percent_format(accuracy = 1),
                       limits = c(0, 1)) +
    labs(
      title = "Trajectory prompts improve aggregate distributional alignment",
      subtitle = paste(
        "Total variation distance between Human and LLM category distributions;",
        "lower values indicate closer aggregate alignment."
      ),
      x = NULL,
      y = "Total variation distance",
      colour = "Model",
      caption = paste(
        "Notes: Values pool respondent-wave predictions within each task and prompt condition.",
        "This aggregate metric does not measure individual-level longitudinal accuracy."
      )
    ) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(size = 15, face = "bold"),
      plot.subtitle = element_text(size = 10.5, colour = "grey25"),
      plot.caption = element_text(size = 8.3, colour = "grey35", hjust = 0),
      panel.grid.minor = element_blank(),
      axis.text.x = element_text(angle = 20, hjust = 1),
      strip.text = element_text(face = "bold"),
      legend.position = "bottom"
    )

  aggregate_png <- file.path(
    FIGURE_DIR, "aggregate_distribution_distance_overall.png"
  )
  aggregate_pdf <- file.path(
    FIGURE_DIR, "aggregate_distribution_distance_overall.pdf"
  )
  ggsave(aggregate_png, aggregate_distance_plot, width = 11.5, height = 8,
         dpi = 300, bg = "white")
  ggsave(aggregate_pdf, aggregate_distance_plot, width = 11.5, height = 8,
         bg = "white")
  file.copy(
    aggregate_png,
    file.path(ORGANIZED_MAIN_DIR,
              "aggregate_distribution_distance_overall.png"),
    overwrite = TRUE
  )
}

load_analysis_helpers <- function() {
  script_path <- file.path(PROJECT_ROOT, "03_evaluation", "scripts",
                           "analyse_all_variants.R")
  lines <- readLines(script_path, warn = FALSE)
  boundary <- grep("^csv_files <-", lines)[1]
  if (is.na(boundary) || boundary <= 1L) {
    stop("Could not find execution boundary in ", script_path)
  }
  eval(parse(text = lines[seq_len(boundary - 1L)]), envir = globalenv())
}

# ---------------------------------------------------------------------------
# Figure 2: stable/changing split as a compact three-panel figure.
# ---------------------------------------------------------------------------

stable_path <- file.path(TABLE_DIR, "stable_changing_split_table.csv")
if (!file.exists(stable_path)) {
  stop("Missing stable/changing table: ", stable_path)
}

stable_split <- read_csv(stable_path, show_col_types = FALSE) %>%
  mutate(
    Task = factor(Task, levels = task_levels),
    Model = factor(Model, levels = model_levels),
    acc_stable = parse_number(as.character(`Acc. stable`)),
    acc_changed = parse_number(as.character(`Acc. changed`)),
    false_persistence = parse_number(
      as.character(`False persistence among changers`)
    )
  )

stable_plot_df <- stable_split %>%
  select(Task, Model, acc_stable, acc_changed, false_persistence) %>%
  pivot_longer(
    cols = c(acc_stable, acc_changed, false_persistence),
    names_to = "metric",
    values_to = "value"
  ) %>%
  mutate(
    task_id = as.integer(Task),
    model_offset = recode(
      as.character(Model),
      "Mistral-7B" = -0.32,
      "Qwen2.5-32B" = -0.16,
      "Qwen2.5-7B" = 0,
      "Qwen2.5-72B" = 0.16,
      "Llama-3.3-70B" = 0.32
    ),
    x_position = task_id + model_offset,
    metric = recode(
      metric,
      acc_stable = "A. Accuracy among\nstable respondents",
      acc_changed = "B. Accuracy among\nchanging respondents",
      false_persistence = "C. False persistence\namong changers\n(higher = worse)"
    ),
    metric = factor(metric, levels = c(
      "A. Accuracy among\nstable respondents",
      "B. Accuracy among\nchanging respondents",
      "C. False persistence\namong changers\n(higher = worse)"
    ))
  )

stable_changing_plot <- ggplot(
  stable_plot_df,
  aes(x = x_position, y = value, colour = Model, shape = Model)
) +
  geom_hline(yintercept = c(0.25, 0.50, 0.75), colour = "grey88",
             linewidth = 0.25) +
  geom_point(size = 3.0, stroke = 0.75) +
  facet_wrap(~ metric, nrow = 1) +
  scale_x_continuous(
    breaks = seq_along(task_levels),
    labels = task_labels,
    limits = c(0.55, length(task_levels) + 0.45),
    expand = expansion(mult = c(0.02, 0.02))
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, 1),
    breaks = seq(0, 1, by = 0.25),
    expand = expansion(mult = c(0.02, 0.05))
  ) +
  scale_colour_manual(values = model_colours, drop = FALSE) +
  scale_shape_manual(values = c(
    "Mistral-7B" = 16,
    "Qwen2.5-32B" = 17,
    "Qwen2.5-7B" = 15,
    "Qwen2.5-72B" = 18,
    "Llama-3.3-70B" = 8
  ), drop = FALSE) +
  labs(
    title = "Trajectory prompts fail where dynamics matter",
    subtitle = paste(
      "Accuracy is high when respondents remain stable, but collapses",
      "among changers; false persistence is the dominant error mode."
    ),
    x = NULL,
    y = NULL,
    colour = "Model",
    shape = "Model",
    caption = paste(
      "Notes: Points show trajectory-prompt predictions only, pooled over eligible respondent-wave rows across waves.",
      "Changing respondents have a current human response different from their previous response.\nFalse persistence",
      "is the share of changing rows where the trajectory prediction remains at the previous human response."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(size = 15, face = "bold"),
    plot.subtitle = element_text(size = 10.5, colour = "grey25"),
    plot.caption = element_text(size = 8.3, colour = "grey35", hjust = 0,
                                margin = margin(t = 8)),
    panel.grid.major.x = element_blank(),
    panel.grid.minor = element_blank(),
    strip.text = element_text(size = 10.5, face = "bold"),
    axis.text.x = element_text(size = 8.5, colour = "grey25"),
    axis.text.y = element_text(colour = "grey30"),
    legend.position = "bottom",
    plot.margin = margin(10, 14, 10, 10)
  )

stable_png <- file.path(FIGURE_DIR, "stable_changing_split.png")
stable_pdf <- file.path(FIGURE_DIR, "stable_changing_split.pdf")
ggsave(stable_png, stable_changing_plot, width = 12.5, height = 6.2,
       dpi = 300, bg = "white")
ggsave(stable_pdf, stable_changing_plot, width = 12.5, height = 6.2,
       bg = "white")
file.copy(stable_png, file.path(ORGANIZED_MAIN_DIR,
                                "stable_changing_split.png"),
          overwrite = TRUE)

# ---------------------------------------------------------------------------
# Figure 3: representative anchored-change heatmap, all waves combined.
# ---------------------------------------------------------------------------

load_analysis_helpers()

left_right_csv <- file.path(ANALYSIS_INPUT_DIR, "analyse_1500.csv")
if (!file.exists(left_right_csv)) {
  stop("Missing analysis input: ", left_right_csv)
}

raw_1500 <- prepare_raw(left_right_csv)

heat <- raw_1500 %>%
  filter(
    str_to_lower(prompt_variant) == "trajectory",
    !is.na(label_num),
    !is.na(predict_num),
    !is.na(vorwelle_label_num)
  ) %>%
  mutate(
    delta_H = label_num - vorwelle_label_num,
    delta_L = predict_num - vorwelle_label_num
  )

if (nrow(heat) == 0L) {
  stop("No valid trajectory rows found for anchored-change heatmap.")
}

delta_H_levels <- sort(unique(heat$delta_H))
delta_L_levels <- sort(unique(heat$delta_L))
zero_l_position <- match(0, delta_L_levels)

heatmap_grid <- heat %>%
  count(model, delta_H, delta_L, name = "count") %>%
  group_by(model, delta_H) %>%
  mutate(row_percent = count / sum(count)) %>%
  ungroup() %>%
  complete(
    model,
    delta_H = delta_H_levels,
    delta_L = delta_L_levels,
    fill = list(count = 0L, row_percent = 0)
  ) %>%
  mutate(
    model_short = recode(
      model,
      "Mistral-7B-Instruct-v0_3" = "Mistral-7B",
      "Qwen2_5-32B-Instruct" = "Qwen2.5-32B",
      "Qwen2_5-7B-Instruct-GPTQ-Int4" = "Qwen2.5-7B",
      "Qwen2_5-72B-Instruct" = "Qwen2.5-72B",
      "Llama-3_3-70B-Instruct" = "Llama-3.3-70B",
      .default = model
    ),
    model_short = factor(model_short, levels = model_levels),
    delta_H = factor(delta_H, levels = delta_H_levels),
    delta_L = factor(delta_L, levels = delta_L_levels),
    tile_label = if_else(
      !is.na(row_percent) & row_percent >= 0.03,
      percent(row_percent, accuracy = 1),
      ""
    )
  )

write_csv(
  heatmap_grid,
  file.path(FIGURE_DIR, "anchored_change_heatmap_left_right_grouped_data.csv")
)

anchored_heatmap <- ggplot(
  heatmap_grid,
  aes(x = delta_L, y = delta_H, fill = row_percent)
) +
  geom_tile(colour = "white", linewidth = 0.45) +
  {if (!is.na(zero_l_position)) {
    geom_vline(xintercept = zero_l_position, colour = "#0F766E",
               linewidth = 0.55, linetype = "dashed")
  }} +
  geom_text(aes(label = tile_label), size = 2.7, colour = "#111827") +
  facet_wrap(~ model_short, nrow = 1) +
  scale_fill_gradientn(
    colours = heatmap_fill_colours,
    values = seq(0, 1, length.out = length(heatmap_fill_colours)),
    limits = c(0, 1),
    labels = percent_format(accuracy = 1),
    na.value = "#F7FCF5",
    guide = guide_colourbar(nbin = 256, raster = TRUE,
                            frame.colour = "grey70",
                            ticks.colour = "grey40")
  ) +
  labs(
    title = "Anchored-change heatmaps reveal false persistence",
    subtitle = paste(
      "Grouped left-right ideology, all waves combined.",
      "The dashed column marks Delta L = 0: predictions that remain",
      "at the previous human response."
    ),
    x = "Delta L: LLM prediction minus previous human response",
    y = "Delta H: current minus previous human response",
    fill = "Row %",
    caption = paste(
      "Notes: Cells pool valid trajectory respondent-wave transitions across waves.",
      "Rows condition on observed human change and report row percentages within each Delta H row.\nFor rows with Delta H != 0, mass",
      "in the Delta L = 0 column indicates false persistence; for Delta H = 0,",
      "the same column corresponds to correct stability.\nFull task-by-wave",
      "heatmaps are reported in the appendix."
    )
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(size = 15, face = "bold"),
    plot.subtitle = element_text(size = 10.5, colour = "grey25"),
    plot.caption = element_text(size = 8.3, colour = "grey35", hjust = 0,
                                margin = margin(t = 8)),
    panel.grid = element_blank(),
    strip.text = element_text(size = 10.5, face = "bold"),
    legend.position = "right",
    plot.margin = margin(10, 14, 10, 10)
  )

heatmap_png <- file.path(
  FIGURE_DIR,
  "anchored_change_heatmap_left_right_grouped.png"
)
heatmap_pdf <- file.path(
  FIGURE_DIR,
  "anchored_change_heatmap_left_right_grouped.pdf"
)
ggsave(heatmap_png, anchored_heatmap, width = 12.5, height = 5.8,
       dpi = 300, bg = "white")
ggsave(heatmap_pdf, anchored_heatmap, width = 12.5, height = 5.8,
       bg = "white")
file.copy(
  heatmap_png,
  file.path(ORGANIZED_MAIN_DIR,
            "anchored_change_heatmap_left_right_grouped.png"),
  overwrite = TRUE
)

message("Wrote: ", stable_png)
message("Wrote: ", heatmap_png)
