#!/usr/bin/env Rscript
# =============================================================================
# All-in-one script (sequential pipeline):
#   1) read_dta_select_columns.R   — read requested columns per wave → daten_liste
#   2) select_waves_filter_outcome.R — select waves + build/filter outcome → w{n}
#   3) build_prompt_from_waves.R   — build prompt JSON from w{n}
#
# Traceability: next to wave_list_for_llm_join.rds, also writes wave_column_metadata.rds
#   (survey_column, harmonized_name, var_label, value_labels_json per column).
#   Prompt JSON records remain instruction / input / output / id only.
#
# Edit mainly:
#   - columns_wave_suffix: predictor suffixes to read (e.g. "010","020","2320" ...)
#   - waves_to_use: wave numbers only, e.g. c(10,14,15,22)
#   - outcome_suffix: outcome column suffix (e.g. "1500")
#   - optional aggregate labels (prompt wording): columns named values_<Name> in outcome_groups (names drive prompt text)
#   - model target: raw survey code on the numeric scale (not aggregated to those labels)
#   - outcome_question: question text (manual)
#
# Other parameters have defaults; change only if needed.
#
# personal_info: merged by lfdn into each wave; column prefix personal_info_col_prefix (default pi_).
# =============================================================================

library(haven)
library(dplyr)
library(labelled)
library(jsonlite)
library(glue)

PROJECT_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
if (!dir.exists(file.path(PROJECT_ROOT, "data"))) {
  stop("Run this script from the code project root.")
}
VARIANT <- "1500_original_scale"

# -----------------------------------------------------------------------------
# 0. User-editable parameters
# -----------------------------------------------------------------------------

# Predictors: suffixes only (reads kpx_* and kp{n}_*)
columns_wave_suffix <- c("010","020","1130","1500","1290","780","2320","011","060","820")

# Which waves to use (numbers only)
waves_to_use <- c(10, 14, 15, 22, 23, 25, 26)

# Outcome variable suffix (column names kp{n}_{suffix} within each wave)
outcome_suffix <- "1500"

# outcome_question (set manually)
outcome_question <- "In der Politik reden die Leute häufig von „links“ und „rechts“. Wo würden Sie sich selbst einordnen?"

# Optional override for the enumerated raw-code list in the prompt.
# If non-empty, this text replaces the numbered-choice block that starts with
# "Zulässige Rohcodes gemäß Wertlabels/Welle:".
# Typical use: paste a curated list or a wave-specific snippet. Leave as "" to use the default logic.
custom_rawcode_enum_block <- ""

# Optional coarse coding (informational only — still printed in prompts as context).
# Does not replace the numeric outcome; prompts ask for raw codes in-range.
outcome_groups <- data.frame(
  values_Links   = I(list(as.character(1:4))),    # left
  values_Neutral = I(list(as.character(5:7))),  # neutral
  values_Rechts  = I(list(as.character(8:11)))  # right
)

# Aus outcome_groups: Spaltennamen values_<X> → Prompt-Text „X“ (frei wählbar durch Umbenennen der Spalten)
outcome_aggregate_category_names <- sub(
  "^values_",
  "",
  names(outcome_groups)[startsWith(names(outcome_groups), "values_")]
)
outcome_aggregat_disclaimer_phrase <- {
  labs <- outcome_aggregate_category_names
  if (length(labs) == 0L) {
    "(keine vordefinierten Aggregat-Gruppen der Skala)"
  } else if (length(labs) == 1L) {
    paste0("(keine Aggregat-Kategorie „", labs[1L], "“)")
  } else {
    paste0("(keine Aggregat-Kategorien „", paste(labs, collapse = "/"), "“)")
  }
}

# -----------------------------------------------------------------------------
# 1. Defaults (usually leave as-is)
# -----------------------------------------------------------------------------

base_path <- file.path(PROJECT_ROOT, "data", "raw_survey",
                       "ZA6838_v6-0-0.dta")
dta_encoding <- "latin1"

columns_no_wave <- c("lfdn", "field_start", "field_end")
use_search_in_columns <- FALSE
add_source_file <- FALSE

# waves: drives wave_labels and wave_for_columns (numbers only)
# - If 1–9 present: one entry wave1to9 with wave_for_columns[[1]] = c("x", 1:9)
# - Other n: wave{n} with wave_for_columns entry c("x", n)
# Must match length/order of dta_files below.
waves <- c(1:9, 10:28)

# .dta files to read (project default)
dta_files <- c(
  "ZA6838_w1to9_sA_v6-0-0.dta",
  "ZA6838_w10_sA_v6-0-0.dta",
  "ZA6838_w11_sA_v6-0-0.dta",
  "ZA6838_w12_sA_v6-0-0.dta",
  "ZA6838_w13_sA_v6-0-0.dta",
  "ZA6838_w14_sA_v6-0-0.dta",
  "ZA6838_w15_sA_v6-0-0.dta",
  "ZA6838_w16_sA_v6-0-0.dta",
  "ZA6838_w17_sA_v6-0-0.dta",
  "ZA6838_w18_sA_v6-0-0.dta",
  "ZA6838_w19_sA_v6-0-0.dta",
  "ZA6838_w20_sA_v6-0-0.dta",
  "ZA6838_w21_sA_v6-0-0.dta",
  "ZA7728_v1-0-0.dta",
  "ZA7729_v1-0-0.dta",
  "ZA7730_v1-0-0.dta",
  "ZA7731_sA_v1-0-0.dta",
  "ZA7732_sA_v1-0-0.dta",
  "ZA7733_sA_v1-0-0.dta",
  "ZA10117_w28_sA_v2-0-0.dta"
)

build_wave_labels_and_columns <- function(waves_vec) {
  w <- sort(unique(as.integer(waves_vec)))
  w <- w[!is.na(w)]
  has_1to9 <- any(w %in% 1:9)
  rest <- setdiff(w, 1:9)

  labels <- character()
  wfc <- list()

  if (has_1to9) {
    labels <- c(labels, "wave1to9")
    wfc[[length(wfc) + 1L]] <- c("x", 1:9)
  }
  for (n in rest) {
    labels <- c(labels, paste0("wave", n))
    wfc[[length(wfc) + 1L]] <- c("x", n)
  }
  list(wave_labels = labels, wave_for_columns = wfc)
}

.wave_cfg <- build_wave_labels_and_columns(waves)
wave_labels <- .wave_cfg$wave_labels
wave_for_columns <- .wave_cfg$wave_for_columns

if (length(wave_labels) != length(dta_files) || length(wave_for_columns) != length(dta_files)) {
  stop(
    "wave_labels/wave_for_columns length from waves does not match dta_files.\n",
    "length(wave_labels) = ", length(wave_labels), ", length(wave_for_columns) = ", length(wave_for_columns),
    ", length(dta_files) = ", length(dta_files), "\n",
    "Align waves expansion with dta_files (default waves = c(1:9, 10:28))."
  )
}

