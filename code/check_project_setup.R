#!/usr/bin/env Rscript
if (!dir.exists("01_prompt_generation")) stop("Run from the code/ directory.")
directories <- c(
  "data/raw_survey/ZA6838_v6-0-0.dta", "data/intermediate_hdata",
  "data/llm_outputs/outcome", "data/analysis_inputs", "outputs/prompts",
  "outputs/evaluation"
)
for (path in directories) dir.create(path, recursive = TRUE, showWarnings = FALSE)
required <- c("haven", "dplyr", "labelled", "jsonlite", "glue", "purrr",
              "stringr", "tidyr", "stringdist", "readr", "ggplot2", "broom",
              "scales", "viridis", "patchwork", "MASS", "nnet", "ordinal",
              "svglite", "tibble", "tidyselect")
missing <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) stop("Run Rscript ../setup/install_packages.R. Missing: ",
                          paste(missing, collapse = ", "))
cat("Source layout and R dependencies: OK.\n")
cat("Raw .dta files:", length(list.files(directories[1], pattern = "\\.dta$")), "\n")
cat("Wave-list .rds files:", length(list.files(directories[2], pattern = "^wave_list.*\\.rds$")), "\n")
cat("LLM .jsonl files:", length(list.files(directories[3], pattern = "\\.jsonl$", recursive = TRUE)), "\n")
cat("Research data are supplied separately; see data/README.md.\n")
