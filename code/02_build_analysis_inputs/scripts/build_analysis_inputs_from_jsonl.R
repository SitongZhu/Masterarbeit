# install.packages(c("dplyr", "purrr", "jsonlite", "stringr", "tidyr"))
library(dplyr)
library(purrr)
library(jsonlite)
library(stringr)
library(tidyr)

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "data"))) {
  stop("Run this script from the code project root.")
}

# ==========================================
# 1. 参数 / 路径设置
# ==========================================
# 目录约定（相对脚本工作目录）：
#   HData/wave_list_for_llm_join_<variant>.rds
#   outcome/<variant>/                              ← 直接放 *.jsonl
#   或 outcome/<variant>/<single_subdir>/           ← 只嵌套一层时也兼容
# variant 形如 "1290"、"1290_original_scale"、"1500"、"1500_original_scale"
# 输出：analyse_<variant>.csv

hdata_dir   <- file.path(PROJECT_ROOT, "data", "intermediate_hdata")
outcome_dir <- file.path(PROJECT_ROOT, "data", "llm_outputs", "outcome")
analysis_input_dir <- file.path(PROJECT_ROOT, "data", "analysis_inputs")
dir.create(analysis_input_dir, showWarnings = FALSE, recursive = TRUE)

# 仅处理 nosft_*__prompt_w* 的 JSONL（与 build_prompt 输出一致）
jsonl_pattern <- "^nosft_.*\\.jsonl$"

# 你想要从 JSON 文件中提取的目标列（须含 JSONL 受访者键）
target_columns    <- c("id", "label", "predict")
survey_join_key   <- "lfdn"   # 调查表 / wave_list RDS 中的受访者键
jsonl_subject_col <- "id"     # JSONL 中的受访者键

# ==========================================
# 2. 工具函数
# ==========================================

# nosft_{LLM}__prompt_w{NN}.jsonl                  → variant = baseline
# nosft_{LLM}__prompt_w{NN}_baseline_notime.jsonl  → variant = baseline_notime
# nosft_{LLM}__prompt_w{NN}_tanchored.jsonl        → variant = tanchored
# nosft_{LLM}__prompt_w{NN}_trajectory.jsonl       → variant = trajectory
parse_nosft_jsonl_metadata <- function(file_name) {
  if (!grepl("^nosft_.+__prompt_w\\d+", file_name)) {
    return(list(
      llm_model = NA_character_,
      wave_info = NA_character_,
      prompt_variant = NA_character_
    ))
  }
  llm_model <- sub("^nosft_(.+?)__prompt_.*$", "\\1", file_name)
  m <- str_match(file_name, "__prompt_(w\\d+)([^\\.]*)\\.jsonl\\s*$")
  if (any(is.na(m[1L, ]))) {
    return(list(llm_model = llm_model, wave_info = NA_character_, prompt_variant = NA_character_))
  }
  wave_info <- m[1L, 2L]
  rest <- m[1L, 3L]
  prompt_variant <- if (is.na(rest) || !nzchar(rest)) "baseline" else sub("^_", "", rest)
  list(llm_model = llm_model, wave_info = wave_info, prompt_variant = prompt_variant)
}

labelled_classes <- c(
  "haven_labelled", "haven_labelled_spss", "labelled", "vctrs_vctr"
)

# 把 haven_labelled 列彻底剥成底层 numeric/character（class + 所有属性清空），
# 避免 bind_rows / left_join 中 vctrs 因属性差异报错。
strip_to_base <- function(x) {
  if (inherits(x, labelled_classes)) {
    attributes(x) <- NULL
  }
  x
}

# 把 haven_labelled 的值映射成其 labels 属性里的文本意义。
# 没有 labels 的 labelled 列退化为底层值的 character；非 labelled 列原样返回。
labelled_to_label_chr <- function(x) {
  if (!inherits(x, labelled_classes)) return(x)
  labs <- attr(x, "labels")
  raw <- x; attributes(raw) <- NULL
  if (is.null(labs) || length(labs) == 0L) return(as.character(raw))
  lab_codes <- labs; attributes(lab_codes) <- NULL
  lab_text  <- names(labs)
  out <- as.character(raw)
  ix <- match(raw, lab_codes)
  has <- !is.na(ix)
  out[has] <- lab_text[ix[has]]
  out
}