# Personal info: suffix columns from three .dta (wave5/8/9), merge by lfdn into each wave (prompt background)
# - Ignores digits after kp/kpa; matches columns ending in _<suffix>
# - Multiple columns same suffix in one file: row-wise pmax(..., na.rm=TRUE)
# - After binding sources: first non-NA per lfdn per column
# - Output names prefixed (default pi_), e.g. pi_2280, pi_2290s
personal_info_sources <- list(
  wave5 = file.path(base_path, "ZA7961_wa5_sA_v1-0-0.dta"),
  wave8 = file.path(base_path, "ZA6838_wa2_sA_v6-0-0.dta"),
  wave9 = file.path(base_path, "ZA6838_w1to9_sA_v6-0-0.dta")
)
personal_info_suffixes <- c("2280", "2290s", "2320", "2591")
personal_info_col_prefix <- "pi_"

# Columns excluded from prompt background text
cols_exclude_from_background <- c(
  "lfdn", "field_start", "field_end", "outcome", "wave", "_source_file",
  "outcome_code", "outcome_sublabel"
)

# Output directory (one JSON file per wave)
output_dir <- file.path(PROJECT_ROOT, "outputs", "prompts", VARIANT)
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
hdata_dir <- file.path(PROJECT_ROOT, "data", "intermediate_hdata")
dir.create(hdata_dir, showWarnings = FALSE, recursive = TRUE)

# Save wave_list for LLM–survey joins (extra .rds snapshot)
save_wave_list_rds <- TRUE
# wave_list path (default under output_dir)
# Named with outcome_suffix and original-scale marker: wave_list_for_llm_join_1500_original_scale.rds
wave_list_export_path <- file.path(hdata_dir, paste0("wave_list_for_llm_join_", outcome_suffix, "_original_scale.rds"))
# Per-wave column dictionary: harmonized names (e.g. 020), var labels, value-label JSON
wave_column_metadata_export_path <- file.path(hdata_dir, paste0("wave_column_metadata_", outcome_suffix, "_original_scale.rds"))

# Outcome codes treated as missing/invalid before keeping raw numeric outcomes
values_to_exclude <- c(
  "-99","-98","-97","-96","-95","-94","-93","-92","-91","-86","-85","-84","-83","-82","-81","-72","-71"
)

# Manual variable labels (columns without Stata label; includes pi_* from personal info)
manual_var_labels <- c(
  kpx_2290s = "Geburtsjahr",
  pi_2280 = "Geschlecht",
  pi_2290s = "Geburtsjahr",
  pi_2320 = "Schulabschluss",
  pi_2591 = "Nettoeinkommen HH, mit Kategorien"
)

# Optional: manual scope text per variable (else derived from data)
manual_var_scope <- c()

# Skip scope generation (by variable label or suffix)
cols_exclude_from_scope <- c("Geburtsjahr", "2290s")

# Build Deutsch text: Code ranges per values_* Spalte aus outcome_groups (Prompt-Kontext)
build_outcome_classification_blurb <- function(groups_df = outcome_groups) {
  nm <- names(groups_df)
  keep <- nm[startsWith(nm, "values_")]
  if (length(keep) == 0L) return("")
  lines <- character()
  for (k in keep) {
    lab <- sub("^values_", "", k)
    vals <- groups_df[[k]][[1L]]
    if (is.null(vals) || length(vals) == 0L) next
    lines <- c(lines, paste0("- ", lab, ": Codes ", paste(as.character(vals), collapse = ", ")))
  }
  paste(lines, collapse = "\n")
}

outcome_classification_blurb <- build_outcome_classification_blurb(outcome_groups)

# T-Anchored: period -> event text (edit list as needed)
temporal_context_by_period <- c(
  "2018/H1" = "Mühsame GroKo-Bildung, Asylstreit (Seehofer vs. Merkel), Ankerzentren, Masterplan Migration",
  "2018/H2" = "Ausschreitungen in Chemnitz, Maaßen-Affäre, Rücktritt Merkels vom CDU-Vorsitz, Niedergang der Volksparteien.",
  "2019/H1" = "Mord an Walter Lübcke, Fridays for Future-Hype, Rezo-Video („Zerstörung der CDU“), Grüner Höhenflug.",
  "2019/H2" = "Anschlag in Halle, Grundrenten-Debatte, Repräsentationslücke in Ostdeutschland, Klimapaket-Kritik.",
  "2020/H1" = "Corona-Ausbruch, Lockdown-Schock, „Rally ’round the flag“-Effekt (hohes Regierungsvertrauen), Grenzschließungen.",
  "2020/H2" = "„Querdenken“-Bewegung, Sturm auf die Reichstagstreppe, Maskenpflicht-Debatte, Kritik an Exekutivverordnungen.",
  "2021/H1" = "Maskenaffäre (Korruption), Impfstoff-Mangel, Frustration über bürokratisches Krisenmanagement, Baerbock-Hype.",
  "2021/H2" = "Bundestagswahl, Ende der Ära Merkel, Start der Ampel-Koalition, Aufbruchstimmung vs. Unsicherheit.",
  "2022/H1" = "Ukraine-Invasion, Zeitenwende-Rede, Bundeswehr-Sondervermögen, Ende von „Wandel durch Handel“.",
  "2022/H2" = "Energiepreisschock, Nord-Stream-Sabotage, Reichsbürger-Razzia, „Letzte Generation“ (Klimakleber-Proteste).",
  "2023/H1" = "Heizungsgesetz-Streit (GEG), massive Inflation, Streikwelle, industrielle Abwanderungssorgen (Deindustrialisierung).",
  "2023/H2" = "Haushaltsurteil (60-Milliarden-Loch), AfD-Umfragehoch, Antisemitismus-Debatte nach 7. Oktober, Migrationsgipfel.",
  "2024/H1" = "Correctiv-Enthüllungen (Remigration), Demos gegen Rechtsextremismus, Bauernproteste, Messerattacke von Mannheim.",
  "2024/H2" = "Landtagswahlen im Osten (BSW/AfD Erfolg), Bruch der Ampel-Koalition (Linder-Entlassung), VW-Krise, Trump-Wiederwahl.",
  "2025/H1" = "Vorgezogene Neuwahlen, Vertrauensfrage, Fokus auf Wirtschaftswende, Debatte über staatliche Handlungsfähigkeit.",
  "2025/H2" = "Schwierige Regierungsbildung, fragmentiertes Parlament, Wehrpflicht-Debatte, Suche nach neuer gesellschaftlicher Mitte."
)
temporal_context_by_wave <- c()

# -----------------------------------------------------------------------------
# 2. Read .dta + column selection (from read_dta_select_columns.R)
# -----------------------------------------------------------------------------

build_columns_for_file <- function(waves, no_wave, wave_suffix) {
  want <- no_wave
  for (w in waves) {
    for (s in wave_suffix) {
      want <- c(want, paste0("kp", w, "_", s))
    }
  }
  unique(want)
}

read_dta_safe <- function(file_path, encoding = dta_encoding) {
  tryCatch(
    read_dta(file_path, encoding = encoding),
    error = function(e) {
      for (enc in c("UTF-8", "ISO-8859-1", "windows-1252")) {
        if (enc == encoding) next
        out <- tryCatch(read_dta(file_path, encoding = enc), error = function(e2) NULL)
        if (!is.null(out)) {
          message("  Einlesen mit encoding = \"", enc, "\" erfolgreich.")
          return(out)
        }
      }
      stop(e)
    }
  )
}

stopifnot(
  "wave_labels muss dieselbe Länge wie dta_files haben" = length(wave_labels) == length(dta_files),
  "wave_for_columns muss dieselbe Länge wie dta_files haben" = length(wave_for_columns) == length(dta_files)
)

