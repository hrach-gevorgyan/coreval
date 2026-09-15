# Reads CDISC Dataset-JSON and Dataset-NDJSON, the formats CDISC publishes as
# the successor to XPT.
#
# `jsonlite` is a SUGGESTS dependency, not an Import, exactly as `xml2` is for
# Define-XML: the runtime footprint stays `data.table` + `haven`, and a study
# in one of these formats is readable only when the package is installed. Asked
# to read one without it, this raises rather than reporting an empty study.
#
# The two formats carry the same content in two shapes. A `.json` file is one
# object with the metadata and a `rows` array. A `.ndjson` file puts that same
# metadata object on the first line and one row array on each line after it, so
# a writer can stream it. Both are handled here by reducing them to the same
# pair: the metadata object, and the rows.
#
# On a file it cannot make sense of, this RAISES. The reference returns an
# empty DataFrame when the file fails schema validation
# (`dataset_json_reader.py`), which turns a broken file into a dataset with no
# rows, and a dataset with no rows into a clean bill of health. That is the one
# thing this package must never do.

#' Is Dataset-JSON support available (i.e. is `jsonlite` installed)?
#' @return `TRUE` if Dataset-JSON files can be read.
#' @noRd
dataset_json_available <- function() {
  requireNamespace("jsonlite", quietly = TRUE)
}

#' Map a Dataset-JSON `dataType` to coreval's `Char`/`Num`
#'
#' The declaration is used rather than the values, for the same reason the CSV
#' reader trusts `_variables.csv`: a column that happens to hold only digits in
#' one extract is still a text column, and letting the data decide makes the
#' type depend on which rows you were sent.
#'
#' `datetime`, `date`, `time` and `URI` are text. SDTM carries an ISO 8601
#' string in `--DTC`, and the date operators parse that string themselves;
#' turning it into an R date here would lose the partial dates
#' (`2024-03`, `2024`) that the incomplete-date rules exist to find.
#'
#' @param data_type A `dataType` string from a Dataset-JSON column.
#' @return `"Char"` or `"Num"`.
#' @noRd
dataset_json_column_type <- function(data_type) {
  numeric_types <- c("integer", "decimal", "float", "double")
  if (isTRUE(tolower(data_type) %in% numeric_types)) "Num" else "Char"
}

#' Turn a Dataset-JSON metadata object plus its rows into a dataset entry
#' @param meta_obj The parsed metadata object (everything but the rows).
#' @param rows A character or numeric matrix, one row per record.
#' @param source A file path, used only in error messages.
#' @return `list(data, meta, label)`, see [read_study()].
#' @noRd
build_dataset_from_dataset_json <- function(meta_obj, rows, source) {
  columns <- meta_obj$columns
  if (is.null(columns) || NROW(columns) == 0) {
    stop("Dataset-JSON file declares no columns: ", basename(source), call. = FALSE)
  }
  # jsonlite turns an array of objects into a data frame when every object has
  # the same fields, and leaves it a list when they do not. Both are handled,
  # so an optional field missing on one column is not an error.
  field <- function(name) {
    if (is.data.frame(columns)) {
      if (!name %in% names(columns)) return(rep(NA_character_, nrow(columns)))
      as.character(columns[[name]])
    } else {
      vapply(columns, function(col) {
        value <- col[[name]]
        if (is.null(value)) NA_character_ else as.character(value)[[1]]
      }, character(1))
    }
  }
  names_ <- field("name")
  labels <- field("label")
  types <- vapply(field("dataType"), dataset_json_column_type, character(1),
                  USE.NAMES = FALSE)
  n_col <- length(names_)

  # A rows array that did not simplify to a matrix of exactly this width is a
  # ragged file. Refusing is the point: padding it would invent values and
  # dropping it would lose records, and both look like clean data afterwards.
  n_row <- 0L
  if (!is.null(rows) && length(rows) > 0) {
    if (!is.matrix(rows) || ncol(rows) != n_col) {
      stop("Dataset-JSON file is malformed: ", basename(source),
           " declares ", n_col, " columns, but its rows do not all have ",
           n_col, " values.", call. = FALSE)
    }
    n_row <- nrow(rows)
  }

  # `records` is required by the schema and states how many rows the file
  # should hold, which makes a truncated transfer detectable for free. The
  # reference does not compare the two. Refusing matters here: reading 300 of
  # 500 rows and carrying on means every rule reports clean for the 200 that
  # never arrived, and the report looks like a finished check.
  declared_records <- meta_obj$records
  if (!is.null(declared_records) && length(declared_records) == 1 &&
      !is.na(suppressWarnings(as.integer(declared_records)))) {
    expected <- as.integer(declared_records)
    if (expected != n_row) {
      stop("Dataset-JSON file is incomplete: ", basename(source), " says it has ",
           expected, " record", if (expected == 1L) "" else "s",
           " but carries ", n_row, ".", call. = FALSE)
    }
  }

  cols <- lapply(seq_len(n_col), function(j) {
    values <- if (n_row == 0L) character(0) else rows[, j]
    if (identical(types[[j]], "Num")) {
      suppressWarnings(as.numeric(values))
    } else {
      as.character(values)
    }
  })
  names(cols) <- names_
  dt <- data.table::as.data.table(cols)
  fill_char_blanks(dt)

  meta <- data.table::data.table(
    variable = names_,
    label = ifelse(is.na(labels), NA_character_, labels),
    type = types
  )
  label <- meta_obj$label
  out <- list(data = dt, meta = meta,
              label = if (is.null(label) || !nzchar(label)) NA_character_ else as.character(label)[[1]])
  # Carried as an attribute rather than a fourth element, so a dataset entry
  # keeps the same shape as one built from XPT or CSV and nothing downstream
  # has to know where it came from.
  declared_name <- meta_obj$name
  if (!is.null(declared_name) && nzchar(declared_name)) {
    attr(out, "dataset_name") <- toupper(as.character(declared_name)[[1]])
  }
  out
}