# 对一个 wave 的 dataframe：
#   - kp_* / pi_* 列：转成 label 文本（实际意义）
#   - 其他 labelled 列：剥成底层数值/字符
normalize_wave_df <- function(df) {
  nms <- names(df)
  for (i in seq_along(df)) {
    nm <- nms[[i]]
    x  <- df[[i]]
    if (grepl("^(kp|pi)", nm, ignore.case = TRUE)) {
      df[[i]] <- labelled_to_label_chr(x)
    } else {
      df[[i]] <- strip_to_base(x)
    }
  }
  df
}

# 去掉 kp{波次}_ / kpa{波次}_ 中的波次，只保留 kp_{后缀}
harmonize_wave_df_kp_columns <- function(df, wave_list_name) {
  if (!grepl("^w\\d+$", wave_list_name, ignore.case = TRUE)) return(df)
  wn <- suppressWarnings(as.integer(sub("^w", "", wave_list_name, ignore.case = TRUE)))
  if (is.na(wn)) return(df)
  nm <- names(df)
  kp_rx <- sprintf("^kpa?%d_(.+)$", wn)
  is_my_kp <- grepl(kp_rx, nm, perl = TRUE)
  is_any_kp <- grepl("^kpa?[0-9]+_", nm, perl = TRUE)
  drop_ix <- is_any_kp & !is_my_kp
  if (any(drop_ix)) df <- df[, !drop_ix, drop = FALSE]
  nm2 <- names(df)
  ix <- grepl(sprintf("^kpa?%d_(.+)$", wn), nm2, perl = TRUE)
  if (any(ix)) names(df)[ix] <- sub(sprintf("^kpa?%d_(.+)$", wn), "kp_\\1", nm2[ix], perl = TRUE)
  df
}

# 找到一个 variant 对应的、含 *.jsonl 的目录。
# JSONL 可以直接放在 outcome/<variant>/，也可以按模型放在任意子目录中；
# 后续会递归读取该 variant 下的所有文件。
resolve_jsonl_dir <- function(variant) {
  base <- file.path(outcome_dir, variant)
  if (!dir.exists(base)) return(NULL)

  files <- list.files(
    path = base,
    pattern = jsonl_pattern,
    full.names = TRUE,
    recursive = TRUE
  )
  if (length(files) == 0L) return(NULL)
  base
}

# 自动发现 variant：HData 下所有 wave_list_for_llm_join_<variant>.rds
discover_variants <- function() {
  files <- list.files(hdata_dir, pattern = "^wave_list_for_llm_join_.+\\.rds$", full.names = FALSE)
  sub("^wave_list_for_llm_join_(.+)\\.rds$", "\\1", files)
}

