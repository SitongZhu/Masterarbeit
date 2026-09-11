#!/usr/bin/env Rscript
# Exercises all four task representations and all three prior conditions.
local({
  stopifnot(dir.exists("code_manipulated_prior"))
  repository <- normalizePath(getwd(), winslash = "/")
  temporary <- tempfile("thesis_prior_smoke_")
  prompt_root <- file.path(temporary, "prompts")
  project <- file.path(temporary, "experiment")
  dir.create(project, recursive = TRUE)
  old_source <- Sys.getenv("SOURCE_PROMPT_ROOT", unset = NA_character_)
  old_output <- Sys.getenv("MANIPULATED_PRIOR_LLM_OUTPUT_ROOT", unset = NA_character_)
  on.exit({
    setwd(repository)
    if (is.na(old_source)) Sys.unsetenv("SOURCE_PROMPT_ROOT") else Sys.setenv(SOURCE_PROMPT_ROOT = old_source)
    if (is.na(old_output)) Sys.unsetenv("MANIPULATED_PRIOR_LLM_OUTPUT_ROOT") else Sys.setenv(MANIPULATED_PRIOR_LLM_OUTPUT_ROOT = old_output)
    unlink(temporary, recursive = TRUE)
  }, add = TRUE)
  cfg <- list(
    "1290" = c("Vorrang_fuer_Bekaempfung_des_Klimawandels", "Mittelposition", "Vorrang_fuer_Wirtschaftswachstum"),
    "1290_original_scale" = as.character(1:7),
    "1500" = c("Links", "Neutral", "Rechts"),
    "1500_original_scale" = as.character(1:11)
  )
  for (variant in names(cfg)) {
    values <- cfg[[variant]]
    prior <- rep(values, length.out = 22L)
    current <- c(prior[-1L], prior[1L])
    instruction <- if (grepl("original_scale", variant)) {
      paste0("Synthetischer Prompt. lautete die damals gegebene Antwort: ", prior, ". Bitte antworte.")
    } else paste0('Synthetischer Prompt. geantwortet: "', prior, '". Bitte antworte.')
    records <- data.frame(instruction, input = "", output = current, id = 900000 + seq_along(prior))
    dir.create(file.path(prompt_root, variant), recursive = TRUE)
    jsonlite::write_json(records, file.path(prompt_root, variant, "prompt_w14_trajectory.json"), auto_unbox = TRUE)
  }
  setwd(project)
  Sys.setenv(SOURCE_PROMPT_ROOT = prompt_root,
             MANIPULATED_PRIOR_LLM_OUTPUT_ROOT = file.path(project, "data", "llm_outputs", "outcome"))
  run <- function(relative) sys.source(file.path(repository, "code_manipulated_prior", relative),
                                       envir = new.env(parent = globalenv()))
  run("01_prompt_generation/scripts/generate_manipulated_prior_prompts.R")
  manifest <- read.csv("data/prompt_manifests/manipulated_prior_manifest.csv", stringsAsFactors = FALSE)
  stopifnot(nrow(manifest) == 4L * 3L * 22L)
  for (task in unique(manifest$task)) {
    original_variant <- sub("_grouped$", "", task)
    original <- jsonlite::fromJSON(file.path(prompt_root, original_variant, "prompt_w14_trajectory.json"))
    correct <- jsonlite::fromJSON(file.path("outputs", "prompts", task, "prompt_w14_trajectory_correct_prior.json"))
    stopifnot(identical(original, correct))
    pattern <- if (grepl("original_scale", task)) "lautete die damals gegebene Antwort: ([^.\\r\\n]+)\\." else 'geantwortet: "([^"]+)"\\.'
    for (condition in c("shuffled_prior", "incorrect_prior")) {
      altered <- jsonlite::fromJSON(file.path("outputs", "prompts", task, paste0("prompt_w14_trajectory_", condition, ".json")))
      stopifnot(identical(original[, c("id", "input", "output")], altered[, c("id", "input", "output")]),
                identical(sub(pattern, "PRIOR", original$instruction), sub(pattern, "PRIOR", altered$instruction)))
    }
    shuffled <- manifest[manifest$task == task & manifest$prior_condition == "shuffled_prior", ]
    incorrect <- manifest[manifest$task == task & manifest$prior_condition == "incorrect_prior", ]
    stopifnot(all(shuffled$id != shuffled$donor_id),
              identical(sort(shuffled$true_prior), sort(shuffled$supplied_prior)),
              all(incorrect$true_prior != incorrect$supplied_prior))
    if (grepl("original_scale", task)) stopifnot(all(abs(as.numeric(incorrect$true_prior) - as.numeric(incorrect$supplied_prior)) == 1))
    for (condition in c("correct_prior", "shuffled_prior", "incorrect_prior")) {
      part <- manifest[manifest$task == task & manifest$prior_condition == condition, ]
      prediction <- if (condition == "correct_prior") part$current_human else part$supplied_prior
      out <- file.path("data", "llm_outputs", "outcome", task)
      dir.create(out, recursive = TRUE, showWarnings = FALSE)
      con <- file(file.path(out, paste0("nosft_synthetic-model__prompt_w14_trajectory_", condition, ".jsonl")), "w", encoding = "UTF-8")
      jsonlite::stream_out(data.frame(id = part$id, label = part$current_human, predict = prediction), con, verbose = FALSE)
      close(con)
    }
  }
  # The generator's fixed seeds must reproduce the same supplied priors.
  run("01_prompt_generation/scripts/generate_manipulated_prior_prompts.R")
  stopifnot(identical(manifest, read.csv("data/prompt_manifests/manipulated_prior_manifest.csv", stringsAsFactors = FALSE)))
  run("02_build_analysis_inputs/scripts/build_manipulated_prior_inputs.R")
  run("03_evaluation/scripts/evaluate_manipulated_prior.R")
  metrics <- read.csv("outputs/evaluation/prior_condition_metrics_overall.csv")
  paired <- read.csv("outputs/evaluation/paired_prior_induced_change_overall.csv")
  stopifnot(nrow(metrics) == 12L, all(metrics$parse_rate == 1),
            all(metrics$accuracy[metrics$prior_condition == "correct_prior"] == 1),
            nrow(paired) == 8L, all(paired$n_pairs == 22L),
            all(paired$manipulated_prior_following == 1),
            all(abs(paired$accuracy_degradation - (1 - paired$manipulated_prior_accuracy)) < 1e-12))
  cat("PASS: 12 prior conditions, prompt invariance, deterministic manipulation, joins, paired evaluation, and figures.\n")
})
