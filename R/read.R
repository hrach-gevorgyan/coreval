#' Read a study into coreval's internal representation
#'
#' Reads a study folder: SAS transport (`.xpt`) and SAS (`.sas7bdat`) files,
#' Dataset-JSON (`.json`, `.ndjson`), or a USDM study document, plus a
#' Define-XML when one is there. A CORE test-case `data/` folder
#' (`_variables.csv` and one CSV per dataset) is read too. All of them come out
#' in the same internal representation, so the evaluator never has to know
#' which one it got.
#'
#' Character columns use `""` for blank/missing (never `NA`) to match how
#' SAS XPT round-trips blanks; numeric columns use `NA`. Column types are
#' taken from the source (XPT's own types, or `_variables.csv`'s declared
#' `Char`/`Num`) rather than guessed from the data, so numeric-looking
#' identifiers (e.g. `"007"`) are never silently coerced.
#'
#' @param path Directory path.
#' @param usdm Read a USDM study design document. `FALSE` by default: USDM is
#'   not what most studies are checked for, and some of its rules take minutes
#'   on one file, so it has to be asked for. Without it, a folder holding only
#'   a USDM document is refused with a message saying so, never read as empty.
#' @return A study object: `list(datasets = <named list of domain ->
#'   list(data, meta, label)>, define, ct = NULL, standard =
#'   list(product, version))`. `define` is the parsed Define-XML if one was
#'   found in `path` and the `xml2` package is installed, and `NULL`
#'   otherwise; `ct` is always `NULL`. Each `data` is a
#'   [data.table::data.table()];
#'   each `meta` is a data.table with columns `variable`, `label`, `type`;
#'   `label` is the dataset's own label (e.g. `"Adverse Events"`), or `NA` if
#'   unavailable. `standard` is the study's declared standard/version (e.g.
#'   `list(product = "SDTMIG", version = "3-4")`), read from a CORE test
#'   case's `.env` file or a USDM document, and both `NA` for a folder of
#'   datasets, which does not declare one.
#' @examples
#' dir <- tempfile("coreval_study_")
#' dir.create(dir)
#' haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
#' study <- read_study(dir)
#' study$datasets$DM$data
#' unlink(dir, recursive = TRUE)
#' @export
read_study <- function(path, usdm = FALSE) {
  # A missing folder used to read as an empty study, and an empty study checks
  # clean - so a typo in the path reported the data as fine. check_study()
  # already refuses a path it cannot find; read_study() must not be laxer than
  # its sibling.
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("`path` must be a single folder path.", call. = FALSE)
  }
  if (!dir.exists(path)) {
    stop("no such folder: ", path, call. = FALSE)
  }
  if (!isTRUE(usdm) && !isFALSE(usdm)) {
    stop("`usdm` must be TRUE or FALSE.", call. = FALSE)
  }
  if (file.exists(file.path(path, "_variables.csv"))) {
    return(read_study_test_case(path))
  }
  # A USDM study document is `.json` too, and reading one as a Dataset-JSON
  # refuses it for declaring no columns, which says nothing useful about what
  # it actually is. A folder holding datasets as well is read as datasets.
  json_files <- list.files(path, pattern = "[.]json$", ignore.case = TRUE,
                           full.names = TRUE)
  usdm_docs <- Filter(is_usdm_document, json_files)
  tabular <- list.files(path, pattern = "[.](xpt|sas7bdat|ndjson)$",
                        ignore.case = TRUE)
  if (length(usdm_docs) > 0 && length(tabular) == 0 &&
      length(json_files) == length(usdm_docs)) {
    # Refused, not skipped: skipped, the folder would read as holding no
    # datasets, and the error for that says nothing about USDM.
    if (!usdm) {
      stop(basename(usdm_docs[[1]]), " is a USDM study design document. ",
           "Checking USDM is optional, because some of its rules take minutes ",
           "on one file: use check_study(\"", path, "\", usdm = TRUE).",
           call. = FALSE)
    }
    return(read_study_usdm(path))
  }
  # With no datasets in any readable format this returns an empty study, which
  # is the honest answer, and check_study() refuses to call an empty study
  # clean.
  read_study_folder(path, skip = usdm_docs)
}

