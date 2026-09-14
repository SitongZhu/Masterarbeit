#!/usr/bin/env Rscript
# Reproduce the native-encoding condition behind the historical CSV corruption.
local({
  original <- Sys.getlocale("LC_CTYPE")
  on.exit(suppressWarnings(Sys.setlocale("LC_CTYPE", original)), add=TRUE)
  legacy <- if (.Platform$OS.type == "windows") "Chinese_China.936" else "C"
  suppressWarnings(Sys.setlocale("LC_CTYPE", legacy))
  source("code/ensure_utf8_locale.R")
  stopifnot(isTRUE(l10n_info()[["UTF-8"]]))
  source("tests/regression_contracts.R", encoding="UTF-8")
})
