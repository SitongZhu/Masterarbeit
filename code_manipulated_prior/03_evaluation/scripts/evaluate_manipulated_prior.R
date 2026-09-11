suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(ggplot2)
})

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
input_file <- file.path(project_root, "data", "analysis_inputs", "manipulated_prior_predictions.csv")
if (!file.exists(input_file)) stop("Run run_02_build_manipulated_prior_inputs.R first.")
output_root <- file.path(project_root, "outputs", "evaluation")
dir.create(output_root, recursive = TRUE, showWarnings = FALSE)

dat <- read.csv(input_file, stringsAsFactors = FALSE, check.names = FALSE,
                fileEncoding = "UTF-8")

clean_prediction <- function(x) {
  x <- trimws(as.character(x))
  x <- gsub('^["\'`]+|["\'`]+$', "", x)
  trimws(x)
}

parse_one <- function(x, task, representation) {
  x <- clean_prediction(x)
  if (is.na(x) || !nzchar(x)) return(NA_character_)
  if (representation == "original_scale") {
    maximum <- if (startsWith(task, "1290")) 7L else 11L
    hit <- str_extract(x, "(?<![0-9])[0-9]{1,2}(?![0-9])")
    value <- suppressWarnings(as.integer(hit))
    return(if (!is.na(value) && value >= 1L && value <= maximum) as.character(value) else NA_character_)
  }
  lower <- tolower(x)
  # Models sometimes render the ASCII category labels with standard German
  # umlauts (for example, fuer/Bekaempfung as für/Bekämpfung).  Normalize
  # these spelling-equivalent forms before matching the manifest labels.
  lower <- str_replace_all(lower, c("ä" = "ae", "ö" = "oe", "ü" = "ue", "ß" = "ss"))
  if (startsWith(task, "1500")) {
    candidates <- c(Links = "links", Neutral = "neutral", Rechts = "rechts")
  } else {
    candidates <- c(
      Vorrang_fuer_Bekaempfung_des_Klimawandels = "vorrang_fuer_bekaempfung_des_klimawandels",
      Mittelposition = "mittelposition",
      Vorrang_fuer_Wirtschaftswachstum = "vorrang_fuer_wirtschaftswachstum"
    )
  }
  exact <- names(candidates)[match(lower, candidates)]
  if (!is.na(exact)) return(exact)
  present <- names(candidates)[vapply(candidates, function(token) grepl(token, lower, fixed = TRUE), logical(1L))]
  if (length(present) == 1L) present else NA_character_
}

parse_predictions <- function(x, task, representation) {
  x <- clean_prediction(x)
  prediction <- rep(NA_character_, length(x))
  valid <- !is.na(x) & nzchar(x)

  original <- valid & representation == "original_scale"
  if (any(original)) {
    hit <- str_extract(x[original], "(?<![0-9])[0-9]{1,2}(?![0-9])")
    value <- suppressWarnings(as.integer(hit))
    maximum <- ifelse(startsWith(task[original], "1290"), 7L, 11L)
    accepted <- !is.na(value) & value >= 1L & value <= maximum
    original_prediction <- rep(NA_character_, length(value))
    original_prediction[accepted] <- as.character(value[accepted])
    prediction[original] <- original_prediction
  }

  grouped <- valid & representation == "grouped"
  if (any(grouped)) {
    grouped_text <- tolower(x[grouped])
    grouped_text <- str_replace_all(
      grouped_text,
      c("ä" = "ae", "ö" = "oe", "ü" = "ue", "ß" = "ss")
    )
    grouped_task <- task[grouped]
    grouped_prediction <- rep(NA_character_, length(grouped_text))

    assign_single_match <- function(index, candidates) {
      if (!any(index)) return(invisible(NULL))
      values <- grouped_text[index]
      hits <- vapply(
        unname(candidates),
        function(token) grepl(token, values, fixed = TRUE),
        logical(length(values))
      )
      if (is.null(dim(hits))) hits <- matrix(hits, nrow = length(values))
      one_hit <- rowSums(hits) == 1L
      selected <- rep(NA_character_, length(values))
      selected[one_hit] <- names(candidates)[max.col(hits[one_hit, , drop = FALSE])]
      grouped_prediction[index] <<- selected
      invisible(NULL)
    }

    assign_single_match(
      startsWith(grouped_task, "1500"),
      c(Links = "links", Neutral = "neutral", Rechts = "rechts")
    )
    assign_single_match(
      startsWith(grouped_task, "1290"),
      c(
        Vorrang_fuer_Bekaempfung_des_Klimawandels =
          "vorrang_fuer_bekaempfung_des_klimawandels",
        Mittelposition = "mittelposition",
        Vorrang_fuer_Wirtschaftswachstum =
          "vorrang_fuer_wirtschaftswachstum"
      )
    )
    prediction[grouped] <- grouped_prediction
  }

  prediction
}

dat$prediction <- parse_predictions(dat$predict_raw, dat$task, dat$representation)
dat <- dat %>%
  mutate(
    parsed = !is.na(prediction),
    correct = if_else(parsed, prediction == current_human, NA),
    supplied_prior_agreement = if_else(parsed, prediction == supplied_prior, NA),
    true_prior_agreement = if_else(parsed, prediction == true_prior, NA),
    manipulated_condition = prior_condition %in% c("shuffled_prior", "incorrect_prior"),
    eligible_for_manipulated_following = manipulated_condition & supplied_prior != current_human,
    manipulated_prior_following = if_else(eligible_for_manipulated_following & parsed,
                                           prediction == supplied_prior, NA)
  )

