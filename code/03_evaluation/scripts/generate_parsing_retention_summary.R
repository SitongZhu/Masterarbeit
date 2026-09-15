#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
EVALUATION_ROOT <- file.path(PROJECT_ROOT, "outputs", "evaluation")
RUN_DIR <- file.path(
  EVALUATION_ROOT, "common_sample_accuracy", "runs", "run_manuscript"
)
SOURCE <- file.path(RUN_DIR, "common_sample_accuracy_pooled.csv")
if (!file.exists(SOURCE)) stop("Missing canonical common-sample output: ", SOURCE)

TABLE_DIR <- file.path(EVALUATION_ROOT, "tables")
PUBLICATION_DIR <- file.path(EVALUATION_ROOT, "manuscript", "tables")
PAPER_GENERATED_DIR <- file.path(
  PROJECT_ROOT, "outputs", "evaluation", "publication", "latex"
)
dir.create(TABLE_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(PUBLICATION_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(PAPER_GENERATED_DIR, recursive = TRUE, showWarnings = FALSE)

task_labels <- c(
  "1290" = "Climate-growth grouped",
  "1290_original_scale" = "Climate-growth original scale",
  "1500" = "Left-right grouped",
  "1500_original_scale" = "Left-right original scale"
)
prompt_labels <- c(
  baseline = "Date-bounded",
  baseline_notime = "No-time",
  tanchored = "Context-anchored",
  trajectory = "Trajectory"
)
prompt_order <- names(prompt_labels)

summary <- read_csv(SOURCE, show_col_types = FALSE) %>%
  mutate(
    Task = unname(task_labels[variant]),
    Prompt = unname(prompt_labels[prompt_variant]),
    task_order = match(variant, names(task_labels)),
    prompt_order = match(prompt_variant, prompt_order),
    unparsed_predictions = n_total - n_parsed_predict,
    parsed_share = n_parsed_predict / n_total
  ) %>%
  arrange(task_order, prompt_order) %>%
  transmute(
    variant,
    prompt_variant,
    Task,
    Prompt,
    evaluation_n = n_total,
    parsed_n = n_parsed_predict,
    unparsed_n = unparsed_predictions,
    parsed_share,
    exact_match_accuracy = accuracy
  )

if (nrow(summary) != 16L || any(!complete.cases(summary))) {
  stop("Canonical parsing summary must contain 16 complete task-prompt rows.")
}

canonical_path <- file.path(
  PUBLICATION_DIR, "parsing_retention_summary.csv"
)
write_csv(summary, canonical_path)

display <- summary %>%
  transmute(
    Task,
    Prompt,
    `Evaluation denominator` = format(evaluation_n, big.mark = ",", scientific = FALSE),
    `Parsed predictions` = format(parsed_n, big.mark = ",", scientific = FALSE),
    `Unparsed predictions` = format(unparsed_n, big.mark = ",", scientific = FALSE),
    `Parsed share` = sprintf("%.5f", parsed_share),
    Accuracy = sprintf("%.3f", exact_match_accuracy)
  )
write_csv(display, file.path(TABLE_DIR, "parsing_retention_summary_table.csv"))

markdown <- c(
  paste0("| ", paste(names(display), collapse = " | "), " |"),
  paste0("| ", paste(rep("---", ncol(display)), collapse = " | "), " |"),
  apply(display, 1L, function(row) {
    paste0("| ", paste(row, collapse = " | "), " |")
  })
)
writeLines(
  markdown,
  file.path(TABLE_DIR, "parsing_retention_summary_table.md"),
  useBytes = TRUE
)

latex_task <- summary$Task
latex_rows <- sprintf(
  "%s & %s & %s & %s & %.5f & %.3f \\\\",
  latex_task,
  summary$Prompt,
  format(summary$evaluation_n, big.mark = ",", scientific = FALSE),
  format(summary$parsed_n, big.mark = ",", scientific = FALSE),
  summary$parsed_share,
  summary$exact_match_accuracy
)
writeLines(
  c(latex_rows, "\\hline"),
  file.path(PAPER_GENERATED_DIR, "parsing_retention_summary_rows.tex"),
  useBytes = TRUE
)

message("Refreshed canonical and display parsing-retention summaries.")
