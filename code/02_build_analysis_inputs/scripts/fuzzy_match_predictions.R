#!/usr/bin/env Rscript
# fuzzy_match.R
# 就地（in-place）修改 analyse_<variant>.csv：
#   - 用 fuzzy 把 predict / vorwelle_predict 规范化到 label 列里出现过的类别
#   - 删除无法匹配的当前预测；保留其他列和剩余行的顺序
#   - 数字 Likert (original-scale) 跳过——精确数字提取已足够
#
# 处理"_"与空格的不一致：切词时按 [^a-z0-9]+ 分隔，下划线/空格/标点都视为
# 分隔符，所以 "Vorrang_fuer_Bekaempfung_des_Klimawandels" 与
# "Vorrang fuer Bekaempfung des Klimawandels" 会切到同一组 token。
# 同时也修 Mojibake (Ã¼/Ã¤/Ã¶ → ue/ae/oe) 和 umlaut (ü/ä/ö → ue/ae/oe)。

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(stringdist)
})

PROJECT_ROOT    <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "data"))) {
  stop("Run this script from the code project root.")
}
ANALYSIS_INPUT_DIR <- file.path(PROJECT_ROOT, "data", "analysis_inputs")
FUZZY_THRESHOLD <- 0.85   # Jaro-Winkler 阈值（命中算"模糊匹配上"）
MIN_TOKEN_LEN   <- 4L

# -----------------------------------------------------------------------------
# 工具
# -----------------------------------------------------------------------------
clean_text <- function(x) {
  x <- as.character(x)
  x <- str_squish(x)
  is_empty <- !is.na(x) & x == ""
  x[is_empty] <- NA_character_
  x
}

normalize_str <- function(s) {
  s <- tolower(as.character(s))
  # Mojibake (UTF-8 bytes read as Latin-1)
  s <- gsub("ã¼", "ue", s, fixed = TRUE)
  s <- gsub("ã¤", "ae", s, fixed = TRUE)
  s <- gsub("ã¶", "oe", s, fixed = TRUE)
  # 标准 Unicode umlaut / Eszett
  s <- gsub("ä", "ae", s, fixed = TRUE)
  s <- gsub("ö", "oe", s, fixed = TRUE)
  s <- gsub("ü", "ue", s, fixed = TRUE)
  s <- gsub("ß", "ss", s, fixed = TRUE)
  # 剥离 "1. " / "2) " / "3:" 之类前缀编号
  s <- sub("^\\s*[0-9]+\\s*[\\.\\):]\\s*", "", s, perl = TRUE)
  s
}

content_tokens <- function(s, min_len = MIN_TOKEN_LEN) {
  s <- normalize_str(s)
  toks <- unlist(strsplit(s, "[^a-z0-9]+", perl = TRUE))
  toks <- toks[!is.na(toks) & nchar(toks) >= min_len]
  unique(toks)
}

build_label_dict <- function(label_col) {
  cats <- clean_text(label_col)
  cats <- cats[!is.na(cats)]
  cats <- cats[nzchar(cats, keepNA = FALSE)]
  cats <- unique(cats)
  if (length(cats) == 0L) {
    return(list(cats = character(0), tokens = list(),
                ordered = character(0), is_numeric = FALSE))
  }
  if (all(grepl("^-?\\d+(\\.\\d+)?$", cats))) {
    ordered <- cats[order(as.numeric(cats))]
    return(list(cats = ordered,
                tokens = setNames(as.list(ordered), ordered),
                ordered = ordered, is_numeric = TRUE))
  }
  tokens_per <- lapply(cats, content_tokens)
  names(tokens_per) <- cats
  freq <- table(unlist(tokens_per))
  distinguishing <- lapply(tokens_per, function(toks) {
    if (length(toks) == 0L) return(character(0))
    uniq <- toks[as.integer(freq[toks]) == 1L]
    if (length(uniq) == 0L) toks else uniq
  })
  list(cats = cats, tokens = distinguishing,
       ordered = sort(cats), is_numeric = FALSE)
}

# 给定一组唯一词，与 dict 各类的独占词做 stringdist (Jaro-Winkler)，
# 返回 word → best_cat 映射（best_sim < threshold 的为 NA）。
build_word_lookup <- function(unique_words, dict, threshold) {
  all_toks  <- unlist(dict$tokens, use.names = FALSE)
  tok_to_cat <- rep(names(dict$tokens), lengths(dict$tokens))
  if (length(unique_words) == 0L || length(all_toks) == 0L) {
    return(setNames(character(0), character(0)))
  }
  dmat <- stringdistmatrix(unique_words, all_toks, method = "jw", p = 0.1)
  sims <- 1 - dmat
  best_j   <- max.col(sims, ties.method = "first")
  best_sim <- sims[cbind(seq_along(unique_words), best_j)]
  best_cat <- tok_to_cat[best_j]
  best_cat[best_sim < threshold] <- NA_character_
  setNames(best_cat, unique_words)
}

