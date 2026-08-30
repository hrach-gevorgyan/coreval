#' Read a study into coreval's internal representation
#'
#' Detects whether `path` is a directory of XPT datasets (a real study) or a
#' CORE test-case `data/` directory (`.env` + `_datasets.csv` +
#' `_variables.csv` + one CSV per dataset), and reads either into the same
#' internal representation, so the evaluator never has to know which one it
#' got.
#'
#' Character columns use `""` for blank/missing (never `NA`) to match how
#' SAS XPT round-trips blanks; numeric columns use `NA`. Column types are
#' taken from the source (XPT's own types, or `_variables.csv`'s declared
#' `Char`/`Num`) rather than guessed from the data, so numeric-looking
#' identifiers (e.g. `"007"`) are never silently coerced.
#'
#' @param path Directory path.
#' @return A study object: `list(datasets = <named list of domain ->
#'   list(data, meta, label)>, define = NULL, ct = NULL, standard =
#'   list(product, version))`. Each `data` is a [data.table::data.table()];
#'   each `meta` is a data.table with columns `variable`, `label`, `type`;
#'   `label` is the dataset's own label (e.g. `"Adverse Events"`), or `NA` if
#'   unavailable. `standard` is the study's declared standard/version (e.g.
#'   `list(product = "SDTMIG", version = "3-4")`), read from a CORE test
#'   case's `.env` file - both `NA` for a real XPT-based study (no `.env`).
#' @examples
#' dir <- tempfile("coreval_study_")
#' dir.create(dir)
#' haven::write_xpt(data.frame(USUBJID = c("1", "2"), AGE = c(30, 65)), file.path(dir, "dm.xpt"))
#' study <- read_study(dir)
#' study$datasets$DM$data
#' unlink(dir, recursive = TRUE)
#' @export
read_study <- function(path) {
  if (file.exists(file.path(path, "_datasets.csv"))) {
    read_study_test_case(path)
  } else {
    read_study_xpt(path)
  }
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

#' Read a directory of XPT datasets into the internal study representation
#' @param path Directory containing `.xpt` files.
#' @return A study list, see [read_study()].
#' @noRd
read_study_xpt <- function(path) {
  files <- list.files(path, pattern = "\\.xpt$", ignore.case = TRUE, full.names = TRUE)
  datasets <- lapply(files, function(f) build_dataset_from_xpt(haven::read_xpt(f)))
  names(datasets) <- toupper(tools::file_path_sans_ext(basename(files)))
  list(datasets = datasets, define = NULL, ct = NULL, standard = list(product = NA_character_, version = NA_character_))
}

#' Convert one `haven::read_xpt()` data frame into a `list(data, meta)` dataset entry
#' @param raw Data frame returned by [haven::read_xpt()].
#' @return `list(data, meta)`, see [read_study()].
#' @noRd
build_dataset_from_xpt <- function(raw) {
  dt <- data.table::as.data.table(raw)
  labels <- vapply(raw, function(col) {
    lbl <- attr(col, "label")
    if (is.null(lbl)) NA_character_ else lbl
  }, character(1))

  fill_char_blanks(dt)

  meta <- data.table::data.table(
    variable = names(dt),
    label = unname(labels[names(dt)]),
    type = vapply(dt, function(col) if (is.character(col)) "Char" else "Num", character(1))
  )

  dataset_label <- attr(raw, "label")
  list(data = dt, meta = meta, label = if (is.null(dataset_label)) NA_character_ else dataset_label)
}

#' Read a CORE test-case `data/` directory into the internal study representation
#' @param path Directory containing `_datasets.csv`, `_variables.csv`, and one CSV per dataset.
#' @return A study list, see [read_study()].
#' @noRd
read_study_test_case <- function(path) {
  datasets_csv <- data.table::fread(file.path(path, "_datasets.csv"), colClasses = "character")
  variables_csv <- data.table::fread(file.path(path, "_variables.csv"), colClasses = "character")

  datasets <- lapply(seq_len(nrow(datasets_csv)), function(i) {
    build_dataset_from_csv(path, datasets_csv$Filename[i], variables_csv, datasets_csv$Label[i])
  })
  names(datasets) <- toupper(datasets_csv$Filename)

  list(datasets = datasets, define = NULL, ct = NULL, standard = read_env_standard(path))
}

# A CORE test case's `.env` file declares which standard/version its data
# actually conforms to (e.g. "PRODUCT=SENDIG" / "VERSION=3-1") - confirmed
# this is NOT always SDTMIG even for rules that look SDTM-flavored on their
# face (e.g. CORE-000355's own EX fixture is SENDIG 3.1, not SDTMIG). Library
# metadata operators (required_variables, expected_variables, ...) need this
# to pick the right per-standard table rather than silently assuming SDTMIG.
#' Parse a CORE test case's `.env` file into a standard/version pair
#' @param path Study directory (may or may not contain `.env`).
#' @return `list(product, version)`, both `NA_character_` if `.env` is absent/unparseable.
#' @noRd
read_env_standard <- function(path) {
  env_path <- file.path(path, ".env")
  if (!file.exists(env_path)) {
    return(list(product = NA_character_, version = NA_character_))
  }
  lines <- readLines(env_path, warn = FALSE)
  kv <- strsplit(lines, "=", fixed = TRUE)
  keys <- toupper(trimws(vapply(kv, function(x) x[1], character(1))))
  vals <- trimws(vapply(kv, function(x) if (length(x) >= 2) paste(x[-1], collapse = "="), character(1)))
  list(
    product = toupper(vals[match("PRODUCT", keys)]),
    version = vals[match("VERSION", keys)]
  )
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
  dt <- data.table::fread(
    file.path(path, paste0(fname, ".csv")), colClasses = col_classes,
    na.strings = character(0), strip.white = FALSE
  )

  fill_char_blanks(dt)

  meta <- data.table::data.table(
    variable = vmeta$variable,
    label = vmeta$label,
    type = vmeta$type
  )

  list(data = dt, meta = meta, label = dataset_label)
}