file_paths <- file.path(base_path, dta_files)
required_sources <- unique(c(file_paths, unlist(personal_info_sources)))
missing_sources <- required_sources[!file.exists(required_sources)]
if (length(missing_sources)) {
  stop("Missing configured GLES inputs: ", paste(basename(missing_sources), collapse = ", "))
}
daten_liste <- list()

for (i in seq_along(dta_files)) {
  f <- file_paths[i]
  fname <- dta_files[i]
  if (!file.exists(f)) {
    warning("Datei nicht gefunden: ", f, " – überspringe.")
    next
  }
  message("Lese: ", fname, " ...")
  d <- read_dta_safe(f)
  d <- as.data.frame(d)

  if (use_search_in_columns) {
    has_suffix <- function(n) any(vapply(columns_wave_suffix, function(s) grepl(s, n, fixed = TRUE), NA))
    wave_cols <- names(d)[vapply(names(d), has_suffix, NA)]
    columns_to_keep <- c(columns_no_wave, wave_cols)
  } else {
    waves_this_file <- wave_for_columns[[i]]
    columns_to_keep <- build_columns_for_file(waves_this_file, columns_no_wave, columns_wave_suffix)
  }

  vorhanden <- intersect(columns_to_keep, names(d))
  if (length(vorhanden) == 0L) {
    warning("  Keine der gewünschten Spalten in ", fname, " gefunden – überspringe.")
    next
  }
  d <- d[, vorhanden, drop = FALSE]
  list_name <- wave_labels[i]
  if (list_name %in% names(daten_liste)) list_name <- paste0(list_name, "_", i)
  daten_liste[[list_name]] <- d
  if (add_source_file) daten_liste[[list_name]][["_source_file"]] <- fname
}

if (length(daten_liste) == 0L) stop("Keine Dateien eingelesen (daten_liste ist leer). base_path/dta_files prüfen.")

# -----------------------------------------------------------------------------
# 2b. Personal info from wave5/8/9 .dta, merge by lfdn (prompt background)
# -----------------------------------------------------------------------------
normalize_label_text <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("\\s+", " ", x)
  x <- gsub("ue", "ü", x, fixed = TRUE)
  x <- gsub("oe", "ö", x, fixed = TRUE)
  x <- gsub("ae", "ä", x, fixed = TRUE)
  x
}

# Harmonize 2591 (household net income) to codes 1–13 via label text
# Fixes code 14 / shifts across wave8/wave9
harmonize_2591_by_label <- function(vec) {
  # Use value-label text (robust to numeric code differences across waves)
  txt <- as.character(labelled::to_factor(vec, levels = "labels"))
  txt_n <- normalize_label_text(txt)

  # Canonical 13 brackets (codebook)
  canonical <- c(
    "unter 500 Euro",
    "500 bis unter 750 Euro",
    "750 bis unter 1000 Euro",
    "1000 bis unter 1250 Euro",
    "1250 bis unter 1500 Euro",
    "1500 bis unter 2000 Euro",
    "2000 bis unter 2500 Euro",
    "2500 bis unter 3000 Euro",
    "3000 bis unter 4000 Euro",
    "4000 bis unter 5000 Euro",
    "5000 bis unter 7500 Euro",
    "7500 bis unter 10000 Euro",
    "10000 Euro und mehr"
  )
  canonical_n <- normalize_label_text(canonical)
  canonical_labels <- setNames(seq_along(canonical), canonical)

  # Unknown / missing-style labels -> NA
  bad <- c(
    "keine angabe", "weiss nicht", "trifft nicht zu", "split", "nicht teilgenommen",
    "nicht in auswahlgesamtheit", "interview abgebrochen", "fehler in daten", "modus",
    "nicht wahlberechtigt", "nicht waehlen", "keine erst-/zweitstimme abgeben",
    "ungueltig waehlen", "keine andere partei waehlen", "noch nicht entschieden",
    "nicht einzuschaetzen", "nicht bekannt", "nicht gefragt / keine angabe"
  )
  bad_n <- normalize_label_text(bad)

  out <- rep(NA_real_, length(txt_n))
  ok <- !(is.na(txt_n) | txt_n %in% bad_n | txt_n == "")
  out[ok] <- match(txt_n[ok], canonical_n)

  # Reattach unified labels + variable label for prompt scope / value labels
  labelled::labelled(out, labels = canonical_labels, label = "Nettoeinkommen HH, mit Kategorien")
}

extract_cols_by_suffix_max <- function(df, suffixes) {
  if (is.null(df) || !"lfdn" %in% names(df)) return(NULL)
  nm <- names(df)
  res <- data.frame(lfdn = suppressWarnings(as.numeric(df[["lfdn"]])), stringsAsFactors = FALSE)
  for (suf in suffixes) {
    cols_suf <- grep(paste0("_", suf, "$"), nm, value = TRUE)
    if (length(cols_suf) == 0L) next
    if (length(cols_suf) == 1L) {
      v <- df[[cols_suf]]
      if (identical(suf, "2591")) {
        v <- harmonize_2591_by_label(v)
      }
      res[[suf]] <- v
    } else {
      cols_df <- as.data.frame(df[cols_suf])
      if (identical(suf, "2591")) {
        cols_df[] <- lapply(cols_df, harmonize_2591_by_label)
      }
      v <- do.call(pmax, c(cols_df, list(na.rm = TRUE)))
      if (identical(suf, "2591")) {
        # pmax drops labelled; reattach labels
        v <- harmonize_2591_by_label(v)
      }
      res[[suf]] <- v
    }
  }
  res
}

read_source_if_exists <- function(p) {
  if (!is.character(p) || length(p) != 1L || !nzchar(p) || !file.exists(p)) return(NULL)
  as.data.frame(read_dta_safe(p))
}

parts_pi <- list()
for (src_nm in names(personal_info_sources)) {
  p <- personal_info_sources[[src_nm]]
  df_src <- read_source_if_exists(p)
  if (is.null(df_src)) {
    message("Personal info source not found (skip): ", p)
    next
  }
  pi_part <- extract_cols_by_suffix_max(df_src, personal_info_suffixes)
  if (!is.null(pi_part)) parts_pi[[src_nm]] <- pi_part
}

if (length(parts_pi) > 0L) {
  pi_long <- bind_rows(parts_pi)
  pi_long <- pi_long %>%
    group_by(lfdn) %>%
    summarise(across(everything(), ~ {
      x <- .[!is.na(.)]
      if (length(x) == 0L) NA else x[1L]
    }), .groups = "drop")

  # summarise drops labelled on 2591; reattach
  if ("2591" %in% names(pi_long)) {
    pi_long[["2591"]] <- harmonize_2591_by_label(pi_long[["2591"]])
  }

  # Prefix pi_
  other_cols <- setdiff(names(pi_long), "lfdn")
  pi_sub <- data.frame(lfdn = pi_long[["lfdn"]], stringsAsFactors = FALSE)
  for (cn in other_cols) pi_sub[[paste0(personal_info_col_prefix, cn)]] <- pi_long[[cn]]

  n_merged <- 0L
  for (nm in names(daten_liste)) {
    df <- daten_liste[[nm]]
    if (!"lfdn" %in% names(df)) next
    df[["lfdn"]] <- suppressWarnings(as.numeric(df[["lfdn"]]))
    daten_liste[[nm]] <- dplyr::left_join(df, pi_sub, by = "lfdn")
    n_merged <- n_merged + 1L
  }
  message(
    "Personal info merged by lfdn into ", n_merged, " dataset(s) (columns: ",
    paste(setdiff(names(pi_sub), "lfdn"), collapse = ", "), ")."
  )
} else {
  message("No personal-info table (wave5/8/9 missing or no lfdn/target columns).")
}

