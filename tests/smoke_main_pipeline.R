#!/usr/bin/env Rscript
# Exercises the actual four prompt builders, joins, cleaner, and accuracy module.
# All respondents and input .dta files are invented in a temporary directory.
local({
  stopifnot(dir.exists("code"))
  repository <- normalizePath(getwd(), winslash = "/")
  temporary <- tempfile("thesis_main_smoke_")
  project <- file.path(temporary, "code")
  dir.create(project, recursive = TRUE)
  on.exit({ setwd(repository); unlink(temporary, recursive = TRUE) }, add = TRUE)
  files <- list.files(file.path(repository, "code"), pattern = "\\.R$",
                      recursive = TRUE, full.names = TRUE)
  files <- files[!grepl("/(data|outputs)/", files)]
  for (file in files) {
    relative <- substring(file, nchar(file.path(repository, "code")) + 2L)
    destination <- file.path(project, relative)
    dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(file, destination))
  }
  raw_dir <- file.path(project, "data", "raw_survey", "ZA6838_v6-0-0.dta")
  dir.create(raw_dir, recursive = TRUE)
  n <- 12L
  ids <- 900000 + seq_len(n)
  file_map <- c(
    "ZA6838_w1to9_sA_v6-0-0.dta",
    paste0("ZA6838_w", 10:21, "_sA_v6-0-0.dta"),
    "ZA7728_v1-0-0.dta", "ZA7729_v1-0-0.dta", "ZA7730_v1-0-0.dta",
    "ZA7731_sA_v1-0-0.dta", "ZA7732_sA_v1-0-0.dta",
    "ZA7733_sA_v1-0-0.dta", "ZA10117_w28_sA_v2-0-0.dta",
    "ZA7961_wa5_sA_v1-0-0.dta", "ZA6838_wa2_sA_v6-0-0.dta"
  )
  for (index in seq_along(file_map)) {
    wave <- if (index == 1L) 1:9 else if (index <= 20L) index + 8L else 5L
    d <- data.frame(lfdn = as.double(ids), field_start = rep("2020-01-01", n),
                    field_end = rep("2020-01-15", n))
    for (w in c("x", as.character(wave))) {
      shift <- if (w == "x") 0L else as.integer(w)
      for (suffix in c("010", "020", "1130", "1290", "1500", "780", "2320",
                        "011", "060", "820", "2280", "2290s", "2591")) {
        count <- if (suffix == "1290") 7L else if (suffix == "1500") 11L else 3L
        values <- as.double((seq_len(n) + shift - 1L) %% count + 1L)
        labs <- setNames(as.double(seq_len(count)), paste0("Synthetic ", seq_len(count)))
        if (suffix == "2290s") {
          values <- as.double(1970 + seq_len(n)); labs <- NULL
        }
        if (suffix == "2591") labs <- c("unter 500 Euro" = 1, "500 bis unter 750 Euro" = 2,
                                        "750 bis unter 1000 Euro" = 3)
        if (suffix == "2280") {
          values <- as.double(seq_len(n) %% 2L + 1L)
          labs <- c("maennlich" = 1, "weiblich" = 2)
        }
        if (suffix == "2320") labs <- c("Hauptschulabschluss" = 1,
                                         "Realschulabschluss" = 2, "Abitur" = 3)
        d[[paste0("kp", w, "_", suffix)]] <- haven::labelled(values, labs, label = paste("Synthetic", suffix))
      }
    }
    haven::write_dta(d, file.path(raw_dir, file_map[[index]]))
  }
  setwd(project)
  sys.source("run_01_generate_prompts.R", envir = new.env(parent = globalenv()))
  variants <- c("1290", "1290_original_scale", "1500", "1500_original_scale")
  total_prompts <- 0L
  for (variant in variants) {
    prompt_files <- list.files(file.path("outputs", "prompts", variant),
                              pattern = "\\.json$", full.names = TRUE)
    stopifnot(length(prompt_files) == if (startsWith(variant, "1290")) 31L else 27L)
    metadata <- readRDS(file.path("data", "intermediate_hdata",
                                  paste0("wave_column_metadata_", variant, ".rds")))
    first <- metadata[[1L]]
    outcome_column <- paste0("kp10_", sub("_original_scale$", "", variant))
    dictionary <- first$value_labels_json[first$survey_column == outcome_column]
    stopifnot(length(dictionary)==1L, !is.na(dictionary),
              grepl("Synthetic 1", dictionary, fixed=TRUE))
    out_dir <- file.path("data", "llm_outputs", "outcome", variant, "synthetic-model")
    dir.create(out_dir, recursive = TRUE)
    for (path in prompt_files) {
      prompt <- jsonlite::fromJSON(path)
      stopifnot(setequal(names(prompt), c("id", "instruction", "input", "output")),
                nrow(prompt) == n, !anyDuplicated(prompt$id),
                setequal(as.numeric(prompt$id), ids), all(trimws(prompt$input) == ""),
                all(nzchar(prompt$instruction)))
      # Perfect predictions except one invalid response per file.
      response <- as.character(prompt$output)
      response[1] <- "synthetic_unparseable"
      records <- data.frame(id = prompt$id, label = prompt$output, predict = response)
      # Missing prior-wave generation must not change the designated prior wave.
      if (basename(path) == "prompt_w14_trajectory.json") records <- records[-2, ]
      destination <- file.path(out_dir, paste0("nosft_synthetic-model__", sub("\\.json$", ".jsonl", basename(path))))
      con <- file(destination, "w", encoding = "UTF-8")
      jsonlite::stream_out(records, con, verbose = FALSE)
      close(con)
      total_prompts <- total_prompts + 1L
    }
  }
  sys.source("run_02a_build_and_clean_analysis_inputs.R", envir = new.env(parent = globalenv()))
  # Load function definitions without executing the heavy full analysis loop.
  lines <- readLines("03_evaluation/scripts/analyse_all_variants.R", encoding = "UTF-8", warn = FALSE)
  cut <- grep("^csv_files <-", lines)[1] - 1L
  stopifnot(is.finite(cut))
  evaluation <- new.env(parent = globalenv())
  eval(parse(text = lines[seq_len(cut)]), envir = evaluation)
  for (variant in variants) {
    path <- file.path("data", "analysis_inputs", paste0("analyse_", variant, ".csv"))
    stopifnot(file.exists(path))
    joined <- read.csv(path, stringsAsFactors = FALSE)
    target <- joined[joined$lfdn == ids[2] & joined$wave_id_from_list == "w15" &
                       !is.na(joined$prompt_variant) & joined$prompt_variant == "trajectory", ]
    stopifnot(nrow(target) == 1L, target$previous_wave_id == "w14",
              !is.na(target$vorwelle_label), is.na(target$vorwelle_predict))
    raw <- evaluation$prepare_raw(path)
    dir <- file.path("outputs", "evaluation", paste0("analysis_", variant))
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    evaluation$run_module_accuracy(raw, dir)
    metrics <- read.csv(file.path(dir, "accuracy_summary.csv"))
    metrics <- metrics[!is.na(metrics$model) & metrics$model == "synthetic-model", ]
    stopifnot(nrow(metrics) > 0L, all(metrics$accuracy_parsed == 1))
    if (grepl("original_scale", variant)) {
      stopifnot(all(metrics$n_correct == metrics$n_total - 1L),
                all(metrics$n_parsed_predict == metrics$n_total - 1L))
    } else {
      # The existing grouped cleaner drops unparseable predictions in place.
      stopifnot(all(metrics$n_correct == metrics$n_total), all(metrics$accuracy == 1),
                all(metrics$n_total %in% c(n - 1L, n - 2L)))
    }
  }
  cat("PASS:", total_prompts, "prompt files, four JSONL joins/cleaning runs, designated lag checks, and accuracy metrics.\n")
})
