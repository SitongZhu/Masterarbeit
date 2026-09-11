suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
  library(stringr)
})

project_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source_prompt_root <- Sys.getenv(
  "SOURCE_PROMPT_ROOT",
  unset = file.path(dirname(project_root), "code", "outputs", "prompts")
)
source_prompt_root <- normalizePath(source_prompt_root, winslash = "/", mustWork = TRUE)
prompt_root <- file.path(project_root, "outputs", "prompts")
manifest_root <- file.path(project_root, "data", "prompt_manifests")
dir.create(prompt_root, recursive = TRUE, showWarnings = FALSE)
dir.create(manifest_root, recursive = TRUE, showWarnings = FALSE)

task_config <- list(
  list(task = "1290_grouped", source = "1290", outcome = "1290",
       representation = "grouped",
       valid = c("Vorrang_fuer_Bekaempfung_des_Klimawandels", "Mittelposition",
                 "Vorrang_fuer_Wirtschaftswachstum"), seed = 129003L),
  list(task = "1290_original_scale", source = NA_character_, outcome = "1290",
       representation = "original_scale", valid = as.character(1:7), seed = 129007L),
  list(task = "1500_grouped", source = "1500", outcome = "1500",
       representation = "grouped", valid = c("Links", "Neutral", "Rechts"), seed = 150003L),
  list(task = "1500_original_scale", source = NA_character_, outcome = "1500",
       representation = "original_scale", valid = as.character(1:11), seed = 150011L)
)

prior_patterns <- c(
  grouped = 'geantwortet: "([^"]+)"\\.',
  original_scale = "lautete die damals gegebene Antwort: ([^.\\r\\n]+)\\."
)

extract_prior <- function(instruction, representation) {
  pattern <- unname(prior_patterns[[representation]])
  hit <- regmatches(instruction, regexec(pattern, instruction, perl = TRUE))[[1L]]
  if (length(hit) != 2L) stop("Could not find exactly one prior block in a prompt.")
  trimws(hit[[2L]])
}

replace_prior <- function(instruction, supplied_prior, representation) {
  pattern <- unname(prior_patterns[[representation]])
  hit <- regmatches(instruction, regexec(pattern, instruction, perl = TRUE))[[1L]]
  if (length(hit) != 2L) stop("Could not replace prior: prior block is missing or ambiguous.")
  replacement <- sub(hit[[2L]], supplied_prior, hit[[1L]], fixed = TRUE)
  sub(hit[[1L]], replacement, instruction, fixed = TRUE)
}

make_derangement <- function(n) {
  if (n < 2L) stop("Shuffling requires at least two respondents in each task-wave cell.")
  randomized <- sample.int(n)
  donor <- integer(n)
  donor[randomized] <- c(randomized[-1L], randomized[1L])
  stopifnot(all(donor != seq_len(n)), identical(sort(donor), seq_len(n)))
  donor
}

make_incorrect <- function(true_prior, valid, representation) {
  if (representation == "grouped") {
    return(vapply(true_prior, function(x) sample(setdiff(valid, x), 1L), character(1L)))
  }
  maximum <- max(as.integer(valid))
  vapply(as.integer(true_prior), function(x) {
    neighbours <- c(x - 1L, x + 1L)
    neighbours <- neighbours[neighbours >= 1L & neighbours <= maximum]
    # sample(x, 1) treats a length-one numeric x as 1:x; sample the index instead.
    as.character(neighbours[[sample.int(length(neighbours), 1L)]])
  }, character(1L))
}

all_manifests <- list()
manifest_counter <- 0L