# -----------------------------------------------------------------------------
# 3. Select waves + build/filter outcome (from select_waves_filter_outcome.R)
# -----------------------------------------------------------------------------

wave_num_from_label <- function(lbl) {
  if (identical(lbl, "wave1to9")) return(1L)
  m <- regmatches(lbl, regexpr("[0-9]+$", lbl))
  if (length(m) == 0L || !nzchar(m)) return(NA_integer_)
  as.integer(m)
}

available <- names(daten_liste)
waves_to_use <- unique(as.integer(waves_to_use))
waves_to_use <- waves_to_use[!is.na(waves_to_use)]
if (length(waves_to_use) == 0L) stop("waves_to_use is empty or invalid; use wave numbers, e.g. c(10,14,22).")

selected_wave_labels <- paste0("wave", waves_to_use)
selected_wave_labels[selected_wave_labels == "wave1"] <- "wave1to9"
selected <- intersect(selected_wave_labels, available)
if (length(selected) == 0L) stop("No wave data for waves_to_use: ", paste(selected_wave_labels, collapse = ", "))

exclude_char <- as.character(values_to_exclude)

wave_objects <- character()
wave_list <- list()

for (nm in selected) {
  df <- daten_liste[[nm]]
  if (!"lfdn" %in% names(df)) next
  num <- wave_num_from_label(nm)
  if (is.na(num)) next

  col_name <- paste0("kp", num, "_", outcome_suffix)
  if (!col_name %in% names(df)) {
    cand <- names(df)[grepl(paste0("_", outcome_suffix, "$"), names(df))]
    if (length(cand) > 0L) col_name <- cand[1L]
  }
  if (!col_name %in% names(df)) {
    warning("Outcome kp", num, "_", outcome_suffix, " in ", nm, " nicht gefunden – überspringe.")
    next
  }

  oz <- trimws(as.character(haven::zap_labels(df[[col_name]])))
  df <- df[!(oz %in% exclude_char), , drop = FALSE]
  oz <- trimws(as.character(haven::zap_labels(df[[col_name]])))
  onum <- suppressWarnings(as.numeric(oz))
  df[["outcome"]] <- onum
  df[["outcome_code"]] <- vapply(
    onum,
    function(v) if (is.na(v)) NA_character_ else if (abs(v - round(v)) < .Machine$double.eps^0.5) as.character(as.integer(round(v))) else trimws(sprintf("%.16g", v)),
    FUN.VALUE = character(1L)
  )
  attr(df, "outcome_source_column") <- col_name
  df <- df[!is.na(df[["outcome"]]) & df[["outcome"]] >= 0, , drop = FALSE]

  obj_name <- paste0("w", num)
  wave_objects <- c(wave_objects, obj_name)
  wave_list[[obj_name]] <- df
  assign(obj_name, df, envir = .GlobalEnv)
  message("  ", obj_name, " (", nm, "): ", nrow(df), " Zeilen")
}

wave_objects <- unique(wave_objects)
if (length(wave_objects) == 0L) stop("No w{n} objects (outcome column missing or all rows filtered).")

# -----------------------------------------------------------------------------
# 3.5 wave_list save moved to start of section 4 (after outcome_sublabel + column dict)
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# 4. Prompt generation (from build_prompt_from_waves.R)
# -----------------------------------------------------------------------------

# field_start (Datum) → Halbjahr "YYYY/H1" (Jan–Jun) oder "YYYY/H2" (Jul–Dez); für T-Anchored-Zeitkontext
period_from_field_start <- function(field_start) {
  if (is.na(field_start) || !nzchar(trimws(as.character(field_start)))) return(NA_character_)
  s <- trimws(as.character(field_start))
  year <- NA_integer_
  month <- NA_integer_
  if (grepl("^[0-9]{4}-[0-9]{1,2}", s)) {
    year <- as.integer(substr(s, 1L, 4L))
    month <- as.integer(sub("^[0-9]{4}-([0-9]{1,2}).*", "\\1", s))
  } else if (grepl("^[0-9]{4}/", s)) {
    year <- as.integer(substr(s, 1L, 4L))
    month <- as.integer(sub("^[0-9]{4}/([0-9]{1,2}).*", "\\1", s))
  } else if (grepl("^[0-9]{1,2}\\.[0-9]{1,2}\\.[0-9]{4}", s)) {
    parts <- strsplit(s, "\\.")[[1L]]
    if (length(parts) >= 3L) {
      year <- as.integer(parts[3L])
      month <- as.integer(parts[2L])
    }
  } else if (grepl("[0-9]{4}", s)) {
    year <- as.integer(sub(".*([0-9]{4}).*", "\\1", s))
    month <- 6L
  }
  if (is.na(year)) return(NA_character_)
  if (is.na(month)) month <- 6L
  paste0(year, "/", if (month <= 6L) "H1" else "H2")
}

# Zeitlicher Kontext für T-Anchored: zuerst nach field_start (Halbjahr), sonst Fallback nach Welle
get_temporal_context_for_record <- function(field_start, wave_name) {
  period <- period_from_field_start(field_start)
  if (!is.na(period) && length(temporal_context_by_period) > 0L && period %in% names(temporal_context_by_period))
    return(as.character(temporal_context_by_period[[period]]))
  if (length(temporal_context_by_wave) > 0L && wave_name %in% names(temporal_context_by_wave))
    return(as.character(temporal_context_by_wave[[wave_name]]))
  return("")
}

get_var_label <- function(var) {
  if (inherits(var, "haven_labelled") || inherits(var, "labelled")) {
    lbl <- var_label(var)
    if (!is.null(lbl) && !is.na(lbl)) return(as.character(lbl))
  }
  return(NULL)
}

# value = Einzelwert; var_column = optional die ganze Spalte (für Lookup der Wertelabels in den Daten)
get_value_label <- function(value, var_column = NULL) {
  if (is.na(value)) return("Nicht gefragt / keine Angabe")
  num_val <- suppressWarnings(as.numeric(value))
  char_val <- as.character(value)

  if (!is.null(var_column)) {
    lbls <- tryCatch(val_labels(var_column), error = function(e) NULL)
    if (is.null(lbls)) lbls <- attr(var_column, "labels")
    if (!is.null(lbls) && length(lbls) > 0L) {
      if (!is.null(names(lbls))) {
        idx <- which(lbls == num_val)
        if (length(idx) > 0L) return(names(lbls)[idx[1L]])
        if (char_val %in% names(lbls)) return(lbls[[char_val]])
      }
      if (!is.na(num_val) && num_val >= 1 && num_val <= length(lbls)) return(as.character(lbls[num_val]))
    }
  }
  if (inherits(value, "haven_labelled") || inherits(value, "labelled")) {
    lbl <- tryCatch(val_label(value, value), error = function(e) NULL)
    if (!is.null(lbl) && !is.na(lbl) && length(lbl) > 0) return(as.character(lbl))
  }
  if (is.factor(value)) return(as.character(value))
  char_val
}

