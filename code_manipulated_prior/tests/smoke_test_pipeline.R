suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
})

real_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
temporary_root <- tempfile("manipulated_prior_smoke_")
dir.create(file.path(temporary_root, "data", "prompt_manifests"), recursive = TRUE)
dir.create(file.path(temporary_root, "data", "llm_outputs", "outcome", "1290_grouped"),
           recursive = TRUE)
on.exit({
  setwd(real_root)
  unlink(temporary_root, recursive = TRUE, force = TRUE)
}, add = TRUE)

manifest <- read.csv(file.path(real_root, "data", "prompt_manifests",
                               "manipulated_prior_manifest.csv"),
                     stringsAsFactors = FALSE, fileEncoding = "UTF-8")
cell <- manifest %>% filter(task == "1290_grouped", target_wave == "w14")
sample_ids <- cell %>% filter(prior_condition == "correct_prior") %>%
  slice_head(n = 20L) %>% pull(id) %>% as.character()
fixture <- cell %>% filter(as.character(id) %in% sample_ids)
write.csv(fixture, file.path(temporary_root, "data", "prompt_manifests",
                             "manipulated_prior_manifest.csv"), row.names = FALSE)

for (condition in c("correct_prior", "shuffled_prior", "incorrect_prior")) {
  part <- fixture %>% filter(prior_condition == condition)
  prediction <- if (condition == "correct_prior") part$current_human else part$supplied_prior
  lines <- Map(function(id, label, predict) {
    toJSON(list(id = as.character(id), label = as.character(label),
                predict = as.character(predict)), auto_unbox = TRUE)
  }, part$id, part$current_human, prediction)
  file_name <- paste0("nosft_smoke-model__prompt_w14_trajectory_", condition, ".jsonl")
  writeLines(unlist(lines), file.path(temporary_root, "data", "llm_outputs", "outcome",
                                     "1290_grouped", file_name), useBytes = TRUE)
}

setwd(temporary_root)
Sys.setenv(MANIPULATED_PRIOR_LLM_OUTPUT_ROOT = file.path(temporary_root, "data",
                                                         "llm_outputs", "outcome"))
source(file.path(real_root, "02_build_analysis_inputs", "scripts",
                 "build_manipulated_prior_inputs.R"), encoding = "UTF-8")
source(file.path(real_root, "03_evaluation", "scripts",
                 "evaluate_manipulated_prior.R"), encoding = "UTF-8")

metrics <- read.csv(file.path(temporary_root, "outputs", "evaluation",
                              "prior_condition_metrics_overall.csv"))
paired <- read.csv(file.path(temporary_root, "outputs", "evaluation",
                             "paired_prior_induced_change_overall.csv"))
stopifnot(
  nrow(metrics) == 3L,
  all(metrics$parse_rate == 1),
  metrics$accuracy[metrics$prior_condition == "correct_prior"] == 1,
  all(paired$manipulated_prior_following == 1)
)
cat("End-to-end smoke test passed.\n")
