#!/usr/bin/env Rscript
# Regressions for failures found during the thesis/code audit.
local({
  repository <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  original_ctype <- Sys.getlocale("LC_CTYPE")
  original_collate <- Sys.getlocale("LC_COLLATE")
  original_contrasts <- getOption("contrasts")
  on.exit({Sys.setlocale("LC_CTYPE", original_ctype); Sys.setlocale("LC_COLLATE", original_collate);
           options(contrasts=original_contrasts)}, add=TRUE)
  stopifnot(dir.exists(file.path(repository, "code")))
  # Match the pipeline's locale initialization when this test runs directly.
  source(file.path(repository, "code/ensure_utf8_locale.R"), encoding="UTF-8")
  temporary <- tempfile("thesis_contracts_")
  dir.create(file.path(temporary, "data"), recursive = TRUE)
  dir.create(file.path(temporary, "03_evaluation/scripts"), recursive = TRUE)
  stopifnot(file.copy(file.path(repository, "code/03_evaluation/scripts/numeric_response_parser.R"),
                     file.path(temporary, "03_evaluation/scripts/numeric_response_parser.R")))
  on.exit({setwd(repository); unlink(temporary, recursive = TRUE)}, add = TRUE)
  setwd(temporary)
  expect_error <- function(expr, pattern) {
    error <- tryCatch({force(expr); NULL}, error = identity)
    stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
  }
  # Definitions are loaded without invoking a dataset-level main loop.
  load_before <- function(relative, marker, environment) {
    lines <- readLines(file.path(repository, relative), encoding = "UTF-8")
    end <- grep(marker, lines)[1L] - 1L
    stopifnot(is.finite(end))
    eval(parse(text = lines[seq_len(end)]), envir = environment)
  }
  builder <- new.env(parent = globalenv())
  load_before("code/02_build_analysis_inputs/scripts/build_analysis_inputs_from_jsonl.R",
              "^variants <- discover_variants", builder)
  folder <- file.path(temporary, "data/llm_outputs/outcome/1290")
  dir.create(folder, recursive = TRUE)
  path <- file.path(folder, "nosft_test__prompt_w10.jsonl")
  writeLines('{"id":1,"label":"A"}', path)
  expect_error(builder$extract_llm_data(folder, "\\.jsonl$", c("id","label","predict")), "required JSONL fields")
  writeLines(c('{"id":1,"label":"A","predict":"A"}',
               '{"id":"1.0","label":"A","predict":"B"}'), path)
  expect_error(builder$extract_llm_data(folder, "\\.jsonl$", c("id","label","predict")), "duplicate respondent")
  writeLines('{"id":"not_numeric","label":"A","predict":"A"}', path)
  expect_error(builder$extract_llm_data(folder, "\\.jsonl$", c("id","label","predict")), "nonnumeric")
  dir.create(file.path(temporary, "data/intermediate_hdata"))
  saveRDS(list(w10 = data.frame(lfdn=1, outcome="A")),
          file.path(temporary, "data/intermediate_hdata/wave_list_for_llm_join_1290.rds"))
  writeLines('{"id":1,"label":"B","predict":"A"}', path)
  expect_error(builder$process_variant("1290"), "reference labels disagree")
  writeLines('{"id":2,"label":"A","predict":"A"}', path)
  expect_error(builder$process_variant("1290"), "do not match")
  writeLines('{"id":1,"label":"A","predict":"A"}', path)
  joined <- builder$process_variant("1290")
  stopifnot(nrow(joined)==1L, joined$label=="A")
  # Unicode must remain text rather than introducing numeric <U+....> artifacts.
  unicode_prediction <- "f\u00fcr Gr\u00f6\u00dfe, sp\u00e4ter 7"
  writeLines(enc2utf8(sprintf('{"id":1,"label":"A","predict":"%s"}', unicode_prediction)),
             path, useBytes=TRUE)
  builder$process_variant("1290")
  saved <- read.csv(file.path(temporary, "data/analysis_inputs/analyse_1290.csv"),
                    fileEncoding="UTF-8", stringsAsFactors=FALSE)
  stopifnot(identical(saved$predict, unicode_prediction),
            !grepl("<U+", saved$predict, fixed=TRUE))

  # Evaluate just the pure metric functions from the ordinal baseline source.
  ordinal <- new.env(parent = globalenv())
  expressions <- parse(file.path(repository, "code/03_evaluation/scripts/generate_ordinal_statistical_baselines.R"))
  required <- c("metric_summary", "compare_covariates_only", "compare_lag")
  for (expression in expressions) {
    if (is.call(expression) && identical(expression[[1]], as.name("<-")) &&
        as.character(expression[[2]])[1] %in% required) eval(expression, ordinal)
  }
  rows <- tibble::tibble(lfdn=as.character(1:3), wave="w14", wave_order=14L,
    model="test", prompt_variant="baseline_notime", prompt_label="No-time baseline",
    label_cat=c("1","7","4"), predict_cat=c("1",NA,"6"),
    previous_wave_modal_category="1", previous_wave_modal_correct=c(TRUE,FALSE,FALSE),
    carry_forward_correct=c(TRUE,FALSE,FALSE))
  predictions <- tibble::tibble(lfdn=as.character(1:3), wave="w14", wave_order=14L,
    ordinal_pred_cat=c("1","1","4"), ordinal_model="test")
  metrics <- ordinal$compare_covariates_only(rows, predictions, "original_scale")
  stopifnot(metrics$n_total==3L, metrics$n_ordinal_metric==2L,
            metrics$accuracy_prompt==1/3, metrics$accuracy_ordinal==2/3,
            metrics$prompt_mae==1, metrics$ordinal_mae==0,
            metrics$prompt_within_one==.5, metrics$ordinal_within_one==1)
  rows$prompt_variant <- "trajectory"
  metrics <- ordinal$compare_lag(rows, predictions, "original_scale")
  stopifnot(metrics$n_ordinal_metric==2L, metrics$trajectory_mae==1,
            metrics$ordinal_mae==0, metrics$accuracy_trajectory==1/3)
  # Full-data factor levels must not masquerade as levels observed in training.
  core <- new.env(parent=globalenv())
  if (.Platform$OS.type=="windows") Sys.setlocale("LC_COLLATE", "English_United States.utf8")
  options(contrasts=c("contr.sum", "contr.poly"))
  load_before("code/03_evaluation/scripts/analyse_all_variants.R", "^csv_files <-", core)
  stopifnot(Sys.getlocale("LC_COLLATE")=="C",
            identical(getOption("contrasts"), c("contr.treatment", "contr.poly")),
            levels(factor(c("gut", "Interview abgebrochen")))[1]=="Interview abgebrochen",
            core$modal_value(c("gut", "Interview abgebrochen"))=="Interview abgebrochen")
  levels_all <- c("A", "B", "future_only", "__MISSING__")
  train <- data.frame(x=factor(c("A","A","B"), levels=levels_all))
  test <- data.frame(x=factor(c("B","future_only","__MISSING__"), levels=levels_all))
  fit <- list(xlevels=list(x=levels_all))
  aligned <- core$align_newdata_levels(test, fit, train)
  stopifnot(identical(as.character(aligned$x), c("B","A","A")),
            identical(levels(aligned$x), levels_all))
  cat("PASS: JSONL, Unicode, reference linkage, matched distances, unseen training levels, and factor references.\n")
})