#' Read one Dataset-JSON (`.json`) file
#' @param path Path to the file.
#' @return `list(data, meta, label)`, see [read_study()].
#' @noRd
read_dataset_json <- function(path) {
  if (!dataset_json_available()) {
    stop("reading Dataset-JSON needs the 'jsonlite' package: ",
         "install.packages(\"jsonlite\")", call. = FALSE)
  }
  parsed <- tryCatch(
    jsonlite::fromJSON(path, simplifyVector = TRUE),
    error = function(e) {
      stop("not valid JSON: ", basename(path), " (", conditionMessage(e), ")",
           call. = FALSE)
    }
  )
  build_dataset_from_dataset_json(parsed, parsed$rows, path)
}

#' Read one Dataset-NDJSON (`.ndjson`) file
#'
#' The metadata object is the first line and every line after it is one row.
#' Read line by line rather than as one document, which is the whole reason the
#' format exists: a study dataset need never be held in memory twice.
#'
#' @param path Path to the file.
#' @return `list(data, meta, label)`, see [read_study()].
#' @noRd
read_dataset_ndjson <- function(path) {
  if (!dataset_json_available()) {
    stop("reading Dataset-NDJSON needs the 'jsonlite' package: ",
         "install.packages(\"jsonlite\")", call. = FALSE)
  }
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  lines <- lines[nzchar(trimws(lines))]
  if (length(lines) == 0) {
    stop("Dataset-NDJSON file is empty: ", basename(path), call. = FALSE)
  }
  header <- tryCatch(
    jsonlite::fromJSON(lines[[1]], simplifyVector = TRUE),
    error = function(e) {
      stop("first line of ", basename(path), " is not valid JSON metadata (",
           conditionMessage(e), ")", call. = FALSE)
    }
  )
  rows <- NULL
  if (length(lines) > 1) {
    # One fromJSON over the lines wrapped as an array, rather than one call per
    # line: the same simplification then applies to the whole block, so a
    # ragged file still comes back as a list and is still caught below.
    rows <- tryCatch(
      jsonlite::fromJSON(paste0("[", paste(lines[-1], collapse = ","), "]"),
                         simplifyVector = TRUE),
      error = function(e) {
        stop("a data line of ", basename(path), " is not valid JSON (",
             conditionMessage(e), ")", call. = FALSE)
      }
    )
  }
  build_dataset_from_dataset_json(header, rows, path)
}