#' Read every dataset file in a study folder
#'
#' A folder holding any `.xpt` file used to be read as XPT only, and every
#' `.sas7bdat`, `.json` and `.ndjson` file beside them was dropped without a
#' word. A study whose DM was a SAS dataset then reported "DM dataset is
#' missing", and every rule comparing another dataset with DM lost its other
#' half.
#'
#' Every dataset file is now read. When two files hold the same dataset, which
#' is what a conversion in progress looks like, the transport file wins, then
#' the SAS dataset, then Dataset-JSON, and the one left out is named in a
#' warning. Two files of the same format for one dataset cannot be ranked, so
#' that is refused. CSV files are not read from a folder, since a CSV carries no
#' types or labels; they are named in a warning so they are not missed.
#'
#' @param path The folder.
#' @param skip Files already accounted for (a USDM document) and not to warn
#'   about.
#' @return A study list, see [read_study()].
#' @noRd
read_study_folder <- function(path, skip = character(0)) {
  rank <- c(xpt = 1L, sas7bdat = 2L, json = 3L, ndjson = 4L)
  files <- list.files(path, pattern = "[.](xpt|sas7bdat|json|ndjson)$",
                      ignore.case = TRUE, full.names = TRUE)
  files <- files[!normalizePath(files, mustWork = FALSE) %in%
                   normalizePath(skip, mustWork = FALSE)]
  ext <- tolower(tools::file_ext(files))
  datasets <- lapply(seq_along(files), function(i) {
    switch(ext[[i]],
      xpt = , sas7bdat = build_dataset_from_data_frame(read_sas_file(files[[i]])),
      json = read_dataset_json(files[[i]]),
      ndjson = read_dataset_ndjson(files[[i]])
    )
  })
  # The name a Dataset-JSON file declares for itself is used over its file
  # name: a file renamed on the way out of a transfer should not rename the
  # dataset with it.
  declared <- vapply(datasets, function(d) {
    nm <- attr(d, "dataset_name")
    if (is.null(nm)) NA_character_ else nm
  }, character(1))
  keys <- ifelse(is.na(declared),
                 toupper(tools::file_path_sans_ext(basename(files))), declared)

  keep <- rep(TRUE, length(files))
  for (key in unique(keys[duplicated(keys)])) {
    idx <- which(keys == key)
    best <- min(rank[ext[idx]])
    winners <- idx[rank[ext[idx]] == best]
    if (length(winners) > 1) {
      stop("more than one file holds the dataset ", key, ": ",
           paste(basename(files[winners]), collapse = ", "),
           ". Keep one, since there is no telling which should be checked.",
           call. = FALSE)
    }
    dropped <- setdiff(idx, winners)
    keep[dropped] <- FALSE
    warning(basename(files[winners]), " and ",
            paste(basename(files[dropped]), collapse = ", "),
            " both hold the dataset ", key, "; only ", basename(files[winners]),
            " was checked.", call. = FALSE)
  }
  datasets <- datasets[keep]
  names(datasets) <- keys[keep]

  csv <- list.files(path, pattern = "[.]csv$", ignore.case = TRUE)
  if (length(datasets) > 0 && length(csv) > 0) {
    warning("not read: ", paste(csv, collapse = ", "), ". A study folder is read ",
            "from .xpt, .sas7bdat and Dataset-JSON files; check a CSV on its own ",
            "with check_dataset().", call. = FALSE)
  }
  if (length(datasets) > 0 && length(skip) > 0) {
    warning("not read: ", paste(basename(skip), collapse = ", "), ", a USDM ",
            "document in a folder of datasets. Check it from a folder of its ",
            "own, with usdm = TRUE.", call. = FALSE)
  }
  list(datasets = datasets, define = read_define_xml(find_define_xml(path)),
       ct = NULL, standard = list(product = NA_character_, version = NA_character_))
}

#' Undo `fread`'s handling of an escaped quote inside a quoted CSV field
#'
#' RFC 4180 escapes a quote inside a quoted field by doubling it, so
#' `"<ref klass=""Range""/>"` is the value `<ref klass="Range"/>`. `fread` does
#' not collapse the pair when the field contains no separator and no newline:
#' it hands back `<ref klass=""Range""/>`, quotes and all. `utils::read.csv`
#' reads the same file correctly, so this is not ambiguity in the data.
#'
#' The consequence is a wrong value rather than a failure to read, which is why
#' it went unnoticed: a rule matching the value against a pattern gets a
#' definite answer computed from text the file does not contain. Found on
#' CORE-000833, whose values are `usdm:ref` elements full of quoted attributes.
#'
#' Only files that actually contain a doubled quote are re-read, so the common
#' case pays one scan of the raw bytes and nothing else. The re-read is
#' authoritative for character columns only; every type decision stays with the
#' `fread` call, which the rest of this function depends on.
#'
#' @param dt The data.table just read, mutated by reference.
#' @param path The file it came from.
#' @return `invisible(NULL)`; `dt` is modified in place.
#' @noRd
repair_doubled_quotes <- function(dt, path) {
  if (nrow(dt) == 0 || !file.exists(path)) {
    return(invisible(NULL))
  }
  char_cols <- names(dt)[vapply(dt, is.character, logical(1))]
  if (length(char_cols) == 0) {
    return(invisible(NULL))
  }
  affected <- char_cols[vapply(char_cols, function(v) {
    any(grepl('""', dt[[v]], fixed = TRUE), na.rm = TRUE)
  }, logical(1))]
  if (length(affected) == 0) {
    return(invisible(NULL))
  }
  proper <- tryCatch(
    utils::read.csv(path, colClasses = "character", check.names = FALSE,
                    na.strings = character(0)),
    error = function(e) NULL
  )
  if (is.null(proper) || nrow(proper) != nrow(dt)) {
    return(invisible(NULL))
  }
  for (v in intersect(affected, names(proper))) {
    data.table::set(dt, j = v, value = as.character(proper[[v]]))
  }
  invisible(NULL)
}

