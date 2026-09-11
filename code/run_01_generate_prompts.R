#!/usr/bin/env Rscript

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "01_prompt_generation"))) {
  stop("Run this script from the code project root.")
}

run_script <- function(path) {
  message("\n==== running: ", path, " ====")
  sys.source(file.path(PROJECT_ROOT, path),
             envir = new.env(parent = globalenv()))
}

scripts <- c(
  "01_prompt_generation/scripts/build_1290_clustered_prompts.R",
  "01_prompt_generation/scripts/build_1290_original_scale_prompts.R",
  "01_prompt_generation/scripts/build_1500_clustered_prompts.R",
  "01_prompt_generation/scripts/build_1500_original_scale_prompts.R"
)

for (script in scripts) {
  run_script(script)
}

message("\nPrompt generation complete.")
message("Prompts: ", file.path(PROJECT_ROOT, "outputs", "prompts"))
message("Wave-list RDS files: ",
        file.path(PROJECT_ROOT, "data", "intermediate_hdata"))
