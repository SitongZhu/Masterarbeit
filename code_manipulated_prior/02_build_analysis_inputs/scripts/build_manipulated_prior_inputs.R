suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(stringr)
})

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
manifest_file <- file.path(project_root, "data", "prompt_manifests", "manipulated_prior_manifest.csv")
if (!file.exists(manifest_file)) stop("Run run_01_generate_manipulated_prior_prompts.R first.")

llm_root <- Sys.getenv(
  "MANIPULATED_PRIOR_LLM_OUTPUT_ROOT",
  unset = file.path(project_root, "data", "llm_outputs", "outcome")
)
if (!dir.exists(llm_root)) stop("LLM output directory does not exist: ", llm_root)
analysis_root <- file.path(project_root, "data", "analysis_inputs")
dir.create(analysis_root, recursive = TRUE, showWarnings = FALSE)

manifest <- read.csv(manifest_file, stringsAsFactors = FALSE, check.names = FALSE,
                     fileEncoding = "UTF-8") %>%
  mutate(across(c(task, target_wave, id, prompt_variant, prior_condition,
                  true_prior, supplied_prior, current_human), as.character))

parse_metadata <- function(path) {
  file_name <- basename(path)
  hit <- str_match(file_name,
    "^nosft_(.+?)__prompt_(w[0-9]+)_(trajectory_(correct|shuffled|incorrect)_prior)\\.jsonl$")
  if (any(is.na(hit))) stop("Unexpected JSONL filename: ", file_name)
  data.frame(llm_model = hit[, 2L], target_wave = hit[, 3L],
             prompt_variant = hit[, 4L], stringsAsFactors = FALSE)
}

read_jsonl <- function(path, task) {
  connection <- file(path, open = "rt", encoding = "UTF-8")
  on.exit(close(connection), add = TRUE)
  content <- stream_in(connection, verbose = FALSE, simplifyDataFrame = TRUE)
  required <- c("id", "predict")
  if (!all(required %in% names(content))) {
    stop("JSONL lacks id/predict fields: ", path)
  }
  metadata <- parse_metadata(path)
  data.frame(
    task = task,
    target_wave = metadata$target_wave,
    id = as.character(content$id),
    llm_model = metadata$llm_model,
    prompt_variant = metadata$prompt_variant,
    jsonl_label = if ("label" %in% names(content)) as.character(content$label) else NA_character_,
    predict_raw = as.character(content$predict),
    source_jsonl = normalizePath(path, winslash = "/", mustWork = TRUE),
    stringsAsFactors = FALSE
  )
}

task_dirs <- list.dirs(llm_root, recursive = FALSE, full.names = TRUE)
task_dirs <- task_dirs[basename(task_dirs) %in% unique(manifest$task)]
if (!length(task_dirs)) {
  stop("No task directories found. Expected: ", paste(unique(manifest$task), collapse = ", "))
}

prediction_parts <- list()
counter <- 0L
for (task_dir in task_dirs) {
  files <- list.files(task_dir, pattern = "^nosft_.*\\.jsonl$", recursive = TRUE,
                      full.names = TRUE)
  for (path in files) {
    counter <- counter + 1L
    prediction_parts[[counter]] <- read_jsonl(path, basename(task_dir))
  }
}
if (!length(prediction_parts)) stop("No manipulated-prior JSONL files found.")
predictions <- bind_rows(prediction_parts)

prediction_key <- c("task", "target_wave", "id", "llm_model", "prompt_variant")
if (anyDuplicated(predictions[prediction_key])) {
  duplicate_rows <- predictions %>% count(across(all_of(prediction_key))) %>% filter(n > 1L)
  write.csv(duplicate_rows, file.path(analysis_root, "duplicate_prediction_keys.csv"), row.names = FALSE)
  stop("Duplicate prediction keys found; see duplicate_prediction_keys.csv.")
}

manifest_key <- c("task", "target_wave", "id", "prompt_variant")
if (anyDuplicated(manifest[manifest_key])) stop("Manifest keys are not unique.")
joined <- predictions %>%
  left_join(manifest, by = manifest_key)

if (any(is.na(joined$prior_condition))) {
  unmatched <- joined %>% filter(is.na(prior_condition)) %>% distinct(across(all_of(manifest_key)))
  write.csv(unmatched, file.path(analysis_root, "unmatched_prediction_rows.csv"), row.names = FALSE)
  stop("Some LLM outputs do not match the prompt manifest; see unmatched_prediction_rows.csv.")
}

# Some runners preserve a trailing newline in the JSONL label.  Treat leading
# and trailing whitespace as serialization noise while retaining the strict
# content check for genuine label mismatches.
normalized_jsonl_label <- trimws(joined$jsonl_label)
normalized_current_human <- trimws(joined$current_human)
label_mismatch <- !is.na(normalized_jsonl_label) & nzchar(normalized_jsonl_label) &
  normalized_jsonl_label != normalized_current_human
if (any(label_mismatch)) {
  write.csv(joined[label_mismatch, ], file.path(analysis_root, "jsonl_label_mismatches.csv"),
            row.names = FALSE, fileEncoding = "UTF-8")
  stop("JSONL label differs from the manifest current-human response.")
}

write.csv(joined, file.path(analysis_root, "manipulated_prior_predictions.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")
for (task_name in unique(joined$task)) {
  write.csv(filter(joined, task == task_name),
            file.path(analysis_root, paste0(task_name, "_predictions.csv")),
            row.names = FALSE, fileEncoding = "UTF-8")
}

coverage <- joined %>%
  count(task, target_wave, llm_model, prior_condition, name = "n_predictions")
write.csv(coverage, file.path(analysis_root, "prediction_coverage.csv"), row.names = FALSE)
cat("Built analysis input with", nrow(joined), "LLM predictions.\n")