#' Text that is not valid UTF-8, read as the Windows encoding SAS writes
#'
#' A transport file carries no statement of its encoding, and SAS on Windows
#' writes `wlatin1`, so a curly apostrophe arrives as the single byte 0x92.
#' `haven` hands that back marked as UTF-8, where it is not a character at all.
#' CDISC's own pilot submission has three such values in TS. Every pattern
#' rule that met one raised a warning and got NA for that row, and NA is not a
#' finding: those rows were silently left unchecked, 126 warnings' worth.
#'
#' Only strings that are invalid as UTF-8 are converted, so valid text, which
#' is nearly all of it, is untouched. Windows-1252 rather than Latin-1 because
#' it is the superset that gives 0x80-0x9F their meaning; those are exactly the
#' quotes and dashes this goes wrong on. A byte that is not text in that
#' encoding either keeps its hex escape rather than being dropped.
#'
#' @param x A character vector.
#' @return `x`, with invalid strings re-read as Windows-1252.
#' @noRd
fix_invalid_utf8 <- function(x) {
  if (!is.character(x)) {
    return(x)
  }
  bad <- !is.na(x) & !validUTF8(x)
  if (!any(bad)) {
    return(x)
  }
  fixed <- iconv(x[bad], from = "CP1252", to = "UTF-8", sub = "byte")
  Encoding(fixed) <- "UTF-8"
  x[bad] <- fixed
  x
}

#' A number as the text a person would write
#'
#' `as.character(100000)` is `"1e+05"`, so every place that turned a number
#' into text to compare it with text failed on round numbers from 100,000 up:
#' a SUPP row with IDVARVAL "100000" found no parent with AESEQ 100000, and a
#' study day of 100000 failed the pattern for a study day. Fifteen significant
#' digits, the same precision [settle_float_noise()] keeps.
#'
#' @param x A numeric vector.
#' @return A character vector, `NA` where `x` is `NA`.
#' @noRd
number_text <- function(x) {
  out <- trimws(formatC(as.double(x), format = "fg", digits = 15))
  out[is.na(x)] <- NA_character_
  out
}

#' Values from a Dataset-JSON rows matrix as text
#'
#' jsonlite turns the rows into a numeric matrix when every value is a number,
#' so a text column holding numbers comes back as doubles and must be written
#' out the way the file wrote it.
#'
#' @param values One column of the rows matrix.
#' @return A character vector.
#' @noRd
json_text <- function(values) {
  if (is.numeric(values)) number_text(values) else as.character(values)
}

#' Remove the conversion noise transport files leave in numbers
#'
#' XPT stores numbers as IBM mainframe floating point, often in fewer than
#' eight bytes, and converting them to the doubles R uses lands them a hair off
#' the value that was written. The same visit number can then arrive as
#' 9.2999999999999989 in one dataset and 9.3000000000000007 in another, which
#' compare unequal. CDISC's own pilot submission does exactly that between LB
#' and SV, and a rule asking whether each lab visit appears in the subject's
#' visits reported 250 records whose visit is sitting right there. The same
#' study read from its Dataset-JSON copy reported none.
#'
#' Rounded to 15 significant digits, which is below where the noise lives and
#' far above any precision clinical data carries; R prints no more than that
#' by default anyway. Whole numbers and exact values are unchanged.
#'
#' @param dt A data.table, mutated by reference.
#' @return `invisible(NULL)`.
#' @noRd
settle_float_noise <- function(dt) {
  for (v in names(dt)) {
    col <- dt[[v]]
    if (is.double(col) && !inherits(col, c("Date", "POSIXt", "difftime", "hms"))) {
      rounded <- signif(col, 15)
      attributes(rounded) <- attributes(col)
      data.table::set(dt, j = v, value = rounded)
    }
  }
  invisible(NULL)
}