# ==========================================
# 3. 提取并清洗 LLM JSONL 数据
# ==========================================
extract_llm_data <- function(directory, pattern, extract_cols) {
  file_paths <- list.files(
    path = directory,
    pattern = pattern,
    full.names = TRUE,
    recursive = TRUE
  )
  file_paths <- file_paths[grepl("^nosft_.+__prompt_w\\d+", basename(file_paths), ignore.case = TRUE)]
  file_paths <- sort(file_paths)

  if (length(file_paths) == 0L) {
    stop("未找到符合 nosft_*__prompt_w* 的 JSONL：", directory)
  }
  duplicated_names <- unique(basename(file_paths)[duplicated(basename(file_paths))])
  if (length(duplicated_names) > 0L) {
    stop(
      "Duplicate JSONL basenames under ", directory, ": ",
      paste(duplicated_names, collapse = ", "),
      ". Keep one file per model/wave/prompt combination."
    )
  }

  combined_llm_df <- map_dfr(file_paths, function(file_path) {
    file_name <- basename(file_path)
    meta <- parse_nosft_jsonl_metadata(file_name)
    con <- file(file_path, open = "r", encoding = "UTF-8")
    on.exit(close(con), add = TRUE)
    df <- jsonlite::stream_in(con, verbose = FALSE)
    missing_columns <- setdiff(extract_cols, names(df))
    if (length(missing_columns)) {
      stop(file_name, " is missing required JSONL fields: ",
           paste(missing_columns, collapse = ", "))
    }
    if (!nrow(df)) stop("Empty generation file: ", file_name)
    numeric_id <- suppressWarnings(as.numeric(as.character(df[[jsonl_subject_col]])))
    if (any(!is.finite(numeric_id)) || anyDuplicated(numeric_id)) {
      stop("Missing, nonnumeric, or duplicate respondent IDs in ", file_name)
    }
    if (any(is.na(df$label) | !nzchar(trimws(as.character(df$label))))) {
      stop("Missing reference labels in ", file_name)
    }
    cols_to_keep <- extract_cols

    df %>%
      select(all_of(cols_to_keep)) %>%
      mutate(
        source_file = file_name,
        llm_model = meta$llm_model,
        wave_info = meta$wave_info,
        prompt_variant = meta$prompt_variant
      )
  })

  combined_llm_df
}