# Aus Spalte automatisch Skalenbeschreibung erzeugen: nur nicht-negative Werte, Min/Max mit Wertelabels aus den Daten
get_scope_from_column <- function(col) {
  if (is.null(col) || length(col) == 0L) return(NULL)

  # Prefer value labels (codebook) for range; else observed min/max in data
  lbls <- tryCatch(val_labels(col), error = function(e) NULL)
  if (is.null(lbls)) lbls <- attr(col, "labels")

  # Few discrete levels: list all (e.g. gender)
  if (!is.null(lbls) && length(lbls) > 0L) {
    codes <- suppressWarnings(as.numeric(unname(lbls)))
    ok <- !is.na(codes) & codes >= 0
    codes <- codes[ok]
    if (length(codes) > 0L) {
      codes_u <- sort(unique(codes))
      if (length(codes_u) >= 2L && length(codes_u) <= 5L) {
        parts <- vapply(
          codes_u,
          function(v) {
            lab <- get_value_label(v, col)
            if (is.na(lab) || !nzchar(trimws(lab)) || identical(lab, "Nicht gefragt / keine Angabe")) lab <- as.character(v)
            paste0(v, " = ", lab)
          },
          character(1L)
        )
        return(paste(parts, collapse = ", "))
      }
    }
  }

  range_vals <- numeric()
  if (!is.null(lbls) && length(lbls) > 0L) {
    # haven/labelled: names = text labels, unname(lbls) = numeric codes
    range_vals <- suppressWarnings(as.numeric(unname(lbls)))
    range_vals <- range_vals[!is.na(range_vals) & range_vals >= 0]
  }

  if (length(range_vals) < 2L) {
    vals <- col[!is.na(col)]
    if (length(vals) == 0L) return(NULL)
    vals_num <- suppressWarnings(as.numeric(vals))
    vals_num <- vals_num[!is.na(vals_num) & vals_num >= 0]
    if (length(vals_num) < 2L) return(NULL)
    range_vals <- vals_num
  }

  min_val <- min(range_vals)
  max_val <- max(range_vals)
  if (identical(min_val, max_val)) return(NULL)

  lbl_min <- get_value_label(min_val, col)
  lbl_max <- get_value_label(max_val, col)
  if (is.na(lbl_min) || !nzchar(trimws(lbl_min)) || identical(lbl_min, "Nicht gefragt / keine Angabe")) lbl_min <- as.character(min_val)
  if (is.na(lbl_max) || !nzchar(trimws(lbl_max)) || identical(lbl_max, "Nicht gefragt / keine Angabe")) lbl_max <- as.character(max_val)

  # Strip leading "1 = ..." only; keep e.g. 10000 in "10000 Euro ..."
  strip_leading_digit <- function(s) trimws(sub("^\\s*[0-9]+\\s*=\\s*", "", as.character(s)))
  lbl_min <- strip_leading_digit(lbl_min)
  lbl_max <- strip_leading_digit(lbl_max)
  if (!nzchar(lbl_min)) lbl_min <- as.character(min_val)
  if (!nzchar(lbl_max)) lbl_max <- as.character(max_val)

  paste0(min_val, " = ", lbl_min, ", ", max_val, " = ", lbl_max)
}

# JSON output: Rohcode der bereinigten Skala (wie in der Datenbank)
format_outcome_code_for_prompt_json <- function(value) {
  if (length(value) != 1L && !is.atomic(value))
    stop("format_outcome_code_for_prompt_json: scalar expected")
  if (length(value) == 0L || is.na(value)) return("")
  num <- suppressWarnings(as.numeric(value))
  if (!is.na(num)) {
    if (abs(num - round(num)) < .Machine$double.eps^0.5) return(as.character(as.integer(round(num))))
    return(trimws(sprintf("%.16g", num)))
  }
  trimws(as.character(value))
}

# Text für Antwortformat: Bereich + optional Codeliste; Einordnung aus outcome_* (Klassifikationsregeln bleiben im Prompt als Kontext)
build_raw_outcome_answer_format_block <- function(outcome_src_col, observed_numeric, classification_blurb,
                                                   exclusions = exclude_char) {
  fmt_one <- function(x) {
    if (length(x) != 1L || is.na(x)) return(NA_character_)
    num <- suppressWarnings(as.numeric(x))
    if (!is.na(num) && is.finite(num)) {
      if (abs(num - round(num)) < .Machine$double.eps^0.5) return(as.character(as.integer(round(num))))
      return(trimws(sprintf("%.16g", num)))
    }
    trimws(as.character(x))
  }
  lbls <- tryCatch(val_labels(outcome_src_col), error = function(e) NULL)
  cand <- numeric()
  if (!is.null(lbls) && length(lbls) > 0L) {
    codes <- suppressWarnings(as.numeric(unname(lbls)))
    keys <- vapply(codes, function(c) suppressWarnings(fmt_one(c)), character(1L))
    ok <- !is.na(codes) & is.finite(codes) & codes >= 0 & !(keys %in% exclusions)
    cand <- codes[ok]
  }
  obs <- suppressWarnings(as.numeric(observed_numeric))
  obs <- unique(obs[!is.na(obs) & obs >= 0])
  cand <- sort(unique(c(cand, obs)))
  cand <- cand[is.finite(cand)]

  if (length(cand) == 0L) {
    rng <- "**Hinweis:** Für diese Welle konnte kein gültiger Codebereich aus Labels/Daten ermittelt werden — geben Sie den numerischen Antwortcode (Rohwert der Skala) zurück."
    block_enum <- ""
  } else {
    min_c <- min(cand, na.rm = TRUE)
    max_c <- max(cand, na.rm = TRUE)
    if (length(cand) == 1L || identical(min_c, max_c)) {
      rng <- glue("Der erlaubte Antwortbereich liegt für diese Erhebung **nur** bei dem Rohcode `{mc}`.",
                  mc = fmt_one(min_c))
    } else {
      rng <- glue(
        "Gültige Antworten sind Rohcodes im numerischen Bereich von **`{mn}` bis `{mx}`** (einschließlich der Grenzen). ",
        mn = fmt_one(min_c), mx = fmt_one(max_c)
      )
    }
    # Enumerated code list: either user override, or auto (<=7 full; >7 first+last)
    if (is.character(custom_rawcode_enum_block) && length(custom_rawcode_enum_block) == 1L &&
        nzchar(trimws(custom_rawcode_enum_block))) {
      block_enum <- paste0("\n\n", trimws(custom_rawcode_enum_block))
    } else {
      lab_lines_all <- vapply(cand, function(code) {
        lb <- as.character(get_value_label(code, outcome_src_col))
        if (is.na(lb) || !nzchar(trimws(lb)) || identical(lb, "Nicht gefragt / keine Angabe"))
          lb <- "(keine Textbeschriftung)"
        sprintf("%s = %s", fmt_one(code), lb)
      }, character(1L))

      lab_lines_show <- if (length(lab_lines_all) <= 7L) {
        lab_lines_all
      } else {
        lab_lines_all[c(1L, length(lab_lines_all))]
      }

      block_enum <- paste0(
        "\n\nZulässige Rohcodes gemäß Wertlabels/Welle:\n",
        paste(lab_lines_show, collapse = "\n")
      )
    }
  }

  paste0(rng, block_enum,
         "\n\nGeben Sie als **gesamte** Antwort ausschließlich **einen** solchen Zahlen‑Rohcode aus — ",
         "kein JSON, keine Erläuterung, nichts vor oder nach der Zahl.")
}