#' Apply [fix_invalid_utf8()] to every character column, in place
#' @param dt A data.table, mutated by reference.
#' @return `invisible(NULL)`.
#' @noRd
repair_invalid_utf8 <- function(dt) {
  for (v in names(dt)) {
    col <- dt[[v]]
    if (is.character(col) && !all(validUTF8(col[!is.na(col)]))) {
      data.table::set(dt, j = v, value = fix_invalid_utf8(col))
    }
  }
  invisible(NULL)
}

#' Rewrite `NA` to `""` for every character column of a data.table, in place
#' @param dt A data.table, mutated by reference.
#' @return `invisible(NULL)`; `dt` is modified in place.
#' @noRd
fill_char_blanks <- function(dt) {
  for (v in names(dt)) {
    if (is.character(dt[[v]])) {
      data.table::set(dt, j = v, value = ifelse(is.na(dt[[v]]), "", dt[[v]]))
    }
  }
  invisible(NULL)
}

#' Read one SAS transport or SAS dataset file, refusing one that is not whole
#'
#' A transport file cut off part-way (an interrupted copy or download) read
#' without complaint: haven returned the rows before the break, and the study
#' was checked as if that were all of AE. Every problem in the missing half
#' went unreported. A transport file is built from 80-byte records, so one
#' whose size is not a multiple of 80 has lost its end. A cut that lands on a
#' record boundary cannot be told from a shorter file, since the format stores
#' no row count.
#'
#' haven's own error names the full path and says only "Unable to read from
#' file", so an empty or damaged file is reported by its name instead.
#'
#' @param path A `.xpt` or `.sas7bdat` file.
#' @return The data frame haven reads.
#' @noRd
read_sas_file <- function(path) {
  name <- basename(path)
  xpt <- tolower(tools::file_ext(path)) == "xpt"
  size <- file.size(path)
  if (is.na(size) || size == 0) {
    stop("'", name, "' is empty (0 bytes), so there is no dataset in it to check. ",
         "Replace it with the real file, or remove it.", call. = FALSE)
  }
  # Every transport file opens with this record, v5 and v8 alike. Testing it
  # first keeps a CSV saved under a .xpt name from being called cut off.
  if (xpt && !identical(suppressWarnings(readChar(path, 20L, useBytes = TRUE)),
                       "HEADER RECORD*******")) {
    stop("'", name, "' is not a SAS transport file, whatever its name says. ",
         "Nothing was checked.", call. = FALSE)
  }
  if (xpt && size %% 80 != 0) {
    stop("'", name, "' is damaged: it ends part-way through the data, the way a ",
         "file does when a copy or download was interrupted. Nothing was checked, ",
         "because checking part of a dataset would miss problems in the rest.",
         call. = FALSE)
  }
  tryCatch(
    if (xpt) haven::read_xpt(path) else haven::read_sas(path),
    error = function(e) {
      stop("could not read '", name, "': it is damaged, or is not a ",
           if (xpt) "SAS transport (.xpt)" else "SAS (.sas7bdat)", " file (",
           sub("^Failed to parse .*: ", "", conditionMessage(e)), ")",
           call. = FALSE)
    }
  )
}