# ==========================================
# 4. 处理单个 variant
# ==========================================
process_variant <- function(variant) {
  message("==== Processing variant: ", variant, " ====")

  rds_basename  <- sprintf("wave_list_for_llm_join_%s.rds", variant)
  rds_file_path <- file.path(hdata_dir, rds_basename)
  if (!file.exists(rds_file_path)) {
    stop("找不到 RDS：", rds_file_path)
  }

  jsonl_dir <- resolve_jsonl_dir(variant)
  if (is.null(jsonl_dir)) {
    stop("找不到 ", variant, " 对应的 JSONL 目录（尝试过 outcome/", variant,
         "/ 与其一级子目录）。")
  }
  message("  RDS  : ", rds_file_path)
  message("  JSONL: ", jsonl_dir)

  llm_predictions_df <- extract_llm_data(
    directory = jsonl_dir,
    pattern = jsonl_pattern,
    extract_cols = target_columns
  )

  if (!jsonl_subject_col %in% names(llm_predictions_df)) {
    stop("JSONL 中缺少列 ", jsonl_subject_col, "（variant=", variant, "）。")
  }

  # JSONL 的 id 与 wave_list 的 lfdn 同一受访者
  llm_predictions_df[[survey_join_key]] <- suppressWarnings(
    as.numeric(llm_predictions_df[[jsonl_subject_col]])
  )
  llm_predictions_df[["rds_basename"]] <- rds_basename
  llm_predictions_df[["variant"]]      <- variant

  bad_wave <- is.na(llm_predictions_df[["wave_info"]]) |
              llm_predictions_df[["wave_info"]] == ""
  if (any(bad_wave)) {
    warning(sum(bad_wave), " 行 LLM 结果无法从文件名解析 wave_info，已剔除（variant=",
            variant, "）。")
    llm_predictions_df <- llm_predictions_df[!bad_wave, , drop = FALSE]
  }

  # ---- 读 RDS，合并波次内列名 ----
  original_wave_list <- readRDS(rds_file_path)
  wl_names <- names(original_wave_list)
  original_wave_list <- stats::setNames(
    Map(
      function(nm, d) normalize_wave_df(harmonize_wave_df_kp_columns(d, nm)),
      wl_names, original_wave_list
    ),
    wl_names
  )

  w0 <- original_wave_list[[1L]]
  if (!survey_join_key %in% names(w0)) {
    stop("RDS 中缺少键列 ", survey_join_key, "（variant=", variant, "）。")
  }

  # 展平 list → 长 dataframe
  # Attach the explicitly designated preceding survey wave before joining any
  # generations. The previous human state must come from the panel rather than
  # from lagging available output rows.
  original_combined_df <- bind_rows(original_wave_list, .id = "wave_id_from_list")
  # Historical files for unselected waves are reported but never enter this task.
  outside_waves <- !llm_predictions_df$wave_info %in% names(original_wave_list)
  if (any(outside_waves)) {
    message("Excluding ", sum(outside_waves), " archived rows from unselected waves.")
    llm_predictions_df <- llm_predictions_df[!outside_waves, , drop = FALSE]
  }
  reference_check <- llm_predictions_df %>%
    left_join(
      original_combined_df %>% transmute(
        lfdn, wave_info = wave_id_from_list, survey_reference = as.character(outcome)
      ),
      by = c("lfdn", "wave_info")
    )
  if (any(is.na(reference_check$survey_reference))) {
    stop("Generation IDs do not match the selected survey records for ", variant)
  }
  if (any(str_squish(as.character(reference_check$label)) !=
          str_squish(reference_check$survey_reference))) {
    stop("Archived reference labels disagree with the survey outcomes for ", variant)
  }
  ordered_waves <- names(original_wave_list)
  ordered_waves <- ordered_waves[order(suppressWarnings(
    as.integer(sub("^.*?([0-9]+).*$", "\\1", ordered_waves))
  ))]
  previous_wave_map <- tibble(
    wave_id_from_list = ordered_waves,
    previous_wave_id = c(NA_character_, head(ordered_waves, -1L))
  )

  duplicate_human_keys <- original_combined_df %>%
    count(.data[[survey_join_key]], wave_id_from_list, name = "n") %>%
    filter(n > 1L)
  if (nrow(duplicate_human_keys) > 0L) {
    stop("Duplicate respondent-wave keys in survey wave list for variant ", variant)
  }
  previous_human_lookup <- original_combined_df %>%
    transmute(
      !!survey_join_key := .data[[survey_join_key]],
      previous_wave_id = wave_id_from_list,
      vorwelle_label = as.character(outcome)
    )
  original_combined_df <- original_combined_df %>%
    left_join(previous_wave_map, by = "wave_id_from_list") %>%
    left_join(
      previous_human_lookup,
      by = c(survey_join_key, "previous_wave_id")
    )

  # 按 lfdn + wave 合并
  final_joined_df <- left_join(
    original_combined_df,
    llm_predictions_df,
    by = c("lfdn", "wave_id_from_list" = "wave_info")
  )

  # ---- vorwelle：每组内按波次顺序取上一行的 label / predict ----
  # Attach the prediction from the same designated preceding wave. This keeps
  # self-trajectory diagnostics explicit and prevents available-row lagging from
  # silently jumping over an absent generation.
  duplicate_prediction_keys <- llm_predictions_df %>%
    count(
      .data[[survey_join_key]], wave_info, llm_model, prompt_variant,
      name = "n"
    ) %>%
    filter(n > 1L)
  if (nrow(duplicate_prediction_keys) > 0L) {
    stop("Duplicate model respondent-wave keys for variant ", variant)
  }
  previous_prediction_lookup <- llm_predictions_df %>%
    transmute(
      !!survey_join_key := .data[[survey_join_key]],
      previous_wave_id = wave_info,
      llm_model,
      prompt_variant,
      vorwelle_predict = predict
    )
  final_joined_df <- final_joined_df %>%
    left_join(
      previous_prediction_lookup,
      by = c(
        survey_join_key,
        "previous_wave_id",
        "llm_model",
        "prompt_variant"
      )
    )

  out_path <- file.path(analysis_input_dir, sprintf("analyse_%s.csv", variant))
  write.csv(final_joined_df, out_path, row.names = FALSE, fileEncoding = "UTF-8")
  message("  -> wrote ", out_path, " (", nrow(final_joined_df), " rows)")

  invisible(final_joined_df)
}

# ==========================================
# 5. 主流程：自动发现并依次处理所有 variants
# ==========================================
variants <- discover_variants()
if (length(variants) == 0L) {
  stop("在 ", hdata_dir, " 中未找到 wave_list_for_llm_join_*.rds")
}
message("Discovered variants: ", paste(variants, collapse = ", "))

for (v in variants) {
  process_variant(v)
  invisible(gc())
}