# w14 -> 14 (same as join_llm_with_wave_survey.R)
wave_num_from_wave_list_name <- function(list_name) {
  m <- regmatches(tolower(trimws(list_name)), regexec("^w([0-9]+)$", tolower(trimws(list_name))))[[1]]
  if (length(m) >= 2L) return(suppressWarnings(as.integer(m[2L])))
  NA_integer_
}

serialize_val_labels_json <- function(col) {
  if (!inherits(col, "labelled") && !inherits(col, "haven_labelled")) return(NA_character_)
  vl <- labelled::val_labels(col)
  if (is.null(vl) || length(vl) == 0L) return(NA_character_)
  codes <- unname(vl)
  labs <- names(vl)
  if (is.null(labs) || length(labs) == 0L) return(NA_character_)
  lst <- stats::setNames(as.list(labs), as.character(codes))
  jsonlite::toJSON(lst, auto_unbox = TRUE)
}

# One metadata table per wave: original name, harmonized suffix (020), var label, value-label JSON
build_wave_column_metadata_df <- function(df, wave_num) {
  df <- as.data.frame(df, stringsAsFactors = FALSE)
  cn <- names(df)
  if (length(cn) == 0L) {
    return(data.frame(
      survey_column = character(),
      harmonized_name = character(),
      var_label = character(),
      value_labels_json = character(),
      stringsAsFactors = FALSE
    ))
  }
  harm <- cn
  if (length(wave_num) == 1L && !is.na(wave_num)) {
    pat <- paste0("^kp", wave_num, "_(.+)$")
    for (i in seq_along(cn)) {
      mm <- regmatches(cn[i], regexec(pat, cn[i], perl = TRUE))[[1]]
      if (length(mm) >= 2L && nzchar(mm[2L])) harm[i] <- mm[2L]
    }
  }
  n <- length(cn)
  var_label_chr <- character(n)
  vlj <- character(n)
  for (i in seq_len(n)) {
    v <- df[[cn[i]]]
    vl <- get_var_label(v)
    if (is.null(vl) || !nzchar(trimws(vl))) {
      vl <- if (cn[i] %in% names(manual_var_labels)) manual_var_labels[[cn[i]]] else NA_character_
    } else {
      vl <- as.character(vl)
    }
    var_label_chr[i] <- vl
    vlj[i] <- serialize_val_labels_json(v)
  }
  data.frame(
    survey_column = cn,
    harmonized_name = harm,
    var_label = var_label_chr,
    value_labels_json = vlj,
    stringsAsFactors = FALSE
  )
}

# Outcome value label (German sublabel) + column dict; then save wave_list / metadata RDS
if (length(wave_list) > 0L) {
  for (nm in names(wave_list)) {
    df <- wave_list[[nm]]
    sc <- attr(df, "outcome_source_column", exact = TRUE)
    if (!is.null(sc) && sc %in% names(df)) {
      vc <- df[[sc]]
      df[["outcome_sublabel"]] <- vapply(
        seq_len(nrow(df)),
        function(i) as.character(get_value_label(vc[i], vc)),
        character(1L)
      )
    } else {
      df[["outcome_sublabel"]] <- rep(NA_character_, nrow(df))
    }
    attr(df, "outcome_source_column") <- NULL
    wave_list[[nm]] <- df
  }
}

wave_column_metadata <- list()
if (length(wave_list) > 0L) {
  for (nm in names(wave_list)) {
    wn <- wave_num_from_wave_list_name(nm)
    tab <- build_wave_column_metadata_df(wave_list[[nm]], wn)
    tab$wave_key <- nm
    wave_column_metadata[[nm]] <- tab
  }
}