#' Convert a data frame into a `list(data, meta)` dataset entry
#'
#' Used for a whole directory of XPT files, and for a single data frame handed
#' straight to [check_dataset()]. Column labels are read from each column's
#' `label` attribute, which `haven` sets and a plain data frame simply lacks.
#'
#' @param raw A data frame, e.g. from [haven::read_xpt()].
#' @return `list(data, meta)`, see [read_study()].
#' @noRd
build_dataset_from_data_frame <- function(raw) {
  # Two columns of one name were checked without a word, and which of the two
  # a rule read depended on how it looked the column up.
  dup <- unique(names(raw)[duplicated(names(raw))])
  if (length(dup) > 0) {
    stop("more than one column is named ", paste0("'", dup, "'", collapse = ", "),
         ". Give each column its own name; otherwise there is no telling which ",
         "one a rule checked.", call. = FALSE)
  }
  dt <- data.table::as.data.table(raw)
  # exact = TRUE: `attr(col, "label")` also matches the `labels` attribute
  # haven gives a column with value labels, so a column with value labels and
  # no variable label either stopped the check or took a value label as its
  # variable label.
  labels <- vapply(raw, function(col) {
    lbl <- attr(col, "label", exact = TRUE)
    if (is.null(lbl) || length(lbl) != 1L) NA_character_ else as.character(lbl)
  }, character(1))

  for (v in names(dt)) {
    col <- dt[[v]]
    # Value labels are a display format; the rules read the stored values.
    if (inherits(col, "haven_labelled")) {
      col <- as.vector(haven::zap_labels(col))
    }
    # SDTM dates are ISO 8601 text, and the date rules parse that text. A
    # date-time column (a data frame built in R, or a SAS DATETIME variable)
    # printed as "2024-01-05 09:00:00", which is not ISO 8601, so every date
    # rule treated it as unreadable and found nothing.
    if (inherits(col, "POSIXt")) {
      text <- format(col, "%Y-%m-%dT%H:%M:%S")
      text[is.na(col)] <- ""
      col <- text
    } else if (inherits(col, "Date")) {
      text <- format(col, "%Y-%m-%d")
      text[is.na(col)] <- ""
      col <- text
    }
    if (!identical(col, dt[[v]])) {
      data.table::set(dt, j = v, value = col)
    }
  }

  # A factor is text as far as every rule is concerned, but it is an integer
  # vector underneath, so nzchar()/startsWith() on one is an error rather than
  # a wrong answer - the whole check died with "'nzchar()' requires a
  # character vector". `read.csv(stringsAsFactors = TRUE)` and plenty of older
  # code still hand over factors, so convert rather than refuse.
  for (v in names(dt)) {
    if (is.factor(dt[[v]])) {
      data.table::set(dt, j = v, value = as.character(dt[[v]]))
    }
  }

  fill_char_blanks(dt)
  repair_invalid_utf8(dt)
  labels <- fix_invalid_utf8(labels)
  settle_float_noise(dt)

  meta <- data.table::data.table(
    variable = names(dt),
    label = unname(labels[names(dt)]),
    type = vapply(dt, function(col) if (is.character(col)) "Char" else "Num", character(1))
  )

  dataset_label <- attr(raw, "label")
  list(data = dt, meta = meta, label = if (is.null(dataset_label)) NA_character_ else dataset_label)
}

#' Read a CORE test-case `data/` directory into the internal study representation
#' @param path Directory containing `_variables.csv`, one CSV per dataset,
#'   and (usually) `_datasets.csv`.
#' @return A study list, see [read_study()].
#' @noRd
read_study_test_case <- function(path) {
  # strip.white = FALSE for the same reason as build_dataset_from_csv()'s own
  # data read below: fread()'s default trims leading/trailing whitespace,
  # which would silently shorten a `label` value that has a real trailing
  # space in the source data - confirmed against CORE-000019's real fixture,
  # where ML.USUBJID's label is "...Unique Subject " (41 chars, WITH a
  # trailing space) and the rule flags labels longer than 40; stripping that
  # space would wrongly make the label look 40 chars long and miss the
  # violation entirely.
  variables_csv <- data.table::fread(
    file.path(path, "_variables.csv"),
    colClasses = "character", na.strings = character(0), strip.white = FALSE
  )

  # A handful of real CORE test cases ship `_variables.csv` and the per-
  # dataset CSVs but no `_datasets.csv` manifest at all (confirmed against
  # e.g. CORE-000395's own fixtures) - fall back to the dataset names
  # `_variables.csv` itself declares, with no Label available (nothing else
  # names one).
  datasets_csv_path <- file.path(path, "_datasets.csv")
  datasets_csv <- if (file.exists(datasets_csv_path)) {
    data.table::fread(datasets_csv_path, colClasses = "character")
  } else {
    fnames <- unique(variables_csv$dataset)
    data.table::data.table(Filename = fnames, Label = NA_character_)
  }

  datasets <- lapply(seq_len(nrow(datasets_csv)), function(i) {
    build_dataset_from_csv(path, datasets_csv$Filename[i], variables_csv, datasets_csv$Label[i])
  })
  # A dataset's NAME is what the manifest DECLARES, which need not be its file
  # name. USDM test cases truncate the file stem to 27 characters while
  # declaring the full entity: StudyProtocolDocumentVersio.csv carries
  # `Dataset Name` = StudyProtocolDocumentVersion, and that is the entity a
  # USDM rule scopes by and an answer sheet names. Keying on the file name
  # filed CORE-000851's findings under an entity USDM does not have, and left
  # five more rules skipped as "no dataset matches the rule's scope" with the
  # scoped dataset sitting right there. The reference reads the same column
  # (csv_metadata_reader.py:85-89, with upper-cased Filename only as the
  # fallback) and read_study_folder() already honours the declared name.
  # Files are still opened by `Filename`, since the CSV on disk and
  # `_variables.csv`'s `dataset` column both use the truncated form.
  declared_name <- datasets_csv$Filename
  if ("Dataset Name" %in% names(datasets_csv)) {
    given <- datasets_csv[["Dataset Name"]]
    use <- !is.na(given) & nzchar(trimws(given))
    declared_name[use] <- trimws(given[use])
  }
  names(datasets) <- toupper(declared_name)
  # Two files declaring one name would make `study$datasets[[dom]]` return the
  # first and quietly ignore the second. No fixture does this today (0 of the
  # 2028 manifests upstream), but a split-domain test case declaring `AE` twice
  # would, and it is not a thing to discover from a wrong pass rate.
  if (anyDuplicated(names(datasets))) {
    dup <- unique(names(datasets)[duplicated(names(datasets))])
    stop("test case declares one dataset name for several files: ",
         paste(dup, collapse = ", "), call. = FALSE)
  }

  list(datasets = datasets, define = read_define_xml(find_define_xml(path)), ct = NULL, standard = read_env_standard(path))
}

