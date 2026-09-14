#!/usr/bin/env Rscript
if (!dir.exists("code")) stop("Run from the repository root.")
files <- unlist(lapply(c("code", "setup", "tests"),
                      list.files, pattern = "\\.R$", recursive = TRUE, full.names = TRUE))
files <- files[!grepl("/(data|outputs)/", files)]
for (path in files) parse(path, encoding = "UTF-8")
cat("Parsed", length(files), "R source files successfully.\n")