if (isTRUE(save_wave_list_rds) && length(wave_list) > 0L) {
  dir.create(dirname(wave_list_export_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(wave_list, wave_list_export_path)
  message("wave_list saved (LLM join): ", wave_list_export_path)
  dir.create(dirname(wave_column_metadata_export_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(wave_column_metadata, wave_column_metadata_export_path)
  message("Column metadata dictionary saved: ", wave_column_metadata_export_path)
}

# Hintergrundtext aus einer Zeile; nutzt manual_var_labels und Skalenbeschreibung aus scope_lookup (automatisch aus Daten)
generate_background <- function(row_data, feature_vars, df_source, scope_lookup = NULL) {
  lines <- character()
  for (var_name in feature_vars) {
    if (!var_name %in% names(row_data)) next
    var_label <- get_var_label(df_source[[var_name]])
    if (is.null(var_label) || !nzchar(trimws(var_label))) {
      var_label <- if (var_name %in% names(manual_var_labels)) manual_var_labels[[var_name]] else var_name
    }
    if (length(scope_lookup) > 0L && var_name %in% names(scope_lookup) && nzchar(trimws(scope_lookup[[var_name]])))
      var_label <- paste0(var_label, " (", scope_lookup[[var_name]], ")")
    val <- row_data[[var_name]]
    value_label <- get_value_label(val, df_source[[var_name]])
    lines <- c(lines, paste0(var_label, ": ", value_label))
  }
  paste(lines, collapse = "\n")
}

# -----------------------------------------------------------------------------
# 3. Professioneller Prompt: field_start / field_end zuerst, dann Verbot
# -----------------------------------------------------------------------------

build_instruction <- function(field_start, field_end, background_text, question, choices_text, temporal_context = NULL) {
  fs <- if (is.na(field_start) || !nzchar(trimws(as.character(field_start)))) "[nicht angegeben]" else as.character(field_start)
  fe <- if (is.na(field_end)   || !nzchar(trimws(as.character(field_end))))   "[nicht angegeben]" else as.character(field_end)
  block_tctx <- ""
  if (!is.null(temporal_context) && nzchar(trimws(as.character(temporal_context)))) {
    block_tctx <- glue(
      "\n\n**Verwendbarer zeitlicher Kontext (kann für die Beantwortung verwendet werden):**\n",
      "{trimws(temporal_context)}\n\n"
    )
  }
  glue(
    "Sie sind ein*e Sozialwissenschaftler*in und analysieren Befragungsdaten einer befragten Person.\n\n",
    "**Zeitlicher Geltungsbereich der Daten (verbindlich):**\n",
    "- Feldzeit Beginn (field_start): {fs}\n",
    "- Feldzeit Ende (field_end): {fe}\n\n",
    "**Wichtiger Hinweis:** Verwenden Sie für die Beantwortung der Aufgabe ausschließlich Informationen, ",
    "die zum genannten Erhebungszeitraum (field_start bis field_end) gehören. ",
    "Verwenden Sie keine Daten oder Informationen, die zeitlich nach field_end liegen, zur Generierung Ihrer Antwort.",
    "{block_tctx}",
    "\nHintergrundinformationen der befragten Person (aus dem genannten Erhebungszeitraum):\n",
    "{background_text}\n\n",
    "Aufgabe: Bestimmen Sie die Antwort der befragten Person auf die folgende Frage:\n",
    "\"{question}\"\n\n",
    "Antwortformat: Geben Sie die Antwort als **numerischen Rohcode** der Originalskala vor {outcome_aggregat_disclaimer_phrase}.\n\n",
    "{choices_text}"
  )
}

# Baseline ohne Zeitblock/Hinweis: keine field_start/field_end-Information im Prompt
build_instruction_no_time <- function(background_text, question, choices_text) {
  glue(
    "Sie sind ein*e Sozialwissenschaftler*in und analysieren Befragungsdaten einer befragten Person.\n\n",
    "Hintergrundinformationen der befragten Person:\n",
    "{background_text}\n\n",
    "Aufgabe: Bestimmen Sie die Antwort der befragten Person auf die folgende Frage:\n",
    "\"{question}\"\n\n",
    "Antwortformat: Geben Sie die Antwort als **numerischen Rohcode** der Originalskala vor {outcome_aggregat_disclaimer_phrase}.\n\n",
    "{choices_text}"
  )
}

# Trajectory JSON: set FALSE to disable
enable_trajectory <- TRUE

wave_prev <- if (length(wave_objects) >= 2L) setNames(wave_objects[1:(length(wave_objects) - 1)], wave_objects[2:length(wave_objects)]) else character(0L)

build_instruction_trajectory <- function(year_prev, response_prev, field_start_prev, field_end_prev,
                                         field_start, field_end, background_text, question, choices_text) {
  fs <- if (is.na(field_start) || !nzchar(trimws(as.character(field_start)))) "[nicht angegeben]" else as.character(field_start)
  fe <- if (is.na(field_end)   || !nzchar(trimws(as.character(field_end))))   "[nicht angegeben]" else as.character(field_end)
  y_prev <- if (is.na(year_prev) || !nzchar(trimws(as.character(year_prev)))) "[Jahr Vorwelle]" else as.character(year_prev)
  fs_prev <- if (is.na(field_start_prev) || !nzchar(trimws(as.character(field_start_prev)))) "" else as.character(field_start_prev)
  fe_prev <- if (is.na(field_end_prev)   || !nzchar(trimws(as.character(field_end_prev))))   "" else as.character(field_end_prev)
  prev_survey_extra <- if (nzchar(fs_prev) && nzchar(fe_prev)) glue(", Erhebungszeitraum {fs_prev} bis {fe_prev}") else ""
  block_vorwelle <- glue(
    "**Antwort der befragten Person in der Vorwelle im Jahr {y_prev} lautete die damals gegebene Antwort: {response_prev}.\n\n---\n\n"
  )
  closing_marker <- "\n\nGeben Sie als **gesamte** Antwort"
  parts <- strsplit(choices_text, closing_marker, fixed = TRUE)[[1L]]
  if (length(parts) >= 2L) {
    choices_body <- parts[1L]
    choices_closing <- paste0(closing_marker, paste(parts[-1L], collapse = closing_marker))
  } else {
    choices_body <- choices_text
    choices_closing <- ""
  }
  part1 <- glue(
    "Sie sind ein*e Sozialwissenschaftler*in und analysieren Befragungsdaten einer befragten Person.\n\n",
    "**Zeitlicher Geltungsbereich der Daten (verbindlich):**\n",
    "- Feldzeit Beginn (field_start): {fs}\n",
    "- Feldzeit Ende (field_end): {fe}\n\n",
    "**Wichtiger Hinweis:** Verwenden Sie für die Beantwortung der Aufgabe ausschließlich Informationen, ",
    "die zum genannten Erhebungszeitraum (field_start bis field_end) gehören. ",
    "Verwenden Sie keine Daten oder Informationen, die zeitlich nach field_end liegen, zur Generierung Ihrer Antwort.\n\n",
    "Hintergrundinformationen der befragten Person (aus dem genannten Erhebungszeitraum):\n",
    "{background_text}\n\n",
    "Aufgabe: Bestimmen Sie die Antwort der befragten Person auf die folgende Frage:\n",
    "\"{question}\"\n\n",
    "Antwortformat: Geben Sie die Antwort als **numerischen Rohcode** der Originalskala vor {outcome_aggregat_disclaimer_phrase}.\n\n",
    "{choices_body}\n\n"
  )
  part2 <- paste0(
    "Bitte beziehen Sie die Antwort aus der Vorwelle in Ihre Vorhersage für diese Welle ein.",
    choices_closing
  )
  paste0(part1, block_vorwelle, part2)
}

# Each w{n} must have field_start, field_end, outcome
for (nm in names(wave_list)) {
  df <- wave_list[[nm]]
  need <- c("field_start", "field_end", "outcome")
  miss <- setdiff(need, names(df))
  if (length(miss) > 0L) stop("In ", nm, " fehlen: ", paste(miss, collapse = ", "))
}

for (nm in names(wave_list)) {
  df <- wave_list[[nm]]
  feature_columns <- setdiff(names(df), cols_exclude_from_background)
  # Outcome-Variable (z. B. kp22_2880x) aus Hintergrund entfernen, sonst steht die Antwort schon im Prompt
  feature_columns <- feature_columns[!grepl(paste0("_", outcome_suffix, "$"), feature_columns)]
  if (length(feature_columns) == 0L) feature_columns <- character(0)
  # Scope per variable: manual_var_scope or auto from column; skip e.g. birth year
  scope_lookup <- list()
  for (v in feature_columns) {
    var_lbl <- get_var_label(df[[v]])
    if (is.null(var_lbl) || !nzchar(trimws(var_lbl))) var_lbl <- if (v %in% names(manual_var_labels)) manual_var_labels[[v]] else ""
    suffix <- sub("^.*_", "", v)
    if (length(cols_exclude_from_scope) > 0L && (trimws(var_lbl) %in% cols_exclude_from_scope || (nzchar(suffix) && suffix %in% cols_exclude_from_scope)))
      next
    scope_text <- NULL
    if (length(manual_var_scope) > 0L && v %in% names(manual_var_scope))
      scope_text <- manual_var_scope[[v]]
    if (is.null(scope_text) && length(manual_var_scope) > 0L && nzchar(suffix) && suffix %in% names(manual_var_scope))
      scope_text <- manual_var_scope[[suffix]]
    if (is.null(scope_text) || !nzchar(trimws(scope_text))) scope_text <- get_scope_from_column(df[[v]])
    if (!is.null(scope_text) && nzchar(trimws(scope_text))) scope_lookup[[v]] <- scope_text
  }
  src_candidates <- grep(paste0("_", outcome_suffix, "$"), names(df), value = TRUE)
  if (length(src_candidates) == 0L)
    stop(nm, ": keine Outcome-Ursprungsvariable (*_", outcome_suffix, ") für Rohcode-Prompt.")
  prefer_src <- src_candidates[grepl("^kp", src_candidates)]
  outcome_src_col_nm <- if (length(prefer_src) > 0L) prefer_src[1L] else src_candidates[1L]
  choices_text_wave <- build_raw_outcome_answer_format_block(
    df[[outcome_src_col_nm]],
    df[["outcome"]],
    outcome_classification_blurb,
    exclusions = exclude_char
  )
  wave_records <- list()
  wave_records_notime <- list()
  wave_records_tanchored <- list()
  for (i in seq_len(nrow(df))) {
    row <- df[i, ]
    fs <- row[["field_start"]]
    fe <- row[["field_end"]]
    tctx <- get_temporal_context_for_record(fs, nm)
    bg <- generate_background(row, feature_columns, df, scope_lookup = scope_lookup)
    instruction <- as.character(build_instruction(
      field_start = fs, field_end = fe,
      background_text = bg,
      question = outcome_question,
      choices_text = choices_text_wave,
      temporal_context = NULL
    ))
    instruction_tanchored <- as.character(build_instruction(
      field_start = fs, field_end = fe,
      background_text = bg,
      question = outcome_question,
      choices_text = choices_text_wave,
      temporal_context = tctx
    ))
    instruction_notime <- as.character(build_instruction_no_time(
      background_text = bg,
      question = outcome_question,
      choices_text = choices_text_wave
    ))
    oc_val <- row[["outcome"]]
    oc_val <- if (length(oc_val) == 1L) oc_val[[1L]] else oc_val
    target_answer <- format_outcome_code_for_prompt_json(oc_val)
    id_val <- if ("lfdn" %in% names(row)) as.character(row[["lfdn"]]) else paste0(nm, "_", i)
    wave_records[[i]] <- list(
      instruction = instruction,
      input = " ",
      output = target_answer,
      id = id_val
    )
    wave_records_notime[[i]] <- list(
      instruction = instruction_notime,
      input = " ",
      output = target_answer,
      id = id_val
    )
    wave_records_tanchored[[i]] <- list(
      instruction = instruction_tanchored,
      input = " ",
      output = target_answer,
      id = id_val
    )
  }
  out_file <- file.path(output_dir, paste0("prompt_", nm, ".json"))
  writeLines(toJSON(wave_records, auto_unbox = TRUE, pretty = TRUE), out_file)
  message(nm, ": ", length(wave_records), " Records → ", out_file)
  out_file_notime <- file.path(output_dir, paste0("prompt_", nm, "_baseline_notime.json"))
  writeLines(toJSON(wave_records_notime, auto_unbox = TRUE, pretty = TRUE), out_file_notime)
  message(nm, " (Baseline ohne Zeitinfo): ", length(wave_records_notime), " Records → ", out_file_notime)
  out_file_t <- file.path(output_dir, paste0("prompt_", nm, "_tanchored.json"))
  writeLines(toJSON(wave_records_tanchored, auto_unbox = TRUE, pretty = TRUE), out_file_t)
  message(nm, " (T-Anchored): ", length(wave_records_tanchored), " Records → ", out_file_t)

  # Trajectory Group: nur Zeilen, deren lfdn in der Vorwelle vorkommt; Prompt mit Historical Profile + Original
  if (enable_trajectory && nm %in% names(wave_prev)) {
    prev_nm <- wave_prev[[nm]]
    if (prev_nm %in% names(wave_list)) {
      prev_df <- wave_list[[prev_nm]]
      current_df <- df
      in_both <- current_df[["lfdn"]] %in% prev_df[["lfdn"]]
      df_traj <- current_df[in_both, , drop = FALSE]
      if (nrow(df_traj) > 0L) {
        wave_records_trajectory <- list()
        for (j in seq_len(nrow(df_traj))) {
          row <- df_traj[j, ]
          lfdn_val <- row[["lfdn"]]
          prev_row <- prev_df[prev_df[["lfdn"]] == lfdn_val, , drop = FALSE][1L, ]
          year_prev <- suppressWarnings(as.integer(substr(as.character(prev_row[["field_start"]]), 1L, 4L)))
          if (is.na(year_prev)) year_prev <- suppressWarnings(as.integer(substr(as.character(prev_row[["field_end"]]), 1L, 4L)))
          pv <- prev_row[["outcome"]]
          pv <- if (length(pv) == 1L) pv[[1L]] else pv
          response_prev <- format_outcome_code_for_prompt_json(pv)
          fs <- row[["field_start"]]
          fe <- row[["field_end"]]
          fs_prev <- prev_row[["field_start"]]
          fe_prev <- prev_row[["field_end"]]
          bg <- generate_background(row, feature_columns, df, scope_lookup = scope_lookup)
          instr_traj <- as.character(build_instruction_trajectory(
            year_prev = year_prev,
            response_prev = response_prev,
            field_start_prev = fs_prev, field_end_prev = fe_prev,
            field_start = fs, field_end = fe,
            background_text = bg,
            question = outcome_question,
            choices_text = choices_text_wave
          ))
          oc_tr <- row[["outcome"]]
          oc_tr <- if (length(oc_tr) == 1L) oc_tr[[1L]] else oc_tr
          target_answer <- format_outcome_code_for_prompt_json(oc_tr)
          id_val <- as.character(lfdn_val)
          wave_records_trajectory[[j]] <- list(
            instruction = instr_traj,
            input = " ",
            output = target_answer,
            id = id_val
          )
        }
        out_file_traj <- file.path(output_dir, paste0("prompt_", nm, "_trajectory.json"))
        writeLines(toJSON(wave_records_trajectory, auto_unbox = TRUE, pretty = TRUE), out_file_traj)
        message(nm, " (Trajectory, Vorwelle ", prev_nm, "): ", length(wave_records_trajectory), " Records → ", out_file_traj)
      }
    }
  }
}

# -----------------------------------------------------------------------------
# 6. Prompt-Vorlage (nur Text) zum Kopieren / Anpassen
# -----------------------------------------------------------------------------

PROMPT_TEMPLATE <- paste0(
  "
Sie sind ein*e Sozialwissenschaftler*in und analysieren Befragungsdaten einer befragten Person.

**Zeitlicher Geltungsbereich der Daten (verbindlich):**
- Feldzeit Beginn (field_start): [FIELD_START]
- Feldzeit Ende (field_end): [FIELD_END]

**Wichtiger Hinweis:** Verwenden Sie für die Beantwortung der Aufgabe ausschließlich Informationen, die zum genannten Erhebungszeitraum (field_start bis field_end) gehören. Verwenden Sie keine Daten oder Informationen, die zeitlich nach field_end liegen, zur Generierung Ihrer Antwort.

Hintergrundinformationen der befragten Person (aus dem genannten Erhebungszeitraum):
[HINTERGRUND]

Aufgabe: Bestimmen Sie die Antwort der befragten Person auf die folgende Frage:
\"[FRAGE]\"

Antwortformat: Geben Sie die Antwort als **numerischen Rohcode** der Originalskala vor ",
  outcome_aggregat_disclaimer_phrase,
  ".
[HINWEIS_CODEBEREICH_OPTIONEN_REFERENZ]

Geben Sie als **gesamte** Antwort ausschließlich **einen** solchen Zahlen-Rohcode — kein JSON, keine Erläuterung, nichts vor oder nach der Zahl.
"
)

# Optional: write text template file
template_file <- file.path(output_dir, "prompt_template_field_start_end.txt")
writeLines(trimws(PROMPT_TEMPLATE), template_file)
message("Prompt template: ", template_file)

# Output: one prompt_<wave>.json per wave (e.g. prompt_w22.json) with all records for that wave.
# PROMPT_TEMPLATE -> prompt_template_field_start_end.txt