# A CORE test case's `.env` file declares which standard/version its data
# actually conforms to (e.g. "PRODUCT=SENDIG" / "VERSION=3-1") - confirmed
# this is NOT always SDTMIG even for rules that look SDTM-flavored on their
# face (e.g. CORE-000355's own EX fixture is SENDIG 3.1, not SDTMIG). Library
# metadata operators (required_variables, expected_variables, ...) need this
# to pick the right per-standard table rather than silently assuming SDTMIG.
#
# Also checks `_env` (leading underscore, no dot) as a fallback: this
# package's own bundled test fixtures (tests/testthat/fixtures/) rename
# their copies of upstream's `.env` files to `_env`, since R CMD check
# flags shipped dot-files as "most likely included in error" - excluding
# them via .Rbuildignore instead (tried first) silently broke every
# fixture-based test that depends on the declared standard, since a
# missing `.env` looks identical to "no declaration, default to SDTMIG"
# (confirmed via CORE-000355: with .env excluded, its SENDIG-declared AE
# fixture was silently evaluated as SDTMIG instead, masking the real
# behavior the test exists to verify). A real CDISC CORE test-case
# directory (e.g. a fresh upstream clone) always uses `.env`; `_env` is
# purely this package's own packaging workaround.
#' Parse a CORE test case's `.env` (or `_env`) file into a standard/version pair
#' @param path Study directory (may or may not contain `.env`/`_env`).
#' @return `list(product, version)`, both `NA_character_` if absent/unparseable.
#' @noRd
read_env_standard <- function(path) {
  env_path <- file.path(path, ".env")
  if (!file.exists(env_path)) {
    env_path <- file.path(path, "_env")
  }
  if (!file.exists(env_path)) {
    return(list(product = NA_character_, version = NA_character_))
  }
  lines <- readLines(env_path, warn = FALSE)
  # Only lines that actually assign something. A blank line, a comment, or a
  # stray heading has no "=" at all, and strsplit() would yield a one-element
  # piece for it.
  lines <- lines[grepl("=", lines, fixed = TRUE)]
  if (length(lines) == 0) {
    return(list(product = NA_character_, version = NA_character_))
  }
  kv <- strsplit(lines, "=", fixed = TRUE)
  keys <- toupper(trimws(vapply(kv, function(x) x[1], character(1))))
  # An EMPTY value ("VERSION=") is legitimate and common - strsplit drops the
  # trailing empty piece, so such a line yields a length-1 vector. Returning
  # NULL there (as `if` without `else` does) made vapply reject a zero-length
  # result and abort the ENTIRE study read over one blank field, rather than
  # reporting that one field as absent.
  vals <- trimws(vapply(kv, function(x) {
    if (length(x) >= 2) paste(x[-1], collapse = "=") else NA_character_
  }, character(1)))
  list(
    product = toupper(vals[match("PRODUCT", keys)]),
    version = vals[match("VERSION", keys)]
  )
}

#' Locate a dataset's CSV, tolerating a case difference in the declared name
#'
#' A dataset's NAME comes from `_datasets.csv`'s `Filename` or, when that
#' manifest is absent, from `_variables.csv`'s `dataset` column - in whatever
#' case upstream happened to write it. The FILE beside them carries its own
#' case. The two need not agree: a study can declare `TS` and ship `ts.csv`.
#'
#' `read_xpt_dir()` has always matched case-insensitively
#' (`list.files(ignore.case = TRUE)`); this applies the same rule to the CSV
#' path, which assumed the declared case matched the file exactly. On a
#' case-insensitive filesystem (Windows, and macOS by default) that assumption
#' is invisible, because opening `TS.csv` simply returns `ts.csv`. On a
#' case-sensitive one (Linux, so also CRAN's build machines) it is a hard
#' `fread()` error that aborts the whole study read.
#'
#' Falls back to the exact path when there is no unique case-insensitive match,
#' so a missing file still produces `fread()`'s own clear error rather
#' than a silently different one.
#'
#' @param path Study directory.
#' @param fname Dataset name as declared, in any case.
#' @return Path to the CSV to read.
#' @noRd
dataset_csv_path <- function(path, fname) {
  wanted <- paste0(fname, ".csv")
  files <- list.files(path, pattern = "\\.csv$", ignore.case = TRUE)

  # Resolve against the directory listing rather than testing file.exists()
  # on the constructed name. file.exists() is itself case-insensitive on
  # Windows and macOS, so it would answer TRUE for "TS.csv" when the file is
  # ts.csv and hand back a name that does not exist on a case-sensitive
  # filesystem - reintroducing the very platform split this exists to remove.
  # Going through the listing returns the file's REAL name everywhere.
  hit <- files[files == wanted]
  if (length(hit) == 0) {
    hit <- files[tolower(files) == tolower(wanted)]
  }
  if (length(hit) == 1) file.path(path, hit) else file.path(path, wanted)
}

