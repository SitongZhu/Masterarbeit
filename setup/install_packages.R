#!/usr/bin/env Rscript
packages <- c(
  "MASS", "broom", "dplyr", "ggplot2", "glue", "haven", "jsonlite",
  "labelled", "nnet", "ordinal", "patchwork", "purrr", "readr", "scales",
  "stringdist", "stringr", "tibble", "tidyr", "tidyselect", "viridis"
)
missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")
remaining <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
if (length(remaining)) stop("Packages still missing: ", paste(remaining, collapse = ", "))
cat("Required R packages are available.
")
