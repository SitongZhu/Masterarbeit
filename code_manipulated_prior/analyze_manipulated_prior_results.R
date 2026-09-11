suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

evaluation_root <- file.path("outputs", "evaluation")

paired <- read.csv(
  file.path(evaluation_root, "paired_prior_induced_change_overall.csv"),
  stringsAsFactors = FALSE
)

task_condition <- paired %>%
  group_by(task, prior_condition) %>%
  summarise(
    n_pairs = sum(n_pairs),
    parse_pair_rate = sum(n_both_parsed) / sum(n_pairs),
    prediction_change = weighted.mean(
      prior_induced_prediction_change, n_both_parsed
    ),
    changed_to_supplied = weighted.mean(
      changed_predictions_to_supplied_prior,
      n_both_parsed * prior_induced_prediction_change
    ),
    correct_accuracy = weighted.mean(correct_prior_accuracy, n_both_parsed),
    manipulated_accuracy = weighted.mean(
      manipulated_prior_accuracy, n_both_parsed
    ),
    accuracy_degradation = correct_accuracy - manipulated_accuracy,
    manipulated_following = weighted.mean(
      manipulated_prior_following, n_conflict_pairs
    ),
    .groups = "drop"
  )

model_condition <- paired %>%
  group_by(llm_model, prior_condition) %>%
  summarise(
    prediction_change = weighted.mean(
      prior_induced_prediction_change, n_both_parsed
    ),
    changed_to_supplied = weighted.mean(
      changed_predictions_to_supplied_prior,
      n_both_parsed * prior_induced_prediction_change
    ),
    accuracy_degradation = weighted.mean(accuracy_degradation, n_both_parsed),
    manipulated_following = weighted.mean(
      manipulated_prior_following, n_conflict_pairs
    ),
    .groups = "drop"
  )

wave <- read.csv(
  file.path(evaluation_root, "accuracy_degradation_by_wave.csv"),
  stringsAsFactors = FALSE
)

wave_consistency <- wave %>%
  group_by(task, prior_condition) %>%
  summarise(
    cells = n(),
    positive_cells = sum(accuracy_degradation > 0),
    minimum = min(accuracy_degradation),
    median = median(accuracy_degradation),
    maximum = max(accuracy_degradation),
    .groups = "drop"
  )

condition <- read.csv(
  file.path(evaluation_root, "prior_condition_metrics_overall.csv"),
  stringsAsFactors = FALSE
)

baseline_by_model_task <- condition %>%
  filter(prior_condition == "correct_prior") %>%
  select(task, llm_model, parse_rate, accuracy, supplied_prior_agreement)

conflict_rates <- condition %>%
  filter(prior_condition != "correct_prior") %>%
  group_by(task, prior_condition) %>%
  summarise(
    supplied_conflicts_current = sum(n_supplied_conflicts_current) / sum(n),
    .groups = "drop"
  )

print_summary <- function(title, data) {
  cat("\n", title, "\n", sep = "")
  print(
    data %>% as_tibble() %>% mutate(across(where(is.numeric), ~ round(.x, 3))),
    n = Inf,
    width = Inf
  )
}

print_summary("TASK_CONDITION", task_condition)
print_summary("MODEL_CONDITION", model_condition)
print_summary("WAVE_CONSISTENCY", wave_consistency)
print_summary("CORRECT_PRIOR_BASELINE", baseline_by_model_task)
print_summary("MANIPULATION_CONFLICT_RATE", conflict_rates)
