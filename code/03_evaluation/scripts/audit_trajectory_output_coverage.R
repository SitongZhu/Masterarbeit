#!/usr/bin/env Rscript

suppressPackageStartupMessages(library(jsonlite))

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
OUTPUT_ROOT <- file.path(PROJECT_ROOT, "data", "llm_outputs", "outcome")
PROMPT_ROOT <- file.path(PROJECT_ROOT, "outputs", "prompts")

files <- list.files(
  OUTPUT_ROOT,
  pattern = "_trajectory\\.jsonl$",
  recursive = TRUE,
  full.names = TRUE
)
if (length(files) == 0L) stop("No trajectory JSONL files found.")

output_root_normalized <- normalizePath(
  OUTPUT_ROOT, winslash = "/", mustWork = TRUE
)

rows <- lapply(files, function(path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = TRUE)
  relative <- substring(normalized, nchar(output_root_normalized) + 2L)
  variant <- strsplit(relative, "/", fixed = TRUE)[[1L]][1L]
  wave <- sub(
    ".*__prompt_(w[0-9]+)_trajectory\\.jsonl$", "\\1", basename(path)
  )
  prompt_path <- file.path(
    PROMPT_ROOT, variant, paste0("prompt_", wave, "_trajectory.json")
  )
  if (!file.exists(prompt_path)) {
    return(data.frame(
      variant = variant,
      file = basename(path),
      wave = wave,
      expected_n = NA_integer_,
      output_n = NA_integer_,
      unique_output_n = NA_integer_,
      missing_n = NA_integer_,
      extra_n = NA_integer_,
      manifest_available = FALSE
    ))
  }

  expected_ids <- as.character(fromJSON(prompt_path)[["id"]])
  connection <- file(path, open = "r")
  on.exit(close(connection), add = TRUE)
  output_ids <- as.character(stream_in(connection, verbose = FALSE)[["id"]])
  close(connection)
  on.exit(NULL, add = FALSE)

  data.frame(
    variant = variant,
    file = basename(path),
    wave = wave,
    expected_n = length(expected_ids),
    output_n = length(output_ids),
    unique_output_n = length(unique(output_ids)),
    missing_n = length(setdiff(expected_ids, output_ids)),
    extra_n = length(setdiff(output_ids, expected_ids)),
    manifest_available = TRUE
  )
})

coverage <- do.call(rbind, rows)
coverage$complete <- with(
  coverage,
  manifest_available & expected_n == output_n & output_n == unique_output_n &
    missing_n == 0L & extra_n == 0L
)

comparable <- coverage[coverage$manifest_available, ]
print(aggregate(complete ~ variant, comparable, function(x) {
  sprintf("%d/%d complete", sum(x), length(x))
}))

orphaned <- coverage[!coverage$manifest_available, c("variant", "file", "wave")]
if (nrow(orphaned) > 0L) {
  message("Ignoring archived trajectory outputs without a current prompt manifest:")
  print(orphaned, row.names = FALSE)
}

incomplete <- comparable[!comparable$complete, ]
if (nrow(incomplete) > 0L) {
  print(incomplete, row.names = FALSE)
  quit(status = 1L)
}

message("All trajectory JSONL files contain exactly the prompt-manifest IDs.")
