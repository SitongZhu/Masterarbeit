# R's native text conversion must not turn umlauts into numeric <U+....> tokens.
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  candidates <- if (.Platform$OS.type == "windows") {
    c("English_United States.utf8", ".UTF-8")
  } else {
    c("C.UTF-8", "en_US.UTF-8")
  }
  for (candidate in candidates) {
    suppressWarnings(try(Sys.setlocale("LC_CTYPE", candidate), silent=TRUE))
    if (isTRUE(l10n_info()[["UTF-8"]])) break
  }
}
if (!isTRUE(l10n_info()[["UTF-8"]])) {
  stop("A UTF-8 R locale is required. Configure LC_CTYPE before running the thesis pipeline.")
}
