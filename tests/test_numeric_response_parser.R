#!/usr/bin/env Rscript
code <- normalizePath("code", winslash = "/", mustWork = TRUE)
setwd(code)
sys.source("ensure_utf8_locale.R", envir = new.env(parent = globalenv()))
Sys.setenv(ANALYSIS_INPUT_DIR = tempdir(), EVALUATION_OUTPUT_ROOT = tempdir())

load_matcher <- function(path) {
  env <- new.env(parent = globalenv())
  expressions <- parse(path, encoding = "UTF-8")
  for (expression in expressions) {
    if (is.call(expression) && identical(expression[[1]], as.name("<-")) &&
        identical(expression[[2]], as.name("match_to_category"))) {
      eval(expression, envir = env)
      return(env)
    }
    # Load definitions and packages, but stop before any data analysis.
    eval(expression, envir = env)
  }
  stop("No category matcher found: ", path)
}

cases <- c("1", "11", "Antwort: 7.", "`3`", "(4)", "-1", "3.5",
           "3,5", "3e2", "3E+2", "3e-2", "+3", "\u22123", "\u20133",
           "abc3", "3abc", "\u00e93", "12", "111", "2018-11-06",
           "10.000", "-1; Antwort: 6", "3.5, Antwort: 4", "3e2; 7",
           "Antwort: 2, mit Begruendung", "", NA_character_)
expected <- c("1", "11", "7", "3", "4", rep(NA_character_, 16),
              "6", "4", "7", "2", NA_character_, NA_character_)
stopifnot(length(cases) == length(expected))
for (script in c("analyse_all_variants.R", "common_sample_accuracy.R")) {
  env <- load_matcher(file.path("03_evaluation/scripts", script))
  dict <- env$build_label_dict(as.character(1:11))
  actual <- env$match_to_category(cases, dict)
  stopifnot(identical(actual, expected))
  dict7 <- env$build_label_dict(as.character(1:7))
  stopifnot(identical(env$match_to_category(c("11", "11; 7"), dict7),
                      c(NA_character_, "7")))
}
cat("Numeric parser boundary regressions passed for both evaluation entry points.\n")