#' Read a directory of Dataset-JSON / Dataset-NDJSON files
#'
#' The dataset's name comes from the file's own `name` field where it has one,
#' not from the file name. Define-XML names a dataset in `ItemGroupDef`, and a
#' Dataset-JSON repeats it; a file renamed on the way out of a transfer should
#' not silently rename the domain with it.
#'
#' @param path Directory containing `.json` or `.ndjson` files.
#' @return A study list, see [read_study()].
#' @noRd
read_study_dataset_json <- function(path) {
  files <- list.files(path, pattern = "[.](json|ndjson)$", ignore.case = TRUE,
                      full.names = TRUE)
  datasets <- lapply(files, function(f) {
    if (grepl("[.]ndjson$", f, ignore.case = TRUE)) {
      read_dataset_ndjson(f)
    } else {
      read_dataset_json(f)
    }
  })
  declared <- vapply(datasets, function(d) {
    nm <- attr(d, "dataset_name")
    if (is.null(nm)) NA_character_ else nm
  }, character(1))
  fallback <- toupper(tools::file_path_sans_ext(basename(files)))
  names(datasets) <- ifelse(is.na(declared), fallback, declared)
  list(datasets = datasets,
       define = read_define_xml(find_define_xml(path)), ct = NULL,
       standard = list(product = NA_character_, version = NA_character_))
}

#' Is this file a USDM study document?
#'
#' A USDM document and a Dataset-JSON file are both `.json` and land in the
#' same folder scan, so they have to be told apart before either is read. Every
#' one of the 258 USDM documents CDISC publishes as rule fixtures carries the
#' same four top-level keys, and `usdmVersion` is the one no Dataset-JSON file
#' has. Read as a Dataset-JSON, such a file is refused for declaring no
#' columns, which is a confusing way to say "this is a different format".
#'
#' Only the head of the file is read: these documents run to megabytes and the
#' question is answered in the first line or two.
#'
#' @param path Path to a `.json` file.
#' @return `TRUE` for a USDM study document.
#' @noRd
is_usdm_document <- function(path) {
  head_text <- tryCatch(
    paste(readLines(path, n = 40L, warn = FALSE, encoding = "UTF-8"), collapse = ""),
    error = function(e) ""
  )
  grepl("\"usdmVersion\"", head_text, fixed = TRUE) ||
    grepl("\"study\"", head_text, fixed = TRUE)
}

#' Read a folder holding a USDM study document
#'
#' USDM is a graph, and its rules come in two shapes. 96 are JSONata
#' expressions over the whole document, so the document is carried as text and
#' handed to the evaluator unchanged. 157 are ordinary Record Data checks over
#' per-entity tables, so the document is also flattened into those tables, the
#' way the reference flattens it (see read_usdm.R).
#'
#' Flattening needs `jsonlite`, which is a Suggests. Without it the document is
#' still carried, so the JSONata rules run and the tabular ones find nothing in
#' scope and are skipped.
#'
#' @param path Folder holding the document.
#' @return A study object carrying `document` and `datasets`.
#' @noRd
read_study_usdm <- function(path) {
  files <- list.files(path, pattern = "[.]json$", ignore.case = TRUE,
                      full.names = TRUE)
  files <- Filter(is_usdm_document, files)
  if (length(files) > 1) {
    stop("this folder holds ", length(files), " USDM documents; a study is one",
         call. = FALSE)
  }
  document <- paste(readLines(files[[1]], warn = FALSE, encoding = "UTF-8"),
                    collapse = "\n")
  found <- regmatches(document,
                      regexpr('"usdmVersion"[[:space:]]*:[[:space:]]*"[^"]*"', document))
  version <- if (length(found) == 1L) {
    gsub('"', "", sub('^"usdmVersion"[[:space:]]*:[[:space:]]*', "", found), fixed = TRUE)
  } else {
    NA_character_
  }
  datasets <- if (requireNamespace("jsonlite", quietly = TRUE)) {
    usdm_datasets(tryCatch(
      jsonlite::fromJSON(document, simplifyVector = FALSE),
      error = function(e) {
        stop("not valid JSON: ", basename(files[[1]]), " (", conditionMessage(e), ")",
             call. = FALSE)
      }
    ))
  } else {
    list()
  }
  list(datasets = datasets, define = NULL, ct = NULL,
       standard = list(product = "USDM", version = version),
       document = document)
}