#' Read one test-case dataset CSV, typed per `_variables.csv`
#' @param path Study directory.
#' @param fname Dataset filename (without extension).
#' @param variables_csv Parsed `_variables.csv` table.
#' @param dataset_label This dataset's `_datasets.csv` `Label` value.
#' @return `list(data, meta, label)`, see [read_study()].
#' @noRd
build_dataset_from_csv <- function(path, fname, variables_csv, dataset_label = NA_character_) {
  vmeta <- variables_csv[toupper(variables_csv$dataset) == toupper(fname), ]

  col_classes <- list(
    character = vmeta$variable[vmeta$type == "Char"],
    numeric = vmeta$variable[vmeta$type == "Num"]
  )
  col_classes <- col_classes[lengths(col_classes) > 0]

  # fread()'s default na.strings = "NA" would silently turn a genuine CDISC
  # null-flavor value like TSVALNF = "NA" (real, meaningful text - "Not
  # Applicable") into R's NA, which fill_char_blanks() then rewrites to ""
  # for character columns - indistinguishable from an actually blank field.
  # Numeric columns don't need na.strings at all: fread already parses a
  # genuinely blank numeric field as NA on its own.
  # fread()'s default strip.white = TRUE would also silently trim leading/
  # trailing whitespace from character fields - destroying exactly the kind
  # of data-quality defect CORE conformance rules exist to catch (e.g.
  # CORE-000867's "text variable must not have leading spaces").
  #
  # A dataset can be listed in _datasets.csv with zero matching rows in
  # _variables.csv at all (a real upstream data gap, confirmed for
  # CORE-000094's own "ec" dataset) - fread() errors on an empty-but-typed
  # colClasses list ("colClasses is type list but has no names"), which
  # would otherwise crash the ENTIRE study read over one broken domain.
  # Falling back to auto-detected types for just that one dataset is the
  # only option when upstream's own type declarations are simply absent.
  # `fill` and `header` are both about a CSV whose rows do not all carry the
  # same number of fields, which real exports produce and which fread's
  # defaults handle in two ways that silently lose data:
  #
  #   - a SHORT last row is read as a footer and DISCARDED. CORE-000103's
  #     pr.csv has three records, the third missing its trailing PRSCAT, and
  #     coreval saw two. A violation on that row could never be reported.
  #   - a row with MORE fields than the header makes fread decide the header
  #     is not a header: it invents a `V1` column and names the rest after the
  #     first row's VALUES. The same fixture's ce.csv came back with columns
  #     called `1234.0` and `Fracture` and no CETERM, CECAT or CESCAT at all,
  #     so every rule about them found nothing and looked clean.
  #
  # fill = TRUE pads a short row with NA instead of dropping it, which is also
  # what the reference reads through pandas, and header = TRUE stops the first
  # line being anything but the header.
  #
  # sep = "," is not redundant next to them. fread re-runs separator detection
  # under fill, and these files carry trailing spaces inside fields
  # ("STUDYID ,DOMAIN ,"), so on CORE-000549's sj.csv it chose WHITESPACE and
  # returned 13 columns named V1..V13 from a file whose every line has ten
  # comma-separated fields. The rule then found no RSTGCD and reported nothing.
  # These files are comma-separated by definition; there is nothing to detect.
  fread_args <- list(
    dataset_csv_path(path, fname),
    na.strings = character(0), strip.white = FALSE,
    fill = TRUE, header = TRUE, sep = ","
  )
  if (length(col_classes) > 0) {
    fread_args$colClasses <- col_classes
  }
  # fread warns "Attempt to override column <X> of inherent type 'string'
  # down to 'float64' ignored" when a column declared Num holds a value it
  # reads as text - SAS's "." missing token being the usual cause. The
  # coercion immediately below handles exactly that case properly, so the
  # warning is noise here rather than information; nothing else fread has to
  # say is suppressed.
  dt <- withCallingHandlers(
    do.call(data.table::fread, fread_args),
    warning = function(w) {
      if (grepl("Attempt to override column", conditionMessage(w), fixed = TRUE)) {
        invokeRestart("muffleWarning")
      }
    }
  )
  repair_doubled_quotes(dt, dataset_csv_path(path, fname))

  # A stray space in the header is not part of the variable's name. Left in,
  # the declared variable is invisible: CORE-000793's own fixture writes
  # " MHDY" while its _variables.csv declares MHDY, so the rule asking whether
  # MHDY exists answered no and reported a violation CDISC's engine does not.
  # Values keep their whitespace (fread is called with strip.white = FALSE on
  # purpose); this is only about the names.
  trimmed <- trimws(names(dt))
  if (!identical(trimmed, names(dt)) && !anyDuplicated(trimmed)) {
    data.table::setnames(dt, trimmed)
  }

  # A column declared Num whose data contains SAS's own numeric-missing token
  # (a lone ".") comes back as character: fread reads "." as a string, and
  # colClasses cannot down-cast an inherently-string column to double - it
  # warns and leaves it alone. The column then silently stays character
  # despite being declared numeric, which is the kind of quiet type drift a
  # conformance check should never inherit. Confirmed against CORE-000183's
  # own fixture, where pc.PCSTRESN is declared Num and every value is ".".
  #
  # "." and "" both mean missing for a numeric variable, so they become NA
  # and the column is coerced explicitly. Anything else that will not parse
  # is left alone rather than destroyed - a declared-Num column carrying real
  # text is itself a finding, and silently turning it into NA would hide it.
  declared_num <- vmeta$variable[vmeta$type == "Num"]
  for (v in intersect(declared_num, names(dt))) {
    col <- dt[[v]]
    if (!is.character(col)) {
      next
    }
    blank <- trimws(col) %in% c(".", "")
    parsed <- suppressWarnings(as.numeric(ifelse(blank, NA_character_, col)))
    if (all(is.na(parsed) == (blank | is.na(col)))) {
      data.table::set(dt, j = v, value = parsed)
    }
  }

  # A variable the fixture declares Boolean holds the text "True"/"FALSE", and
  # the rules compare it against a YAML `true`, which reaches here as a logical.
  # Left as text the comparison is R's coercion of TRUE to "TRUE", which does
  # not equal "True", so a row that plainly satisfies the rule reads as clean.
  # It worked for "FALSE" purely because that casing happens to match.
  #
  # The reference gets this for free: pandas' CSV parser turns boolean-looking
  # text into real booleans and leaves NaN for a blank, so its comparison is
  # bool against bool. This does the same, driven by the declared type rather
  # than by sniffing values, so a "Y"/"N" or "TRUE"/"FALSE" column that nobody
  # declared Boolean is untouched.
  declared_bool <- vmeta$variable[tolower(vmeta$type) == "boolean"]
  for (v in intersect(declared_bool, names(dt))) {
    col <- dt[[v]]
    if (!is.character(col)) {
      next
    }
    key <- toupper(trimws(col))
    parsed <- ifelse(key %in% c("TRUE", "T", "Y", "YES"), TRUE,
                     ifelse(key %in% c("FALSE", "F", "N", "NO"), FALSE, NA))
    # Only when every populated value really is boolean text. Anything else in
    # a column declared Boolean is itself worth reporting, and quietly turning
    # it into NA would hide it.
    populated <- !is.na(col) & nzchar(key)
    if (all(!is.na(parsed[populated]))) {
      data.table::set(dt, j = v, value = as.logical(parsed))
    }
  }

  # A column with no values at all comes back logical, because that is what
  # fread infers for a file of nothing but NA. It is not a logical column; it
  # is a column of unknown type that happens to be empty, and every string
  # operator applied to one raises "non-character object(s)" rather than
  # answering. That took out 39 USDM rules at once, each reported as an
  # evaluation failure rather than as the blank column it really is.
  #
  # Only the all-missing case. A column holding real TRUE/FALSE values is a
  # genuine logical, and several USDM rules compare against one, so converting
  # those would break them instead.
  for (v in names(dt)) {
    col <- dt[[v]]
    if (is.logical(col) && all(is.na(col))) {
      data.table::set(dt, j = v, value = rep(NA_character_, length(col)))
    }
  }

  fill_char_blanks(dt)

  meta <- data.table::data.table(
    variable = vmeta$variable,
    label = vmeta$label,
    type = vmeta$type
  )

  list(data = dt, meta = meta, label = dataset_label)
}