for (cfg in task_config) {
  if (!is.na(cfg$source)) {
    source_dir <- file.path(source_prompt_root, cfg$source)
  } else {
    candidate_dirs <- list.dirs(source_prompt_root, recursive = FALSE, full.names = TRUE)
    candidate_dirs <- candidate_dirs[
      startsWith(basename(candidate_dirs), paste0(cfg$outcome, "_"))
    ]
    if (length(candidate_dirs) != 1L) {
      stop("Could not uniquely identify the legacy original-scale source for outcome ",
           cfg$outcome, ".")
    }
    source_dir <- candidate_dirs[[1L]]
  }
  files <- list.files(source_dir, pattern = "^prompt_w[0-9]+_trajectory\\.json$",
                      full.names = TRUE)
  if (!length(files)) stop("No trajectory prompt files found in: ", source_dir)
  destination_dir <- file.path(prompt_root, cfg$task)
  dir.create(destination_dir, recursive = TRUE, showWarnings = FALSE)
  task_manifests <- list()

  for (file in sort(files)) {
    wave <- str_match(basename(file), "prompt_(w[0-9]+)_trajectory\\.json$")[, 2L]
    records <- fromJSON(file, simplifyDataFrame = TRUE)
    required <- c("instruction", "input", "output", "id")
    if (!all(required %in% names(records))) stop("Missing prompt fields in: ", file)
    if (anyDuplicated(as.character(records$id))) stop("Duplicate respondent IDs in: ", file)

    true_prior <- vapply(records$instruction, extract_prior, character(1L),
                         representation = cfg$representation)
    if (!all(true_prior %in% cfg$valid)) {
      stop("Unexpected prior value in ", file, ": ",
           paste(setdiff(unique(true_prior), cfg$valid), collapse = ", "))
    }

    wave_number <- as.integer(sub("w", "", wave, fixed = TRUE))
    cell_seed <- cfg$seed + wave_number * 100L
    set.seed(cell_seed)
    donor_index <- make_derangement(nrow(records))
    shuffled_prior <- true_prior[donor_index]
    incorrect_prior <- make_incorrect(true_prior, cfg$valid, cfg$representation)

    conditions <- list(
      correct_prior = list(value = true_prior, donor = rep(NA_character_, nrow(records)),
                           rule = "respondent_true_previous_response"),
      shuffled_prior = list(value = shuffled_prior,
                            donor = as.character(records$id[donor_index]),
                            rule = "within_task_wave_derangement"),
      incorrect_prior = list(value = incorrect_prior,
                             donor = rep(NA_character_, nrow(records)),
                             rule = if (cfg$representation == "grouped")
                               "random_other_grouped_category" else "random_adjacent_scale_point")
    )

    for (condition in names(conditions)) {
      specification <- conditions[[condition]]
      output_records <- records[, required, drop = FALSE]
      output_records$instruction <- mapply(
        replace_prior, output_records$instruction, specification$value,
        MoreArgs = list(representation = cfg$representation), USE.NAMES = FALSE
      )
      prompt_variant <- paste0("trajectory_", condition)
      destination <- file.path(destination_dir, paste0("prompt_", wave, "_", prompt_variant, ".json"))
      write_json(output_records, destination, pretty = TRUE, auto_unbox = TRUE, na = "null")

      manifest_counter <- manifest_counter + 1L
      task_manifests[[manifest_counter]] <- data.frame(
        task = cfg$task,
        outcome = cfg$outcome,
        representation = cfg$representation,
        target_wave = wave,
        id = as.character(records$id),
        prompt_variant = prompt_variant,
        prior_condition = condition,
        true_prior = true_prior,
        supplied_prior = specification$value,
        current_human = as.character(records$output),
        donor_id = specification$donor,
        manipulation_rule = specification$rule,
        random_seed = cell_seed,
        supplied_differs_from_true = specification$value != true_prior,
        supplied_conflicts_current = specification$value != as.character(records$output),
        stringsAsFactors = FALSE
      )
    }
  }
  task_manifest <- bind_rows(task_manifests)
  write.csv(task_manifest, file.path(manifest_root, paste0(cfg$task, "_manifest.csv")),
            row.names = FALSE, fileEncoding = "UTF-8")
  all_manifests[[cfg$task]] <- task_manifest
}

manifest <- bind_rows(all_manifests)
write.csv(manifest, file.path(manifest_root, "manipulated_prior_manifest.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

audit <- manifest %>%
  group_by(task, target_wave, prior_condition) %>%
  summarise(
    n = n(),
    n_unique_ids = n_distinct(id),
    donor_is_always_different = if_else(first(prior_condition) == "shuffled_prior",
      all(!is.na(donor_id) & donor_id != id), TRUE),
    all_values_differ_from_true = if_else(first(prior_condition) == "incorrect_prior",
      all(supplied_prior != true_prior), if_else(first(prior_condition) == "correct_prior",
        all(supplied_prior == true_prior), NA)),
    .groups = "drop"
  )

distribution_audit <- manifest %>%
  filter(prior_condition == "shuffled_prior") %>%
  group_by(task, target_wave) %>%
  summarise(distribution_preserved = identical(sort(true_prior), sort(supplied_prior)),
            .groups = "drop")
audit <- left_join(audit, distribution_audit, by = c("task", "target_wave")) %>%
  mutate(distribution_preserved = if_else(prior_condition == "shuffled_prior",
                                          distribution_preserved, TRUE))
write.csv(audit, file.path(manifest_root, "manipulation_audit.csv"),
          row.names = FALSE, fileEncoding = "UTF-8")

if (any(audit$n != audit$n_unique_ids) ||
    any(!audit$donor_is_always_different) ||
    any(audit$all_values_differ_from_true %in% FALSE, na.rm = TRUE) ||
    any(!audit$distribution_preserved)) {
  stop("Manipulation audit failed. See manipulation_audit.csv.")
}

cat("Generated", length(list.files(prompt_root, recursive = TRUE, pattern = "\\.json$")),
    "prompt files and", nrow(manifest), "manifest rows.\n")