# 把整列 text 模糊匹配到 dict$cats，未命中返回 NA。
match_to_category_fuzzy <- function(text, dict, threshold = FUZZY_THRESHOLD) {
  text_c <- clean_text(text)
  n <- length(text_c)
  out <- rep(NA_character_, n)
  if (length(dict$cats) == 0L || n == 0L) return(out)

  text_safe <- text_c
  text_safe[is.na(text_safe)] <- ""
  text_n <- normalize_str(text_safe)
  per_row_words <- strsplit(text_n, "[^a-z0-9]+", perl = TRUE)
  per_row_words <- lapply(per_row_words, function(w) {
    w[!is.na(w) & nchar(w) >= MIN_TOKEN_LEN]
  })

  unique_words <- unique(unlist(per_row_words, use.names = FALSE))
  message("    fuzzy: ", length(unique_words), " unique tokens to score ...")
  word2cat <- build_word_lookup(unique_words, dict, threshold)

  cats <- dict$cats
  K <- length(cats)
  for (i in seq_len(n)) {
    ws <- per_row_words[[i]]
    if (length(ws) == 0L) next
    hits <- word2cat[ws]
    hits <- hits[!is.na(hits)]
    if (length(hits) == 0L) next
    tab <- tabulate(match(hits, cats), nbins = K)
    if (max(tab) == 0L) next
    out[i] <- cats[which.max(tab)]
  }
  out
}

# -----------------------------------------------------------------------------
# 主流程：就地覆盖 analyse_<variant>.csv
# -----------------------------------------------------------------------------
process_csv_inplace <- function(csv_path) {
  variant <- sub("^analyse_(.+)\\.csv$", "\\1", basename(csv_path))
  message("==== in-place fuzzy: ", variant, " ====")

  # 用 base R 读，保持 write.csv 的"首列空表头 + 数字行索引"格式
  df <- read.csv(csv_path, stringsAsFactors = FALSE, check.names = FALSE,
                 fileEncoding = "UTF-8", na.strings = c("", "NA"))
  # write.csv 的首列在读回时被命名为 "X"。识别并保留行索引值，最后写回时复用。
  has_idx <- ncol(df) > 0L && names(df)[1] == "X"
  if (has_idx) {
    row_idx <- df[[1L]]
    df <- df[, -1L, drop = FALSE]
  } else {
    row_idx <- NULL
  }

  if (!"label" %in% names(df) || !"predict" %in% names(df)) {
    message("  缺 label / predict 列，跳过。"); return(invisible(NULL))
  }

  # 关键清洗：label / vorwelle_label 在 csv 里末尾常带 "\n"（来自 jsonl 原始
  # 字符串），导致下游 predict == label 永远不成立。先 trim 干净再写回。
  df$label <- clean_text(df$label)
  if ("vorwelle_label" %in% names(df)) {
    df$vorwelle_label <- clean_text(df$vorwelle_label)
  }

  dict <- build_label_dict(df$label)
  if (length(dict$cats) == 0L) {
    message("  空 label，跳过。"); return(invisible(NULL))
  }
  if (dict$is_numeric) {
    message("  数字 Likert，跳过（精确数字匹配已足够）。")
    return(invisible(NULL))
  }
  message("  text label, ", length(dict$cats), " cats: ",
          paste(dict$cats, collapse = " | "))

  before_na_pred <- sum(is.na(df$predict))
  message("  fuzzy matching predict (", nrow(df), " rows) ...")
  df$predict <- match_to_category_fuzzy(df$predict, dict)
  after_na_pred <- sum(is.na(df$predict))
  message("  predict NA: ", before_na_pred, " -> ", after_na_pred)

  if ("vorwelle_predict" %in% names(df)) {
    before_na_vw <- sum(is.na(df$vorwelle_predict))
    message("  fuzzy matching vorwelle_predict ...")
    df$vorwelle_predict <- match_to_category_fuzzy(df$vorwelle_predict, dict)
    after_na_vw <- sum(is.na(df$vorwelle_predict))
    message("  vorwelle_predict NA: ", before_na_vw, " -> ", after_na_vw)
  }

  # 删除 predict 为 NA 的行（fuzzy 未能匹配上的）
  n_before <- nrow(df)
  keep <- !is.na(df$predict)
  audit_dir <- file.path(PROJECT_ROOT, "outputs", "evaluation", "manuscript", "audits")
  dir.create(audit_dir, recursive = TRUE, showWarnings = FALSE)
  audit_keys <- intersect(c("llm_model", "prompt_variant", "wave_id_from_list"), names(df))
  retention <- dplyr::as_tibble(df) %>%
    dplyr::mutate(parsed_before_retention = keep) %>%
    dplyr::group_by(dplyr::across(dplyr::all_of(audit_keys))) %>%
    dplyr::summarise(attempted = dplyr::n(), retained = sum(parsed_before_retention),
                     removed = attempted - retained, .groups = "drop")
  write.csv(retention, file.path(audit_dir, paste0("grouped_retention_", variant, ".csv")),
            row.names = FALSE, fileEncoding = "UTF-8")
  df <- df[keep, , drop = FALSE]
  if (!is.null(row_idx)) row_idx <- row_idx[keep]
  message("  dropped NA predict rows: ", n_before - nrow(df),
          " (kept ", nrow(df), "/", n_before, ")")

  # 还原首列行索引（与原文件格式一致）
  if (has_idx) {
    out_df <- data.frame(row.names = NULL,
                         setNames(list(row_idx), ""),
                         df, check.names = FALSE,
                         stringsAsFactors = FALSE)
    write.csv(out_df, csv_path, row.names = FALSE, na = "NA",
              fileEncoding = "UTF-8")
  } else {
    write.csv(df, csv_path, row.names = FALSE, na = "NA",
              fileEncoding = "UTF-8")
  }
  message("  -> overwrote ", csv_path)
}

# -----------------------------------------------------------------------------
csv_files <- list.files(ANALYSIS_INPUT_DIR, pattern = "^analyse_.+\\.csv$",
                        full.names = TRUE)
if (length(csv_files) == 0L) stop("未找到 analyse_*.csv。")

for (f in csv_files) {
  process_csv_inplace(f)
}
message("fuzzy_match.R complete.")
