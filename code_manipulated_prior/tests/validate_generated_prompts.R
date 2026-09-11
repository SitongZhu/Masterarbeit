suppressPackageStartupMessages(library(jsonlite))

source_file <- file.path("..", "code", "outputs", "prompts", "1290",
                         "prompt_w14_trajectory.json")
generated_dir <- file.path("outputs", "prompts", "1290_grouped")
source_records <- fromJSON(source_file)
correct <- fromJSON(file.path(generated_dir, "prompt_w14_trajectory_correct_prior.json"))
shuffled <- fromJSON(file.path(generated_dir, "prompt_w14_trajectory_shuffled_prior.json"))
incorrect <- fromJSON(file.path(generated_dir, "prompt_w14_trajectory_incorrect_prior.json"))
pattern <- 'geantwortet: "([^"]+)"\\.'
blank_prior <- function(x) sub(pattern, "PRIOR_BLOCK", x, perl = TRUE)

stopifnot(
  identical(source_records, correct),
  all(blank_prior(source_records$instruction) == blank_prior(shuffled$instruction)),
  all(blank_prior(source_records$instruction) == blank_prior(incorrect$instruction)),
  identical(source_records[, c("input", "output", "id")],
            shuffled[, c("input", "output", "id")]),
  identical(source_records[, c("input", "output", "id")],
            incorrect[, c("input", "output", "id")])
)
cat("Generated-prompt invariance checks passed.\n")