safe_mean <- function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)

summarise_condition <- function(data, grouping) {
  data %>%
    group_by(across(all_of(grouping))) %>%
    summarise(
      n = n(),
      n_parsed = sum(parsed),
      parse_rate = mean(parsed),
      accuracy = safe_mean(correct),
      supplied_prior_agreement = safe_mean(supplied_prior_agreement),
      true_prior_agreement = safe_mean(true_prior_agreement),
      n_supplied_conflicts_current = sum(eligible_for_manipulated_following),
      manipulated_prior_following = safe_mean(manipulated_prior_following),
      .groups = "drop"
    )
}

condition_overall <- summarise_condition(dat,
  c("task", "outcome", "representation", "llm_model", "prior_condition"))
condition_wave <- summarise_condition(dat,
  c("task", "outcome", "representation", "target_wave", "llm_model", "prior_condition"))

keys <- c("task", "outcome", "representation", "target_wave", "id", "llm_model")
correct_rows <- dat %>%
  filter(prior_condition == "correct_prior") %>%
  select(all_of(keys), correct_prediction = prediction, correct_parsed = parsed,
         correct_is_accurate = correct)
manipulated_rows <- dat %>%
  filter(prior_condition %in% c("shuffled_prior", "incorrect_prior")) %>%
  select(all_of(keys), prior_condition, current_human, true_prior, supplied_prior,
         manipulated_prediction = prediction, manipulated_parsed = parsed,
         manipulated_is_accurate = correct)
paired <- manipulated_rows %>%
  inner_join(correct_rows, by = keys) %>%
  mutate(
    both_parsed = manipulated_parsed & correct_parsed,
    prediction_changed = if_else(both_parsed,
      manipulated_prediction != correct_prediction, NA),
    changed_to_supplied_prior = if_else(both_parsed & manipulated_prediction != correct_prediction,
      manipulated_prediction == supplied_prior, NA),
    supplied_conflicts_current = supplied_prior != current_human,
    follows_manipulated_prior = if_else(manipulated_parsed & supplied_conflicts_current,
      manipulated_prediction == supplied_prior, NA)
  )

summarise_paired <- function(data, grouping) {
  data %>%
    group_by(across(all_of(grouping))) %>%
    summarise(
      n_pairs = n(),
      n_both_parsed = sum(both_parsed),
      prior_induced_prediction_change = safe_mean(prediction_changed),
      changed_predictions_to_supplied_prior = safe_mean(changed_to_supplied_prior),
      correct_prior_accuracy = safe_mean(correct_is_accurate[both_parsed]),
      manipulated_prior_accuracy = safe_mean(manipulated_is_accurate[both_parsed]),
      accuracy_degradation = correct_prior_accuracy - manipulated_prior_accuracy,
      n_conflict_pairs = sum(supplied_conflicts_current & manipulated_parsed),
      manipulated_prior_following = safe_mean(follows_manipulated_prior),
      .groups = "drop"
    )
}

paired_overall <- summarise_paired(paired,
  c("task", "outcome", "representation", "llm_model", "prior_condition"))
paired_wave <- summarise_paired(paired,
  c("task", "outcome", "representation", "target_wave", "llm_model", "prior_condition"))

write.csv(condition_overall, file.path(output_root, "prior_condition_metrics_overall.csv"), row.names = FALSE)
write.csv(condition_wave, file.path(output_root, "prior_condition_metrics_by_wave.csv"), row.names = FALSE)
write.csv(paired_overall, file.path(output_root, "paired_prior_induced_change_overall.csv"), row.names = FALSE)
write.csv(paired_wave, file.path(output_root, "paired_prior_induced_change_by_wave.csv"), row.names = FALSE)
write.csv(select(paired_overall, task, outcome, representation, llm_model, prior_condition,
                 n_pairs, n_both_parsed, correct_prior_accuracy,
                 manipulated_prior_accuracy, accuracy_degradation),
          file.path(output_root, "accuracy_degradation_overall.csv"), row.names = FALSE)
write.csv(select(paired_wave, task, outcome, representation, target_wave, llm_model,
                 prior_condition, n_pairs, n_both_parsed, correct_prior_accuracy,
                 manipulated_prior_accuracy, accuracy_degradation),
          file.path(output_root, "accuracy_degradation_by_wave.csv"), row.names = FALSE)
write.csv(dat, file.path(output_root, "row_level_prior_following.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

plot_data <- condition_overall %>%
  select(task, llm_model, prior_condition, accuracy, supplied_prior_agreement) %>%
  pivot_longer(c(accuracy, supplied_prior_agreement), names_to = "metric", values_to = "value")
plot <- ggplot(plot_data, aes(prior_condition, value, colour = llm_model, group = llm_model)) +
  geom_point(position = position_dodge(width = 0.35), size = 2) +
  facet_grid(metric ~ task) +
  scale_y_continuous(limits = c(0, 1)) +
  labs(x = NULL, y = "Proportion", colour = "LLM model") +
  theme_minimal(base_size = 10) +
  theme(axis.text.x = element_text(angle = 35, hjust = 1))
ggsave(file.path(output_root, "accuracy_and_supplied_prior_agreement.png"), plot,
       width = 12, height = 6.5, dpi = 300)

cat("Evaluated", nrow(dat), "predictions and", nrow(paired), "correct/manipulated pairs.\n")
